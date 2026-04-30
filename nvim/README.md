# nvim

A lean Neovim configuration based on kickstart.nvim. Part of [dotfiles](../README.md).

**Philosophy**: Text editing focused, minimal dependencies, tmux-integrated workflow.

## Installation

### Install Neovim

Kickstart.nvim targets _only_ the latest
['stable'](https://github.com/neovim/neovim/releases/tag/stable) and latest
['nightly'](https://github.com/neovim/neovim/releases/tag/nightly) of Neovim.
If you are experiencing issues, please make sure you have the latest versions.

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

- `<leader>gg` - Toggle fullscreen lazygit
- `<leader>tb` - Toggle git blame line
- `<leader>td` - Toggle inline git diff
- `<leader>h*` - Hunk operations (stage, reset, preview, undo)
- `]c` / `[c` - Navigate git hunks

### File Explorer

- `<leader>e` - Toggle neo-tree (right-side)

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

Leader key is `<Space>`. Configuration is documented in `init.lua` and `CLAUDE.md`.

Use `:Lazy` to manage plugins, `:Mason` for LSP servers, and `:checkhealth` to diagnose issues.

## Reset

```sh
# Reset plugins and Mason installations
alias nvim-reset='rm -rf ~/.local/share/nvim/lazy ~/.local/share/nvim/mason'

# Full reset (all state, cache, and data)
alias nvim-reset-all='rm -rf ~/.local/share/nvim ~/.local/state/nvim ~/.cache/nvim'
```
