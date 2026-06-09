-- Tests for sap.core — the pure decision logic behind the picker.
-- No telescope / nvim runtime state required: these are plain functions.

local core = require('sap.core')

describe('core.parse', function()
	it('parses status lines into entries with absolute paths', function()
		local entries =
			core.parse({ 'M lua/sap/init.lua', '? scratch.txt' }, '/repo')
		assert.are.same({
			{
				status = 'M',
				path = 'lua/sap/init.lua',
				abs = '/repo/lua/sap/init.lua',
			},
			{ status = '?', path = 'scratch.txt', abs = '/repo/scratch.txt' },
		}, entries)
	end)

	it('falls back to the relative path when root is nil', function()
		local entries = core.parse({ 'A new.lua' }, nil)
		assert.are.equal('new.lua', entries[1].abs)
	end)

	it('ignores lines that do not match the status format', function()
		local entries = core.parse({ '', 'garbage-without-space' }, '/repo')
		assert.are.equal(0, #entries)
	end)

	it('strips a trailing carriage return from CRLF output', function()
		local entries = core.parse({ 'M lua/sap/init.lua\r' }, '/repo')
		assert.are.equal('lua/sap/init.lua', entries[1].path)
		assert.are.equal('/repo/lua/sap/init.lua', entries[1].abs)
	end)

	it('keeps spaces inside a path', function()
		local entries = core.parse({ 'A my new file.txt' }, nil)
		assert.are.equal('my new file.txt', entries[1].path)
	end)
end)

describe('core.classify', function()
	-- classify(stdout_lines, stderr_lines, exit_code, root)
	it('surfaces the stderr message when the command exits non-zero', function()
		local result = core.classify(
			{},
			{ 'abort: not inside a repository' },
			255,
			nil
		)
		assert.are.equal('error', result.kind)
		assert.is_truthy(result.msg:find('not inside a repository', 1, true))
	end)

	it(
		'falls back to stdout for the error message when stderr is empty',
		function()
			local result = core.classify({ 'something on stdout' }, {}, 1, nil)
			assert.are.equal('error', result.kind)
			assert.is_truthy(result.msg:find('something on stdout', 1, true))
		end
	)

	it('uses a generic message when a failing command is silent', function()
		local result = core.classify({}, {}, 1, nil)
		assert.are.equal('error', result.kind)
		assert.is_truthy(result.msg:find('1', 1, true))
	end)

	it(
		'reports empty (not error) when the command succeeds with no changes',
		function()
			local result = core.classify({}, {}, 0, '/repo')
			assert.are.equal('empty', result.kind)
			assert.is_truthy(result.msg and #result.msg > 0)
		end
	)

	it(
		'returns the parsed list (from stdout) when there are changes',
		function()
			local result = core.classify(
				{ 'M a.lua', '? b.lua' },
				{},
				0,
				'/repo'
			)
			assert.are.equal('list', result.kind)
			assert.are.equal(2, #result.entries)
		end
	)
end)

describe('core.sign', function()
	local SIGNS = {
		M = { '~', 'DiffChange' },
		A = { '+', 'DiffAdd' },
		R = { '-', 'DiffDelete' },
		['!'] = { '-', 'DiffDelete' },
		['?'] = { '?', 'Comment' },
	}

	it('maps each known status to its sign and highlight group', function()
		assert.are.same({ '~', 'DiffChange' }, { core.sign(SIGNS, 'M') })
		assert.are.same({ '+', 'DiffAdd' }, { core.sign(SIGNS, 'A') })
		assert.are.same({ '-', 'DiffDelete' }, { core.sign(SIGNS, 'R') })
		assert.are.same({ '-', 'DiffDelete' }, { core.sign(SIGNS, '!') })
		assert.are.same({ '?', 'Comment' }, { core.sign(SIGNS, '?') })
	end)

	it('falls back to a blank sign for an unknown status', function()
		assert.are.same({ ' ', 'Normal' }, { core.sign(SIGNS, 'X') })
	end)
end)

describe('core.status_command', function()
	it('includes --rev when a revset is given', function()
		assert.are.same(
			{ 'sl', 'status', '-mardu', '--rev', 'BASE' },
			core.status_command('sl', 'BASE')
		)
	end)

	it('omits --rev when none is given (plain status fallback)', function()
		assert.are.same(
			{ 'sl', 'status', '-mardu' },
			core.status_command('sl', nil)
		)
	end)

	it('uses the configured sl binary', function()
		assert.are.equal('/opt/sl', core.status_command('/opt/sl', nil)[1])
	end)
end)

describe('core.diff_command', function()
	it('includes --rev when a revset is given', function()
		assert.are.same(
			{ 'sl', 'diff', '--rev', 'BASE', '/repo/a.lua' },
			core.diff_command('sl', '/repo/a.lua', 'BASE')
		)
	end)

	it('omits --rev when none is given (plain working-copy diff)', function()
		assert.are.same(
			{ 'sl', 'diff', '/repo/a.lua' },
			core.diff_command('sl', '/repo/a.lua', nil)
		)
	end)

	it('uses the configured sl binary', function()
		assert.are.equal(
			'/opt/sl',
			core.diff_command('/opt/sl', '/repo/a.lua', 'BASE')[1]
		)
	end)

	it('does not request ANSI color (we apply highlights ourselves)', function()
		for _, arg in ipairs(core.diff_command('sl', '/repo/a.lua', 'BASE')) do
			assert.is_falsy(arg:find('color', 1, true))
		end
	end)
end)

describe('core.cap', function()
	it('returns the lines unchanged when at or under the cap', function()
		assert.are.same({ 'a', 'b', 'c' }, core.cap({ 'a', 'b', 'c' }, 5))
		assert.are.same({ 'a', 'b' }, core.cap({ 'a', 'b' }, 2))
	end)

	it('truncates to the cap and appends a marker counting the rest', function()
		local out = core.cap({ '1', '2', '3', '4', '5' }, 2)
		assert.are.equal(3, #out) -- 2 kept + 1 marker
		assert.are.equal('1', out[1])
		assert.are.equal('2', out[2])
		assert.is_truthy(out[3]:find('3 more', 1, true))
	end)
end)

describe('core.diff_highlights', function()
	local function by_line(lines)
		local m = {}
		for _, h in ipairs(core.diff_highlights(lines)) do
			m[h.line] = h.kind
		end
		return m
	end

	it(
		'classifies headers, hunks, additions and removals; leaves context plain',
		function()
			local m = by_line({
				'diff --git a/f.lua b/f.lua', -- 0
				'--- a/f.lua', -- 1
				'+++ b/f.lua', -- 2
				'@@ -1,2 +1,2 @@', -- 3
				' context', -- 4
				'-removed', -- 5
				'+added', -- 6
			})
			assert.are.equal('header', m[0])
			assert.are.equal('header', m[1])
			assert.are.equal('header', m[2])
			assert.are.equal('hunk', m[3])
			assert.is_nil(m[4]) -- context lines stay Normal
			assert.are.equal('del', m[5])
			assert.are.equal('add', m[6])
		end
	)

	it(
		'treats a removed comment as a deletion, not a --- file header',
		function()
			-- deleting a `-- foo` line produces `--- foo`; inside a hunk that is a
			-- removal, not a file header.
			local m = by_line({ '@@ -1 +0,0 @@', '--- foo' })
			assert.are.equal('del', m[1])
		end
	)

	it(
		'resets at the next file so its header is not classified as a removal',
		function()
			local m = by_line({
				'@@ -1 +1 @@', -- 0
				'-old', -- 1
				'diff --git a/g.lua b/g.lua', -- 2
				'--- a/g.lua', -- 3
				'+++ b/g.lua', -- 4
			})
			assert.are.equal('del', m[1])
			assert.are.equal('header', m[2])
			assert.are.equal('header', m[3])
			assert.are.equal('header', m[4])
		end
	)
end)
