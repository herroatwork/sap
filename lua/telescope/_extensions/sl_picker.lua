-- telescope extension entry point.
-- discovered by `require('telescope').load_extension('sl_picker')` via the
-- conventional path lua/telescope/_extensions/<name>.lua.

local has_telescope, telescope = pcall(require, 'telescope')
if not has_telescope then
	error('sl_picker requires nvim-telescope/telescope.nvim')
end

local sl_picker = require('sl_picker')

return telescope.register_extension({
	setup = function(_ext_config, _config)
		-- no options yet. ext_config would be the user's
		-- `extensions = { sl_picker = { ... } }` block from telescope.setup.
	end,
	exports = {
		-- primary picker: `:Telescope sl_picker` (bare, matches extension name)
		sl_picker = sl_picker.sl_changed,
		-- explicit alias: `:Telescope sl_picker stack`
		stack = sl_picker.sl_changed,
	},
})
