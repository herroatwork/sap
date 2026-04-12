-- telescope extension entry point.
-- discovered by `require('telescope').load_extension('sap')` via the
-- conventional path lua/telescope/_extensions/<name>.lua.

local has_telescope, telescope = pcall(require, 'telescope')
if not has_telescope then
	error('sap requires nvim-telescope/telescope.nvim')
end

local sap = require('sap')

return telescope.register_extension({
	setup = function(_ext_config, _config)
		-- no options yet. ext_config would be the user's
		-- `extensions = { sap = { ... } }` block from telescope.setup.
	end,
	exports = {
		-- primary picker: `:Telescope sap` (bare, matches extension name)
		sap = sap.sl_changed,
		-- explicit alias: `:Telescope sap stack`
		stack = sap.sl_changed,
	},
})
