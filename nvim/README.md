# nvim

A lean Neovim configuration based on kickstart.nvim. Part of [dotfiles](../README.md).

**Philosophy**: Text editing focused, native Neovim first, minimal external dependencies, and workspace-manager neutral. Herdr is the normal daily workspace; tmux remains a compatible fallback. Prefer built-in Neovim APIs and small locally-owned tools over broad plugin layers when the native surface is enough.

## Installation

### Install Neovim

This configuration follows the current kickstart.nvim mainline baseline and
requires exactly stable Neovim 0.12.4. Startup rejects older, newer, and
prerelease builds so plugin behavior stays tied to the tested baseline.

> For detailed installation methods (Homebrew, Bob, Flatpak, etc.), see the
> [upstream kickstart.nvim documentation](https://github.com/nvim-lua/kickstart.nvim#install-neovim).

### Dependencies

Host requirements:

- `git`, `curl`, `tar`, `gzip`, `unzip`, and `diff` for plugins, Mason
  packages, and Undotree
- A C compiler for Treesitter parsers
- [ripgrep](https://github.com/BurntSushi/ripgrep#installation) for Telescope grep
- [tree-sitter-cli](https://github.com/tree-sitter/tree-sitter/blob/master/cli/README.md)
  0.26.1 or newer
- `lazygit` and `hunk` for their production Tool Tab mappings
- `pbcopy`/`pbpaste` on macOS or a working Wayland/X11 clipboard provider on
  Linux. A remote session with no display and no tmux falls back to OSC 52 so
  the host terminal receives copies; OSC 52 clipboard *read* is not used because
  it blocks waiting on the terminal, so pastes replay Neovim's own yanks.
  `:checkhealth vim.provider` reports the active provider

Mise owns the language runtimes used by the enabled Language Tooling
configuration: Node.js/npm, Python, Rust with Cargo, Clippy, and rustfmt, and
Amazon Corretto JDK 21 (`corretto-21.0.12.8.1`). Mason owns the corresponding
LSPs, formatters, and linters. Python DAP invokes the standalone `uv` CLI.
Haskell support currently requires `ghcup` because Mason's HLS installer calls
it directly.

`make` is optional: when available, it enables telescope-fzf-native and
LuaSnip's jsregexp build. `fd` is not a base dependency because fff.nvim owns
normal file finding. Expect is needed only for the real-PTY Hunk regression
test.

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
- `<leader>gD` - Open the same Hunk review for staged changes
- `<leader>ga` - Stage/add current hunk
- `<leader>gr` - Reset current hunk
- `<leader>gu` - Undo staged hunk
- `<leader>gp` - Preview current hunk
- `<leader>tb` - Toggle git blame line
- `<leader>td` - Toggle inline git diff
- `]c` / `[c` - Navigate git hunks

Lazygit and Hunk open files through the shell-owned `EDITOR=nvim` contract. flatten.nvim routes nested Neovim calls back into the host editor and hides the originating Git surface.

Neovim-launched terminal tools use one shared flow in every environment: one persistent terminal job and Tool Tab per selected instance, all stopped before Neovim exits, with host tmux prefix and pane navigation left available when running in the tmux fallback and flatten.nvim handling editor handoff. LazyGit keeps the default singleton and restarts when its effective working directory changes; Hunk retains one instance per canonical Host Window working directory, with working-tree and staged variants sharing that instance. Add future flows through a declarative `terminal_tool.create { id, command?, key?, desc?, variants?, instances?, env?, handoff? }` call; the module owns mappings, instance lifecycle, error recovery, and source-agnostic handoff routing while leaving TUI input untouched.

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
- `<leader>pa` / `<leader>pr` - Copy the current buffer or selected Neo-tree file/directory's absolute/relative path

## Configuration

Leader key is `<Space>`. Configuration is documented in `init.lua` and `AGENTS.md`.

Use `:lua vim.pack.update(nil, { offline = true })` to inspect plugin state,
`:lua vim.pack.update()` to update plugins, `:Mason` for LSP servers and tools,
and `:checkhealth` to diagnose issues.

Shared LSP, Mason, Treesitter, formatter, format-on-save, and linter support is
declared once in `lua/custom/languages/config.lua`; language tooling consumes its
native-shaped declarations directly.

## Reset

```sh
# Full reset (all state, cache, and data)
alias nvim-reset='rm -rf ~/.local/share/nvim ~/.local/state/nvim ~/.cache/nvim'
```
