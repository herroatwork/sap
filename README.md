# sl_picker

A [Telescope](https://github.com/nvim-telescope/telescope.nvim) picker for [Sapling](https://sapling-scm.com/) (`sl`) working-copy changes. Pick a changed file, preview its diff, open it.

## Requirements

- Neovim ≥ 0.9
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- [`sl`](https://sapling-scm.com/) on your `PATH`
- [`bat`](https://github.com/sharkdp/bat) (used to preview untracked files)

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'kevherro/sl_picker',
  dependencies = { 'nvim-telescope/telescope.nvim' },
  keys = {
    {
      '<leader>fc',
      function() require('sl_picker').sl_changed() end,
      desc = 'sl changed files',
    },
  },
}
```

## Usage

Call `require('sl_picker').sl_changed()` to open the picker. It lists every file reported by `sl status -mardu` with a status sign:

| Sign | Meaning     |
| ---- | ----------- |
| `~`  | modified    |
| `+`  | added       |
| `-`  | removed / missing |
| `?`  | untracked   |

`<CR>` opens the selected file. Tracked files are previewed with `sl diff`; untracked files are previewed with `bat`.

### Optional: diff highlight palette

The picker uses the standard `DiffAdd` / `DiffChange` / `DiffDelete` / `Comment` highlight groups. If you want the palette the author uses (tuned for color vision deficiency), drop this in your config:

```lua
vim.api.nvim_set_hl(0, 'DiffAdd',    { fg = '#7ee787', bold = true })
vim.api.nvim_set_hl(0, 'DiffDelete', { fg = '#8b2e2e' })
vim.api.nvim_set_hl(0, 'DiffChange', { fg = '#e3b341', italic = true })
vim.api.nvim_set_hl(0, 'Comment',    { fg = '#6e7681' })
```

## License

MIT
