# nvim

A lean Neovim configuration based on kickstart.nvim. Part of [dotfiles](../README.md).

**Philosophy**: Text editing focused, native Neovim first, minimal external dependencies, tmux-integrated workflow. Prefer built-in Neovim APIs and small locally-owned tools over broad plugin layers when the native surface is enough.

## Installation

### Install Neovim

Kickstart.nvim targets _only_ the latest
['stable'](https://github.com/neovim/neovim/releases/tag/stable) and latest
['nightly'](https://github.com/neovim/neovim/releases/tag/nightly) of Neovim.
If you are experiencing issues, please make sure you have the latest versions.
This configuration follows the current kickstart.nvim mainline baseline and
requires Neovim 0.12 or newer.

> For detailed installation methods (Homebrew, Bob, Flatpak, etc.), see the
> [upstream kickstart.nvim documentation](https://github.com/nvim-lua/kickstart.nvim#install-neovim).

### Dependencies

Required:

- `git`, `make`, `unzip`, C Compiler (`gcc`)
- [ripgrep](https://github.com/BurntSushi/ripgrep#installation)
- [tree-sitter-cli](https://github.com/tree-sitter/tree-sitter/blob/master/cli/README.md) (`brew install tree-sitter-cli`)
- Clipboard tool (`pbcopy` on macOS, `xclip`/`xsel` on Linux)

Optional:

- [fd-find](https://github.com/sharkdp/fd#installation) (Telescope uses it if available)
- [uv](https://docs.astral.sh/uv/) (Python debugging launches debugpy through uv)
- Language-specific tools (`npm`, `go`, etc. as needed)

### Post Installation

Start Neovim and plugins will auto-install:

```sh
nvim
```

## Key Bindings

### Search & Navigation

- `<leader>sf` - Find files
- `<leader>sg` - Live grep
- `<leader>sw` - Search current word
- `<leader><leader>` - Find buffers
- `<leader>/` - Fuzzy search in current buffer

### Git

- `<leader>gg` - Open lazygit sized to the launching window
- `<leader>gd` - Open Hunk stacked working-tree review sized to the launching window
- `<leader>ga` - Stage/add current hunk
- `<leader>gr` - Reset current hunk
- `<leader>gu` - Undo staged hunk
- `<leader>gp` - Preview current hunk
- `<leader>tb` - Toggle git blame line
- `<leader>td` - Toggle inline git diff
- `]c` / `[c` - Navigate git hunks

Lazygit and Hunk open files through the shell-owned `EDITOR=nvim` contract. flatten.nvim routes nested Neovim calls back into the host editor and hides the originating Git surface.

Neovim-launched terminal tools use one shared flow in every environment: one persistent terminal job per tool, restarted when its effective working directory changes, shown in a Neovim float that follows the size of its launching window, leaves host tmux prefix and pane navigation available, and uses flatten.nvim for editor handoff. Add future flows through a declarative `terminal_tool.create { id, command, key, desc, env?, handoff? }` call; the module owns mappings, lifecycle state, error recovery, and source-agnostic handoff routing while leaving TUI input untouched.

### File Explorer

- `<leader>e` - Toggle neo-tree (right-side)

### Markdown

- `<leader>tm` - Toggle rendered Markdown for the current buffer

### LSP

- `grd` - Go to definition
- `grr` - References
- `grn` - Rename
- `K` - Hover documentation
- `<leader>f` - Format buffer

### Diagnostics

- `<leader>q` - Open diagnostic quickfix list

### Utilities

- `<leader>u` - Toggle undo tree
- `<leader>pa` / `<leader>pr` - Copy absolute/relative file path

## Configuration

Leader key is `<Space>`. Configuration is documented in `init.lua` and `AGENTS.md`.

Use `:lua vim.pack.update(nil, { offline = true })` to inspect plugin state,
`:lua vim.pack.update()` to update plugins, `:Mason` for LSP servers and tools,
and `:checkhealth` to diagnose issues.

Shared LSP, Mason, Treesitter, formatter, format-on-save, and linter support is
declared once in `lua/custom/languages.lua`; plugin configurations consume its
native-shaped declarations directly.

## Reset

```sh
# Full reset (all state, cache, and data)
alias nvim-reset='rm -rf ~/.local/share/nvim ~/.local/state/nvim ~/.cache/nvim'
```
