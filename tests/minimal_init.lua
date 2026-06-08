-- Minimal init for running sap's tests headlessly with plenary.
--
-- Usage (from the repo root):
--   nvim --headless -u tests/minimal_init.lua \
--     -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"
--
-- Assumes plenary.nvim (and telescope.nvim, for the load smoke test) are
-- installed under stdpath('data')/lazy — the default for lazy.nvim users.

local data = vim.fn.stdpath('data')

-- repo under test
vim.opt.runtimepath:prepend(vim.fn.getcwd())

-- dependencies
vim.opt.runtimepath:append(data .. '/lazy/plenary.nvim')
vim.opt.runtimepath:append(data .. '/lazy/telescope.nvim')

vim.cmd('runtime plugin/plenary.vim')
