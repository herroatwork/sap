-- Smoke test: the plugin and its telescope extension load cleanly and expose
-- the expected entry points. Catches syntax errors and broken requires in the
-- telescope-facing glue that core_spec.lua (deliberately telescope-free) cannot.

describe('sap', function()
	it('loads and exposes sl_changed', function()
		local sap = require('sap')
		assert.are.equal('function', type(sap.sl_changed))
	end)

	it('registers a telescope extension with sap and stack pickers', function()
		local ext = require('telescope._extensions.sap')
		assert.are.equal('function', type(ext.exports.sap))
		assert.are.equal('function', type(ext.exports.stack))
	end)

	it('exposes a health check (for :checkhealth sap and telescope)', function()
		assert.are.equal('function', type(require('sap.health').check))
		assert.are.equal(
			'function',
			type(require('telescope._extensions.sap').health)
		)
	end)

	it('exposes setup() that feeds sap.config', function()
		local sap = require('sap')
		assert.are.equal('function', type(sap.setup))
		sap.setup({ revset = 'draft()' })
		assert.are.equal('draft()', require('sap.config').options.revset)
		sap.setup({}) -- reset so we don't leak into other specs
	end)
end)
