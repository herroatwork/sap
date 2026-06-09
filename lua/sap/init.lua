local pickers = require('telescope.pickers')
local finders = require('telescope.finders')
local conf = require('telescope.config').values
local actions = require('telescope.actions')
local action_state = require('telescope.actions.state')
local previewers = require('telescope.previewers')
local putils = require('telescope.previewers.utils')
local core = require('sap.core')

local sap_ns = vim.api.nvim_create_namespace('sap_diff')

local KIND_HL = { add = 'SapDiffAdd', del = 'SapDiffDelete', hunk = 'SapDiffChange', header = 'Comment' }

-- how long to wait for the cursor to settle before spawning `sl diff` for the
-- previewed entry, so flying through the list never spawns a process per entry.
local PREVIEW_DEBOUNCE_MS = 50
-- cap diff rendering; a giant generated/lockfile diff shouldn't make a single
-- preview janky (only the top is visible in a preview pane anyway).
local MAX_PREVIEW_LINES = 2000

-- pull the diff *color* from the colorscheme but apply it as a foreground only,
-- so the preview shows colored text (like `git`/`sl diff` in a terminal) rather
-- than the solid full-line background bars you get from applying DiffAdd/
-- DiffDelete directly (those carry a background in many colorschemes). we take
-- whichever of fg/bg a group defines, since schemes disagree on which they use.
local function setup_diff_hl()
	-- prefer an explicit foreground from the first candidate that has one
	-- (vivid, fg-based); only borrow a background color if none do; else a
	-- sensible default. checking DiffAdd/DiffDelete first favors the vivid
	-- vimdiff palette over the often-pale Added/Removed/@diff.* groups.
	local function pick(groups, fallback)
		for _, g in ipairs(groups) do
			local h = vim.api.nvim_get_hl(0, { name = g, link = false })
			if h and h.fg then
				return h.fg
			end
		end
		for _, g in ipairs(groups) do
			local h = vim.api.nvim_get_hl(0, { name = g, link = false })
			if h and h.bg then
				return h.bg
			end
		end
		return fallback
	end
	vim.api.nvim_set_hl(0, 'SapDiffAdd', { fg = pick({ 'DiffAdd', 'Added', 'diffAdded', '@diff.plus' }, 0x98c379) })
	vim.api.nvim_set_hl(
		0,
		'SapDiffDelete',
		{ fg = pick({ 'DiffDelete', 'Removed', 'diffRemoved', '@diff.minus' }, 0xe06c75) }
	)
	vim.api.nvim_set_hl(
		0,
		'SapDiffChange',
		{ fg = pick({ 'DiffChange', 'Changed', 'diffChanged', '@diff.delta' }, 0x61afef) }
	)
end

-- derive diff colors once now (and again on every colorscheme change) instead of
-- recomputing them on the latency-critical path of every picker open.
setup_diff_hl()
vim.api.nvim_create_autocmd('ColorScheme', {
	group = vim.api.nvim_create_augroup('sap_diff_hl', { clear = true }),
	callback = setup_diff_hl,
})

local function sl_root(cwd)
	local res = vim.system({ 'sl', 'root' }, { text = true, cwd = cwd }):wait()
	return (res.code == 0) and vim.trim(res.stdout or '') or nil
end

-- render an `sl diff` result into a preview buffer: a failure as a plain message
-- (not run through the diff highlighter), success as our foreground-only diff
-- highlights, capped for huge diffs. returns true once content was rendered.
local function render_diff(bufnr, winid, res)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return false
	end
	if res.code ~= 0 then
		local msg = (res.stderr and res.stderr ~= '' and res.stderr)
			or ('sl diff failed (exit ' .. tostring(res.code) .. ')')
		putils.set_preview_message(bufnr, winid, vim.trim(msg))
		return false
	end
	local lines = core.cap(vim.split(res.stdout or '', '\n', { trimempty = true }), MAX_PREVIEW_LINES)
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
	vim.api.nvim_buf_clear_namespace(bufnr, sap_ns, 0, -1)
	for _, h in ipairs(core.diff_highlights(lines)) do
		vim.api.nvim_buf_set_extmark(bufnr, sap_ns, h.line, 0, {
			end_row = h.line + 1,
			end_col = 0,
			hl_group = KIND_HL[h.kind],
		})
	end
	return true
end

local function open_picker(opts, cwd, rev, entries)
	local loaded = {} -- path -> true once its preview buffer is populated
	local token = 0 -- bumped on every selection; invalidates stale debounced spawns

	pickers
		.new(opts, {
			prompt_title = 'sap',
			finder = finders.new_table({
				results = entries,
				entry_maker = function(e)
					local sign, hl = core.sign(e.status)
					local dir, file = e.path:match('^(.+/)([^/]+)$')
					local display = function()
						local text
						local highlights = { { { 1, 2 }, hl } }
						if dir then
							text = string.format(' %s %s%s', sign, dir, file)
							table.insert(highlights, { { 3, 3 + #dir }, 'Comment' })
						else
							text = string.format(' %s %s', sign, e.path)
						end
						return text, highlights
					end
					return {
						value = e,
						ordinal = e.path,
						display = display,
						path = e.abs,
					}
				end,
			}),
			sorter = conf.generic_sorter(opts),
			previewer = previewers.new_buffer_previewer({
				title = 'sap preview',
				-- one preview buffer per file (keyed by path); the `loaded` guard
				-- below makes `sl diff` run once per file, not on every revisit.
				get_buffer_by_name = function(_, entry)
					return entry.value.path
				end,
				define_preview = function(self, entry)
					-- every selection change bumps the token, cancelling any diff
					-- spawn still waiting out its debounce for a now-stale entry.
					token = token + 1
					local my_token = token
					local key = entry.value.path
					if loaded[key] then
						return -- already populated; telescope shows the cached buffer
					end
					local bufnr = self.state.bufnr
					if entry.value.status == '?' then
						-- untracked: nothing to diff against, so show the file
						-- itself, highlighted by treesitter/syntax.
						conf.buffer_previewer_maker(entry.path, bufnr, {
							bufname = self.state.bufname,
							winid = self.state.winid,
						})
						loaded[key] = true
						return
					end
					-- tracked: debounce, then run `sl diff` async (anchored to the
					-- repo cwd) so neither scrolling nor sl's ~200ms startup blocks.
					local winid = self.state.winid
					vim.defer_fn(function()
						if my_token ~= token then
							return -- cursor moved on before the diff settled
						end
						if not vim.api.nvim_buf_is_valid(bufnr) then
							return
						end
						vim.system(core.diff_command(entry.path, rev), { text = true, cwd = cwd }, function(res)
							vim.schedule(function()
								if my_token ~= token then
									return -- moved on while sl was running
								end
								if render_diff(bufnr, winid, res) then
									loaded[key] = true
								end
							end)
						end)
					end, PREVIEW_DEBOUNCE_MS)
				end,
			}),
			attach_mappings = function(_, map)
				actions.select_default:replace(function(prompt_bufnr)
					local sel = action_state.get_selected_entry()
					if vim.fn.filereadable(sel.path) == 0 then
						-- removed/missing in this stack: don't `:edit` it into a
						-- phantom [New File] that could recreate the file on save.
						vim.notify(
							'sap: ' .. sel.value.path .. ' is not on disk (removed in this stack)',
							vim.log.levels.WARN
						)
						return
					end
					actions.close(prompt_bufnr)
					vim.cmd('edit ' .. vim.fn.fnameescape(sel.path))
				end)
				return true
			end,
		})
		:find()
end

local function sl_changed(opts)
	opts = opts or {}

	-- anchor every sl call to the current file's directory (falling back to the
	-- editor cwd) so the picker shows the stack of the repo you're working in,
	-- regardless of nvim's global cwd.
	local cwd = vim.fn.expand('%:p:h')
	if cwd == '' then
		cwd = vim.fn.getcwd()
	end

	-- run status async so pressing the keymap never freezes the editor on sl's
	-- ~200ms startup; the picker opens from the callback once status returns.
	local rev = core.STACK_BASE
	vim.system(core.status_command(rev), { text = true, cwd = cwd }, function(s)
		vim.schedule(function()
			-- a repo with no public ancestor (fresh, nothing pushed) makes the
			-- stack-base revset empty and sl aborts; retry without --rev (rare).
			if s.code ~= 0 then
				local plain = vim.system(core.status_command(nil), { text = true, cwd = cwd }):wait()
				if plain.code == 0 then
					rev, s = nil, plain
				end
			end

			local stdout = vim.split(s.stdout or '', '\n', { trimempty = true })
			local stderr = vim.split(s.stderr or '', '\n', { trimempty = true })
			local root = (s.code == 0) and sl_root(cwd) or nil
			local result = core.classify(stdout, stderr, s.code, root)

			if result.kind == 'error' then
				vim.notify('sap: ' .. result.msg, vim.log.levels.ERROR)
				return
			elseif result.kind == 'empty' then
				vim.notify('sap: ' .. result.msg, vim.log.levels.INFO)
				return
			end

			open_picker(opts, cwd, rev, result.entries)
		end)
	end)
end

return { sl_changed = sl_changed }
