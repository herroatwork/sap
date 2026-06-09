-- Tests for sap.config — defaults, setup() merge, and per-call resolve().

local config = require('sap.config')

describe('config.defaults', function()
	it('has the documented keys', function()
		local d = config.defaults
		assert.are.equal('sl', d.sl_bin)
		assert.are.equal('max(public() & ::.)', d.revset)
		assert.are.equal(true, d.preview)
		assert.are.same({ '~', 'DiffChange' }, d.signs.M)
	end)
end)

describe('config.setup', function()
	before_each(function()
		config.setup({}) -- reset to a clean copy of the defaults
	end)

	it('merges user options over the defaults', function()
		config.setup({ revset = 'draft()', sl_bin = '/opt/sl' })
		assert.are.equal('draft()', config.options.revset)
		assert.are.equal('/opt/sl', config.options.sl_bin)
		assert.are.equal(true, config.options.preview) -- untouched default
	end)

	it('deep-merges signs without dropping the other defaults', function()
		config.setup({ signs = { ['?'] = { '!', 'WarningMsg' } } })
		assert.are.same({ '!', 'WarningMsg' }, config.options.signs['?'])
		assert.are.same({ '~', 'DiffChange' }, config.options.signs.M) -- kept
	end)

	it('does not mutate the defaults table', function()
		config.setup({ revset = 'x' })
		assert.are.equal('max(public() & ::.)', config.defaults.revset)
	end)
end)

describe('config.resolve', function()
	before_each(function()
		config.setup({ revset = 'CONFIGURED' })
	end)

	it('returns the configured options when given no per-call opts', function()
		assert.are.equal('CONFIGURED', config.resolve().revset)
		assert.are.equal('CONFIGURED', config.resolve({}).revset)
	end)

	it('lets per-call opts win over the configured options', function()
		assert.are.equal(
			'PERCALL',
			config.resolve({ revset = 'PERCALL' }).revset
		)
	end)
end)
