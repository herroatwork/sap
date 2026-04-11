-- ~/.config/nvim/init.lua

vim.keymap.set('n', '<leader>fc', function()
	require('sl_picker').sl_changed()
end, { desc = 'sl changed files' })

-- truecolor diff palette tuned for cvd
vim.api.nvim_set_hl(0, 'DiffAdd', { fg = '#7ee787', bold = true })
vim.api.nvim_set_hl(0, 'DiffDelete', { fg = '#8b2e2e' })
vim.api.nvim_set_hl(0, 'DiffChange', { fg = '#e3b341', italic = true })
vim.api.nvim_set_hl(0, 'Comment', { fg = '#6e7681' })
