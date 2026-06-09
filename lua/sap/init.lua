local pickers = require('telescope.pickers')
local finders = require('telescope.finders')
local conf = require('telescope.config').values
local actions = require('telescope.actions')
local action_state = require('telescope.actions.state')
local previewers = require('telescope.previewers')
local putils = require('telescope.previewers.utils')
local core = require('sap.core')
local config = require('sap.config')

local sap_ns = vim.api.nvim_create_namespace('sap_diff')

local KIND_HL = {
	add = 'SapDiffAdd',
	del = 'SapDiffDelete',
	hunk = 'SapDiffChange',
	header = 'Comment',
}

-- how long to wait for the cursor to settle before spawning `sl diff`, so flying
-- through the list never spawns a process per entry.
local PREVIEW_DEBOUNCE_MS = 50
-- cap diff rendering; a giant generated/lockfile diff shouldn't jank a preview.
local MAX_PREVIEW_LINES = 2000

-- Define the SapDiff* preview highlights. Each color is the user's explicit
-- override (config.highlights.*) if set, otherwise derived from the colorscheme:
-- the first candidate group that defines a foreground (vivid, fg-based), else a
-- borrowed background, else a sensible default -- always applied as a foreground
-- so previews show colored text rather than full-line background bars.
local function setup_diff_hl()
	local hl = config.options.highlights
	local function pick(override, groups, fallback)
		if override then
			return override
		end
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
	vim.api.nvim_set_hl(0, 'SapDiffAdd', {
		fg = pick(
			hl.add,
			{ 'DiffAdd', 'Added', 'diffAdded', '@diff.plus' },
			0x98c379
		),
	})
	vim.api.nvim_set_hl(0, 'SapDiffDelete', {
		fg = pick(
			hl.delete,
			{ 'DiffDelete', 'Removed', 'diffRemoved', '@diff.minus' },
			0xe06c75
		),
	})
	vim.api.nvim_set_hl(0, 'SapDiffChange', {
		fg = pick(
			hl.change,
			{ 'DiffChange', 'Changed', 'diffChanged', '@diff.delta' },
			0x61afef
		),
	})
end

-- derive diff colors once now (and again on every colorscheme change) instead of
-- recomputing them on the latency-critical path of every picker open.
setup_diff_hl()
vim.api.nvim_create_autocmd('ColorScheme', {
	group = vim.api.nvim_create_augroup('sap_diff_hl', { clear = true }),
	callback = setup_diff_hl,
})

local function sl_root(sl_bin, cwd)
	local res = vim.system({ sl_bin, 'root' }, { text = true, cwd = cwd })
		:wait()
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
	local lines = core.cap(
		vim.split(res.stdout or '', '\n', { trimempty = true }),
		MAX_PREVIEW_LINES
	)
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

local function make_previewer(cwd, rev, cfg)
	local loaded = {} -- path -> true once its preview buffer is populated
	local token = 0 -- bumped on every selection; invalidates stale debounced spawns
	return previewers.new_buffer_previewer({
		title = 'sap preview',
		-- one preview buffer per file (keyed by path); the `loaded` guard makes
		-- `sl diff` run once per file, not on every revisit.
		get_buffer_by_name = function(_, entry)
			return entry.value.path
		end,
		define_preview = function(self, entry)
			-- every selection change bumps the token, cancelling any diff spawn
			-- still waiting out its debounce for a now-stale entry.
			token = token + 1
			local my_token = token
			local key = entry.value.path
			if loaded[key] then
				return
			end
			local bufnr = self.state.bufnr
			if entry.value.status == '?' then
				-- untracked: show the file itself, treesitter/syntax-highlighted.
				conf.buffer_previewer_maker(entry.path, bufnr, {
					bufname = self.state.bufname,
					winid = self.state.winid,
				})
				loaded[key] = true
				return
			end
			-- tracked: debounce, then run `sl diff` async (anchored to the repo
			-- cwd) so neither scrolling nor sl's ~200ms startup blocks.
			local winid = self.state.winid
			vim.defer_fn(function()
				if my_token ~= token then
					return
				end
				if not vim.api.nvim_buf_is_valid(bufnr) then
					return
				end
				vim.system(
					core.diff_command(cfg.sl_bin, entry.path, rev),
					{ text = true, cwd = cwd },
					function(res)
						vim.schedule(function()
							if my_token ~= token then
								return
							end
							if render_diff(bufnr, winid, res) then
								loaded[key] = true
							end
						end)
					end
				)
			end, PREVIEW_DEBOUNCE_MS)
		end,
	})
end

local function open_picker(opts, cwd, rev, entries, cfg)
	pickers
		.new(opts, {
			prompt_title = 'sap',
			finder = finders.new_table({
				results = entries,
				entry_maker = function(e)
					local sign, hl = core.sign(cfg.signs, e.status)
					local dir, file = e.path:match('^(.+/)([^/]+)$')
					local display = function()
						local text
						local highlights = { { { 1, 2 }, hl } }
						if dir then
							text = string.format(' %s %s%s', sign, dir, file)
							table.insert(
								highlights,
								{ { 3, 3 + #dir }, 'Comment' }
							)
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
			previewer = cfg.preview and make_previewer(cwd, rev, cfg) or false,
			attach_mappings = function(_, map)
				actions.select_default:replace(function(prompt_bufnr)
					local sel = action_state.get_selected_entry()
					if vim.fn.filereadable(sel.path) == 0 then
						-- removed/missing in this stack: don't `:edit` it into a
						-- phantom [New File] that could recreate the file on save.
						vim.notify(
							'sap: '
								.. sel.value.path
								.. ' is not on disk (removed in this stack)',
							vim.log.levels.WARN
						)
						return
					end
					actions.close(prompt_bufnr)
					vim.cmd('edit ' .. vim.fn.fnameescape(sel.path))
				end)
				-- user-defined extra mappings: { i = { lhs = fn }, n = { ... } }
				for mode, maps in pairs(cfg.mappings or {}) do
					for lhs, rhs in pairs(maps) do
						map(mode, lhs, rhs)
					end
				end
				return true
			end,
		})
		:find()
end

local function sl_changed(opts)
	opts = opts or {}
	local cfg = config.resolve(opts)

	-- anchor every sl call to the current file's directory (falling back to the
	-- editor cwd) so the picker shows the stack of the repo you're working in,
	-- regardless of nvim's global cwd.
	local cwd = vim.fn.expand('%:p:h')
	if cwd == '' then
		cwd = vim.fn.getcwd()
	end

	-- run status async so pressing the keymap never freezes the editor on sl's
	-- ~200ms startup; the picker opens from the callback once status returns.
	local rev = cfg.revset
	vim.system(
		core.status_command(cfg.sl_bin, rev),
		{ text = true, cwd = cwd },
		function(s)
			vim.schedule(function()
				-- a repo with no public ancestor (fresh, nothing pushed) makes the
				-- stack-base revset empty and sl aborts; retry without --rev (rare).
				if s.code ~= 0 then
					local plain = vim.system(
						core.status_command(cfg.sl_bin, nil),
						{ text = true, cwd = cwd }
					):wait()
					if plain.code == 0 then
						rev, s = nil, plain
					end
				end

				local stdout =
					vim.split(s.stdout or '', '\n', { trimempty = true })
				local stderr =
					vim.split(s.stderr or '', '\n', { trimempty = true })
				local root = (s.code == 0) and sl_root(cfg.sl_bin, cwd) or nil
				local result = core.classify(stdout, stderr, s.code, root)

				if result.kind == 'error' then
					vim.notify('sap: ' .. result.msg, vim.log.levels.ERROR)
					return
				elseif result.kind == 'empty' then
					vim.notify('sap: ' .. result.msg, vim.log.levels.INFO)
					return
				end

				open_picker(opts, cwd, rev, result.entries, cfg)
			end)
		end
	)
end

local function setup(opts)
	config.setup(opts)
	setup_diff_hl() -- re-derive in case highlight overrides changed
end

return { sl_changed = sl_changed, setup = setup }
