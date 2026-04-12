# sl_picker

A [Telescope](https://github.com/nvim-telescope/telescope.nvim) picker for the
files in your current [Sapling](https://sapling-scm.com/) stack.
Lists every file touched between the base of your stack and your working copy —
committed-in-stack *and* uncommitted — so you can jump back to anything you've
been working on in this branch.

## Requirements

- [NVIM `v0.11.4`+](https://github.com/neovim/neovim/releases)
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- [`sl`](https://sapling-scm.com/) on your `PATH`
- [`bat`](https://github.com/sharkdp/bat) (used to preview untracked files)

## Installation

`sl_picker` is a [telescope extension](https://github.com/nvim-telescope/telescope.nvim#extensions).
With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'kevherro/sl_picker',
  dependencies = { 'nvim-telescope/telescope.nvim' },
  config = function()
    require('telescope').load_extension('sl_picker')
  end,
  keys = {
    { '<leader>fc', '<cmd>Telescope sl_picker<cr>', desc = 'sl stack' },
  },
}
```

The `keys` entry triggers lazy.nvim to load the plugin, `config` runs and
registers the extension with telescope, and then the `<cmd>Telescope sl_picker<cr>`
invocation fires — so cold-start works without any eager loading.

## Usage

Run `:Telescope sl_picker` (or `:Telescope sl_picker stack`) to open the picker.
If you prefer to bypass the extension layer you can also call
`require('sl_picker').sl_changed()` directly — both paths invoke the same function.

Under the hood the picker runs

```
sl status -mardu --rev 'max(public() & ::.)'
```

which lists every file that differs between the base of your stack
(the most recent public ancestor of `.`) and your working copy —
so files you committed earlier in the stack show up alongside uncommitted edits.
If your stack is empty the revset resolves to `.` and you get plain `sl status` behavior.

Each entry is shown with a status sign and the directory dimmed:

```
~ lua/sl_picker/init.lua
+ lua/new_file.lua
- old_stuff.lua
? scratch.txt
```

| Sign | Meaning     |
| ---- | ----------- |
| `~`  | modified    |
| `+`  | added       |
| `-`  | removed / missing |
| `?`  | untracked   |

`<CR>` opens the selected file. Tracked files are previewed with `sl diff --rev 'max(public() & ::.)'`
(so you see the full cumulative diff against the stack base,
not just the working-copy delta); untracked files are previewed with `bat`.

### Optional: diff highlight palette

The picker uses the standard `DiffAdd` / `DiffChange` / `DiffDelete` / `Comment` highlight groups.
If you want the palette the author uses (tuned for color vision deficiency),
drop this in your config:

```lua
vim.api.nvim_set_hl(0, 'DiffAdd',    { fg = '#7ee787', bold = true })
vim.api.nvim_set_hl(0, 'DiffDelete', { fg = '#8b2e2e' })
vim.api.nvim_set_hl(0, 'DiffChange', { fg = '#e3b341', italic = true })
vim.api.nvim_set_hl(0, 'Comment',    { fg = '#6e7681' })
```

## License

[MIT](./LICENSE)
