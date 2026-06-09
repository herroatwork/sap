-- telescope extension entry point.
-- discovered by `require('telescope').load_extension('sap')` via the
-- conventional path lua/telescope/_extensions/<name>.lua.

local has_telescope, telescope = pcall(require, 'telescope')
if not has_telescope then
	error('sap requires nvim-telescope/telescope.nvim')
end

local sap = require('sap')

return telescope.register_extension({
	-- the user's `extensions = { sap = { ... } }` block from telescope.setup;
	-- equivalent to calling require('sap').setup(...) directly.
	setup = function(ext_config, _config)
		sap.setup(ext_config)
	end,
	-- `:checkhealth telescope` includes this; `:checkhealth sap` runs it too
	-- via lua/sap/health.lua.
	health = function()
		require('sap.health').check()
	end,
	exports = {
		-- primary picker: `:Telescope sap` (bare, matches extension name)
		sap = sap.sl_changed,
		-- explicit alias: `:Telescope sap stack`
		stack = sap.sl_changed,
	},
})
