-- User-facing configuration for sap: defaults, setup() (deep-merge over
-- defaults) and resolve() (per-call opts win over the configured options).

local M = {}

M.defaults = {
	-- the `sl` binary (override for nix / custom wrappers / non-PATH installs)
	sl_bin = 'sl',
	-- the revset whose `max(...)` is the stack base; what counts as "the stack"
	revset = 'max(public() & ::.)',
	-- show the diff/file preview pane
	preview = true,
	-- status code -> { sign, highlight group }
	signs = {
		M = { '~', 'DiffChange' },
		A = { '+', 'DiffAdd' },
		R = { '-', 'DiffDelete' },
		['!'] = { '-', 'DiffDelete' },
		['?'] = { '?', 'Comment' },
	},
	-- explicit foreground colors for the diff preview; nil = derive from the
	-- colorscheme's diff groups. each may be a '#rrggbb' string or a number.
	highlights = { add = nil, delete = nil, change = nil },
	-- extra in-picker mappings, e.g. { i = { ['<C-y>'] = fn }, n = { ... } };
	-- each value is a function(prompt_bufnr) or a telescope action.
	mappings = {},
}

M.options = vim.deepcopy(M.defaults)

-- merge user options over a fresh copy of the defaults.
function M.setup(opts)
	M.options =
		vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts or {})
	return M.options
end

-- the configured options, with any per-call opts layered on top (per-call wins).
function M.resolve(opts)
	if not opts or vim.tbl_isempty(opts) then
		return M.options
	end
	return vim.tbl_deep_extend('force', M.options, opts)
end

return M
