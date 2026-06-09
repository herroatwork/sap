-- Pure decision logic for the sap picker, kept free of telescope and (mostly)
-- of nvim runtime state so it can be unit-tested in isolation.

local M = {}

-- base of the current stack: the most recent public ancestor of `.`.
-- if there are draft commits but no public ancestor at all (e.g. a brand-new
-- repo before anything is pushed) this revset is empty and sl aborts; the caller
-- detects that and retries the commands with no --rev (plain `sl status`/`sl
-- diff`), which is why status_command/diff_command take an optional revset.
M.STACK_BASE = 'max(public() & ::.)'

M.sign_map = {
	M = { '~', 'DiffChange' },
	A = { '+', 'DiffAdd' },
	R = { '-', 'DiffDelete' },
	['!'] = { '-', 'DiffDelete' },
	['?'] = { '?', 'Comment' },
}

-- turn `sl status` output lines into entries. `root` (from `sl root`) makes
-- paths absolute so telescope can open them from any cwd; nil leaves them
-- relative.
function M.parse(lines, root)
	local out = {}
	for _, line in ipairs(lines) do
		line = (line:gsub('\r$', '')) -- tolerate CRLF output
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

-- decide what the picker should do given the raw result of `sl status`.
-- distinguishes a real failure (non-zero exit) from a genuinely clean tree
-- (zero exit, no changes) so the two never share a message. on failure the
-- error message prefers sl's stderr (e.g. "abort: not inside a repository"),
-- which is what actually tells the user how to fix it. returns one of:
--   { kind = 'error', msg = <stderr, else stdout, else generic fallback> }
--   { kind = 'empty', msg = <reassuring "clean" message> }
--   { kind = 'list',  entries = { ... } }
function M.classify(stdout, stderr, code, root)
	if code ~= 0 then
		local msg = table.concat(stderr, '\n')
		if msg == '' then
			msg = table.concat(stdout, '\n')
		end
		if msg == '' then
			msg = 'sl status failed (exit code ' .. tostring(code) .. ')'
		end
		return { kind = 'error', msg = msg }
	end
	local entries = M.parse(stdout, root)
	if #entries == 0 then
		return { kind = 'empty', msg = 'no changes in this stack (working copy clean)' }
	end
	return { kind = 'list', entries = entries }
end

-- sign + highlight group for a status code.
function M.sign(status)
	local s = M.sign_map[status]
	if s then
		return s[1], s[2]
	end
	return ' ', 'Normal'
end

-- `sl status` listing changed files. `rev` (e.g. STACK_BASE) is optional so the
-- caller can fall back to a plain status when the stack-base revset is empty.
function M.status_command(rev)
	local cmd = { 'sl', 'status', '-mardu' }
	if rev then
		cmd[#cmd + 1] = '--rev'
		cmd[#cmd + 1] = rev
	end
	return cmd
end

-- `sl diff` for a tracked file: the cumulative diff against `rev` (the stack
-- base), or the working-copy diff when `rev` is nil. no --color, on purpose —
-- we render the diff into a plain buffer and apply our own highlights (see
-- diff_highlights), using the colorscheme's vivid DiffAdd/DiffDelete groups
-- rather than its (often washed-out) treesitter diff palette. (untracked files
-- have nothing to diff against and are previewed as their own contents instead.)
function M.diff_command(path, rev)
	local cmd = { 'sl', 'diff' }
	if rev then
		cmd[#cmd + 1] = '--rev'
		cmd[#cmd + 1] = rev
	end
	cmd[#cmd + 1] = path
	return cmd
end

-- classify each line of a unified diff, returning a list of
-- { line = <0-indexed row>, kind = 'header'|'hunk'|'add'|'del' }. context-aware
-- so that, e.g., a removed `-- comment` line (which reads as `--- comment`) is
-- classified as a deletion rather than mistaken for a `---` file header. only
-- emits an entry for lines that should be colored; context lines are left out
-- (rendered as Normal). the caller maps kinds to concrete highlight groups.
function M.diff_highlights(lines)
	local hls = {}
	local in_hunk = false
	for i, line in ipairs(lines) do
		local kind
		if line:sub(1, 10) == 'diff --git' then
			in_hunk = false -- new file; back to the header section
			kind = 'header'
		elseif line:sub(1, 2) == '@@' then
			in_hunk = true
			kind = 'hunk'
		elseif not in_hunk then
			kind = 'header' -- ---, +++, index, mode, new/deleted file, etc.
		else
			local c = line:sub(1, 1)
			if c == '+' then
				kind = 'add'
			elseif c == '-' then
				kind = 'del'
			end
		end
		if kind then
			hls[#hls + 1] = { line = i - 1, kind = kind }
		end
	end
	return hls
end

return M
