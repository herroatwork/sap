local pickers = require('telescope.pickers')
local finders = require('telescope.finders')
local conf = require('telescope.config').values
local actions = require('telescope.actions')
local action_state = require('telescope.actions.state')
local previewers = require('telescope.previewers')

-- base of the current stack: the most recent public ancestor of `.`.
-- if there are no draft commits in the stack this resolves to `.` itself,
-- so `sl status --rev STACK_BASE` degrades to plain `sl status`.
local STACK_BASE = 'max(public() & ::.)'

local function sl_root()
	local r = vim.fn.systemlist('sl root')[1]
	return (vim.v.shell_error == 0) and r or nil
end

local function sl_status_entries()
	local lines = vim.fn.systemlist({ 'sl', 'status', '-mardu', '--rev', STACK_BASE })
	if vim.v.shell_error ~= 0 then
		return {}
	end
	local root = sl_root()
	local out = {}
	for _, line in ipairs(lines) do
		local st, path = line:match('^(%S)%s+(.+)$')
		if path then
			table.insert(out, {
				status = st,
				path = path,
				abs = root and (root .. '/' .. path) or path,
			})
		end
	end
	return out
end

local sign_map = {
	M = { '~', 'DiffChange' },
	A = { '+', 'DiffAdd' },
	R = { '-', 'DiffDelete' },
	['!'] = { '-', 'DiffDelete' },
	['?'] = { '?', 'Comment' },
}

local function sl_changed(opts)
	opts = opts or {}
	local entries = sl_status_entries()
	if #entries == 0 then
		vim.notify('no sapling changes', vim.log.levels.INFO)
		return
	end

	pickers
		.new(opts, {
			prompt_title = 'sl stack',
			finder = finders.new_table({
				results = entries,
				entry_maker = function(e)
					local sign, hl = unpack(sign_map[e.status] or { ' ', 'Normal' })
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
			previewer = previewers.new_termopen_previewer({
				get_command = function(entry)
					if entry.value.status == '?' then
						return { 'bat', '--color=always', '--style=plain', entry.path }
					end
					return { 'sl', 'diff', '--color=always', '--rev', STACK_BASE, entry.path }
				end,
			}),
			attach_mappings = function(_, map)
				actions.select_default:replace(function(bufnr)
					local sel = action_state.get_selected_entry()
					actions.close(bufnr)
					vim.cmd('edit ' .. vim.fn.fnameescape(sel.path))
				end)
				return true
			end,
		})
		:find()
end

return { sl_changed = sl_changed }
