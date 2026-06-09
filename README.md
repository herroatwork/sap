# sap

A [Telescope](https://github.com/nvim-telescope/telescope.nvim) picker for the
files in your current [Sapling](https://sapling-scm.com/) stack.
Lists every file touched between the base of your stack and your working copy —
committed-in-stack *and* uncommitted — so you can jump back to anything you've
been working on in this branch.

## Requirements

- [NVIM `v0.11.4`+](https://github.com/neovim/neovim/releases)
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- [`sl`](https://sapling-scm.com/) on your `PATH`

## Installation

`sap` is a [telescope extension](https://github.com/nvim-telescope/telescope.nvim#extensions).
With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'kevherro/sap',
  dependencies = { 'nvim-telescope/telescope.nvim' },
  config = function()
    require('telescope').load_extension('sap')
  end,
  keys = {
    { '<leader>fc', '<cmd>Telescope sap<cr>', desc = 'sl stack' },
  },
}
```

The `keys` entry triggers lazy.nvim to load the plugin, `config` runs and
registers the extension with telescope, and then the `<cmd>Telescope sap<cr>`
invocation fires — so cold-start works without any eager loading.

## Usage

Run `:Telescope sap` (or `:Telescope sap stack`) to open the picker.
If you prefer to bypass the extension layer you can also call
`require('sap').sl_changed()` directly — both paths invoke the same function.

Under the hood the picker runs

```
sl status -mardu --rev 'max(public() & ::.)'
```

which lists every file that differs between the base of your stack
(the most recent public ancestor of `.`) and your working copy —
so files you committed earlier in the stack show up alongside uncommitted edits.
If your stack is empty the revset resolves to `.` and you get plain `sl status` behavior.
If there's no public ancestor at all (e.g. a brand-new repo before anything is pushed),
the revset is empty, so `sap` falls back to a plain `sl status` / `sl diff` automatically.
If nothing has changed you get a `no changes in this stack (working copy clean)` notice
(rather than an empty picker); if `sl` itself fails — e.g. you're not inside a repository —
its error is surfaced instead.

Each entry is shown with a status sign and the directory dimmed:

```
~ lua/sap/init.lua
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

`<CR>` opens the selected file. Tracked files are previewed as `sl diff --rev 'max(public() & ::.)'`
(so you see the full cumulative diff against the stack base, not just the working-copy delta),
with added/removed lines highlighted via your `DiffAdd`/`DiffDelete` colors; untracked files are
previewed as their own contents, syntax-highlighted by your editor (treesitter/syntax) — no
external pager required.

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

## Development

Tests use [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)'s busted
harness. From the repo root:

```sh
nvim --headless -u tests/minimal_init.lua \
  -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"
```

`tests/minimal_init.lua` expects `plenary.nvim` (and `telescope.nvim`, for the
load smoke test) under `stdpath('data')/lazy` — the default for lazy.nvim users.
Formatting is enforced with [stylua](https://github.com/JohnnyMorganz/StyLua)
(`stylua --check lua/ tests/`).

## License

[MIT](./LICENSE)
