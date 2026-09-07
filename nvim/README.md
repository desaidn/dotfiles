# nvim

A lean Neovim configuration based on kickstart.nvim. Part of [dotfiles](../README.md).

**Philosophy**: Text editing focused, native Neovim first, minimal external dependencies, and workspace-manager neutral. Herdr is the normal daily workspace; tmux remains a compatible fallback. Prefer built-in Neovim APIs and small locally-owned tools over broad plugin layers when the native surface is enough.

## Features

- LSP through native Neovim configuration, nvim-lspconfig defaults, and Mason tooling.
- Completion and native snippets through Blink.
- File and live-grep search through fff.nvim; other pickers through Telescope and optional fzf-native.
- Git signs, blame, and local hunks through gitsigns; full review through Hunk; Git transactions through LazyGit.
- Treesitter highlighting, parsing, and context through nvim-treesitter and nvim-treesitter-context.
- Formatting through Conform; ESLint through nvim-lint; Python diagnostics/actions through Ruff LSP.
- Debugging through nvim-dap: js-debug for JavaScript/TypeScript, nvim-jdtls with Java debug/test bundles, debugpy for Python, and rustaceanvim with CodeLLDB for Rust.
- Editing helpers through mini.nvim (statusline, surround, text objects), which-key, autopairs, Undotree, and todo-comments.

## Installation

Follow the [repository quick start](../README.md#quick-start) to install the
configuration, applications, and runtimes. The [dependency inventory](../README.md#dependency-ownership)
owns package requirements and versions.

Use the latest stable Neovim release. Installation, startup, and
`:checkhealth kickstart` share a minimum of 0.12.5 and accept newer releases.
Prerelease builds above that stable minimum can start, with an advisory in
the health check; 0.12.5-dev remains below the minimum. Acceptance does not
mean a release has been tested. These checks do not query for updates online.

Neovim itself supports macOS, Linux, and Windows. This repository's installer
targets macOS and Linux; native Windows installation is unsupported. See the
[repository platform scope](../README.md) for validation coverage.

Start `nvim` after installation; plugins and declared language tools install
automatically.

## Language project requirements

Mise owns machine runtimes and Mason owns editor tools. JavaScript/TypeScript
semantics come from each project's root-local TypeScript installation. The
configuration selects a package-manager or Git root and excludes a nearer Deno
project. A parseable TypeScript 7+ installation uses that root's exact
`node_modules/.bin/tsc` LSP; earlier versions use Mason's
`typescript-language-server` transport pointed at the same project's
`node_modules/typescript/lib/tsserver.js`. The compatibility client accepts only
the expected `$/typescriptVersion` report from `user-setting` and terminates
bundled, workspace-fallback, or mismatched TypeScript. Missing, unparseable,
unowned, and Deno workspaces receive neither client.

Python DAP uses Mason's debugpy adapter
while debug targets use their project environments; JavaScript/TypeScript DAP
uses Mason's js-debug adapter while projects own non-trivial launch
configuration. Restart Neovim after changing a project's installed TypeScript
version so its semantic route is recalculated.

This personal editor configuration assumes repositories opened for development
are trusted: JavaScript/TypeScript startup executes the project's root-local
compiler to select a semantic route, and project lint configuration can execute
code. Review untrusted checkouts before opening them in Neovim. Debug launches
remain explicit user actions and bind the adapter to loopback.

## Clipboard

Use `pbcopy`/`pbpaste` on macOS or a working Wayland/X11 clipboard provider on
Linux. A remote session with no display and no tmux falls back to OSC 52 so the
host terminal receives copies. OSC 52 clipboard reads are disabled because
they block waiting on the terminal, so pastes replay Neovim's own yanks.
`:checkhealth vim.provider` reports the active provider.

## Key Bindings

Leader is `<Space>`. Search uses `<leader>s*`, toggles use `<leader>t*`, and
shared LSP actions use Neovim's `gr*` conventions. The interface uses text
labels without requiring a Nerd Font.

### Search & Navigation

- `<leader>sf` - Find files
- `<leader>sg` - Live grep
- `<leader>sw` - Search current word
- `<leader>sh` / `<leader>sk` / `<leader>sd` - Search help, keymaps, or diagnostics
- `<leader><leader>` - Find buffers
- `<leader>/` - Fuzzy search in current buffer

### Git

- `<leader>gg` - Toggle lazygit
- `<leader>gd` - Toggle Hunk stacked working-tree review
- `<leader>gD` - Toggle the same Hunk review for staged changes
- `<leader>ga` - Stage/add current hunk
- `<leader>gr` - Reset current hunk
- `<leader>gu` - Undo staged hunk
- `<leader>gp` - Preview current hunk
- `<leader>tb` - Toggle git blame line
- `<leader>td` - Toggle inline git diff
- `]c` / `[c` - Navigate git hunks

Lazygit and Hunk open files through the shell-owned `EDITOR=nvim` contract. flatten.nvim routes nested Neovim calls back into the host editor and hides the originating Git surface. Workflow reviews run Hunk in devflow's Invoking Checkout, so pressing `e` opens in the review tab's Neovim with normal project-root discovery and full language tooling using that checkout's project and build context.

Each terminal tool uses a persistent Tool Tab. LazyGit restarts in its existing
tab when the working directory changes; Hunk keeps an instance per working
directory so reviews in different repositories remain live. Working-tree and
staged review share the same Hunk tab and process: choosing the other input
retargets that review, and invoking its active toggle returns to the Host
Window. Jobs stop when Neovim exits.

### File Explorer

- `<leader>e` - Toggle neo-tree on the right and reveal the current file
- `?` - Show explorer help
- `a` / `d` / `r` - Add, delete, or rename the selected file
- `<Tab>` - Cycle filesystem, buffers, and git-status sources
- `<leader>pa` / `<leader>pr` - Copy the selected file or directory's absolute/tree-root-relative path

The explorer uses text symbols and the main colorscheme's Git status colors;
no Nerd Font is required.

### LSP

- `grd` - Go to definition
- `grr` - References
- `grn` - Rename
- `K` - Hover documentation
- `<leader>f` - Format buffer

Formatting also runs on save unless disabled by the language configuration.

### Diagnostics

- `<leader>q` - Open the diagnostic location list

### Debugging

- `<leader>b` / `<leader>B` - Toggle a breakpoint / set a conditional breakpoint
- `F5` - Start or continue
- `F1` / `F2` / `F3` - Step into, over, or out
- `F7` - Toggle the debugger UI and inspect the last session result

Debugging loads on first use and selects `launch.json` from the current
buffer's language-specific project root. Rust also initializes DAP when
rust-analyzer attaches so rustaceanvim can create CodeLLDB configurations.
Python test actions are available through `:DapPythonTestClass` and
`:DapPythonTestMethod`. Rust exposes additional actions through
`:RustLsp runnables`, `:RustLsp testables`, `:RustLsp debuggables`,
`:RustLsp expandMacro`, and `:RustLsp hover actions`.

### Terminal navigation

- `<Esc><Esc>` - Exit terminal mode before using normal-mode tool keys
- `<C-h/j/k/l>` - Move between Neovim windows

Herdr manages the daily workspace and tmux remains a separate fallback. When
using tmux, its prefix, session picker, and pane navigation remain available
inside Neovim-owned Tool Tabs.

### Utilities

- `<leader>u` - Toggle undo tree
- `<leader>th` - Toggle LSP inlay hints when supported
- `<leader>ts` - Toggle spell check
- `<leader>pa` / `<leader>pr` - Copy the current buffer or selected Neo-tree file/directory's absolute/relative path

## Snippets

Blink uses Neovim's native snippet engine for language-server completions and
personal VS Code snippets in `~/.config/nvim/snippets/` (for example,
`lua.json`). `<Tab>` and `<S-Tab>` move between placeholders. The bundled
friendly-snippets catalog and LuaSnip-specific features are no longer enabled.

After updating an existing installation, remove the two old plugin copies once
with `:lua vim.pack.del({ 'LuaSnip', 'friendly-snippets' })` in a fresh Neovim
session. Otherwise native package synchronization can restore their lockfile
entries from disk. This removes plugin copies, not personal snippet files.

## Configuration

The configuration keeps an instructional [init.lua](init.lua). Contributor
constraints and module ownership are documented in [AGENTS.md](AGENTS.md).

Use `:lua vim.pack.update(nil, { offline = true })` to inspect plugin state,
`:lua vim.pack.update()` to update plugins, `:Mason` for LSP servers and tools,
and `:checkhealth` to diagnose issues.

To customize a language, edit its family under
[`lua/custom/languages/adapters/`](lua/custom/languages/adapters/). Families
with LSP or DAP support have their own file; `supporting.lua` groups the
remaining parsers and Markdown formatting. Adding a file requires enabling it
in [`config.lua`](lua/custom/languages/config.lua). See the
[language architecture guide](AGENTS.md#lsp-and-language-support) for the
collection and activation contract. Plugin modules live under
`lua/kickstart/plugins/` and `lua/custom/plugins/`; custom modules must be
explicitly required by `lua/custom/plugins/init.lua`.

## Reset

```sh
# Full reset (all state, cache, and data)
alias nvim-reset='rm -rf ~/.local/share/nvim ~/.local/state/nvim ~/.cache/nvim'
```
