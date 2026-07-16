# AGENTS.md

Guidance for coding agents working on the nvim config. See [`../AGENTS.md`](../AGENTS.md) for monorepo-level conventions.

## Neovim Configuration Overview

This is a Neovim configuration based on kickstart.nvim, providing a well-documented starting point for Neovim customization. `init.lua` handles core settings, basic keymaps, native `vim.pack` build hooks, and core UI plugins; each modular plugin configuration lives under `lua/kickstart/plugins/` or `lua/custom/plugins/`.

## Core Architecture

### File Structure

- `init.lua` - Core settings, basic keymaps, autocommands, native `vim.pack` build hooks, core UI plugins, and top-level module imports
- `after/lsp/lua_ls.lua` - LSP server override for `lua_ls` (the only server that needs substantial custom logic)
- `colors/custom.lua` - Custom colorscheme (transparent backgrounds, peach accents)
- `lua/kickstart/parsers.lua` - nvim-treesitter parser install set consumed by `custom/lib/pack.lua` after package installs and updates; runtime parser attachment remains on demand
- `lua/kickstart/plugins/` - Auto-imported by `lua/kickstart/plugins/init.lua` in the established startup order; each plugin file calls `vim.pack.add()` for the plugin(s) it owns and then configures them:
  - `lsp.lua` - nvim-lspconfig, Mason, fidget, native `vim.lsp.config()` overrides, and direct Language Tooling Inventory consumption
  - `blink-cmp.lua` - blink.cmp completion with LuaSnip
  - `conform.lua` - conform.nvim formatter config and format-on-save
  - `telescope.lua` - Telescope pickers and LSP reference/definition keymaps
  - `treesitter.lua` - nvim-treesitter and treesitter-context
  - `gitsigns.lua` - Git signs, blame, and hunk navigation keymaps
  - `neo-tree.lua` - File explorer (right-side, text-based icons)
  - `debug.lua` - DAP debugger keymaps plus on-demand setup (Go via delve, Python via debugpy/uv); DAP plugins load on first debug action, not normal startup
  - `lint.lua` - nvim-lint with eslint_d and ruff
  - `autopairs.lua` - Auto-close brackets, quotes, etc.
- `lua/kickstart/health.lua` - Health check for `:checkhealth`
- `lua/custom/lib/pack.lua` - Shared `vim.pack` helper, GitHub URL helper, and `PackChanged` build hooks
- `lua/custom/lib/plugins_loader.lua` - Shared sorted directory plugin module loader used by `kickstart.plugins` and `custom.plugins`
- `lua/custom/lib/terminal_tool.lua` - Shared launcher for Neovim-owned terminal tools; use this for future flows that should run in a persistent Tool Tab while leaving host tmux navigation available
- `lua/custom/languages.lua` - Canonical read-only Language Tooling Inventory: plain tables for enabled LSP configurations, Mason packages, Conform formatters, and nvim-lint linters
- `lua/custom/plugins/` - Auto-imported by `lua/custom/plugins/init.lua`; every sibling `*.lua` file is required, following symlinks:
  - `init.lua` - Custom plugin loader
  - `fff.lua` - fff.nvim fuzzy file/grep finder (owns `<leader>sf` and `<leader>sg`)
  - `lazygit.lua` - Thin lazygit Git transaction launcher over `lua/custom/lib/terminal_tool.lua` (owns `<leader>gg`)
  - `hunk.lua` - Thin Hunk stacked working-tree review launcher over `lua/custom/lib/terminal_tool.lua` (owns `<leader>gd`)
  - `flatten.lua` - Editor handoff for nested `nvim` calls launched from Neovim-owned tools
  - `render-markdown.lua` - In-editor Markdown rendering without Nerd Font dependencies (owns `<leader>tm`)
- `tests/terminal_tool_spec.lua` - Headless regression harness for the terminal-tool declaration interface, Tool Tab persistence, Host Window return, handoff, failure/race recovery, environment handling, and host tmux input routing
- `tests/languages_spec.lua` - Exact production Language Tooling Inventory regression check
- `tests/pack_spec.lua` - Headless checks for native package build hooks, including nvim-treesitter parser/query installation and updates
- `tests/terminal_tool_hunk_render.exp` and `tests/terminal_tool_hunk_render_init.lua` - Real-PTY regression harness loading the production Hunk declaration and proving its complete first frame renders without graphics-protocol artifacts inside its Tool Tab
- `tests/lsp_hover_spec.lua` - Headless screen regression using an in-process LSP to prove native `K` hover documentation remains complete
- `nvim-pack-lock.json` - Native `vim.pack` plugin version lockfile

### Plugin Management

Uses native `vim.pack` as the plugin manager. Plugin modules should stay simple and idiomatic: call `vim.pack.add()` for the package(s) they own, configure them directly, and avoid recreating lazy.nvim's trigger DSL. Prefer native Neovim APIs before adding plugins, and keep each plugin responsible for a clear capability that is not already covered by core Neovim or a local helper. Core plugins include:

- **LSP**: nvim-lspconfig with Mason for auto-installation. Native Neovim 0.11+ configuration lives in `lua/kickstart/plugins/lsp.lua`, with substantial overrides in `after/lsp/lua_ls.lua`
- **Completion**: blink.cmp with LuaSnip for snippets
- **Fuzzy Finding**: fff.nvim for files and live grep (`<leader>sf`, `<leader>sg`); Telescope with fzf-native for help, keymaps, diagnostics, buffers, LSP symbols, and word-under-cursor grep
- **Git Integration**: gitsigns (in-editor signs, blame, local hunks); Hunk (working-tree review); lazygit (Git transaction UI)
- **Treesitter**: Syntax highlighting, code parsing, and context (nvim-treesitter-context)
- **Formatting**: conform.nvim for auto-formatting
- **Linting**: nvim-lint with eslint_d, ruff
- **Debugging**: nvim-dap with Go (delve) and Python (debugpy via uv)
- **UI**: which-key, mini.nvim (statusline, surround, text objects), undotree, todo-comments

### Key Bindings Structure

- Leader key: `<Space>`
- Search operations: `<leader>s*` (files, grep, help, keymaps, diagnostics, etc.)
- Toggle options: `<leader>t*` — `th` inlay hints, `tb` git blame line, `td` inline git diff, `tm` rendered Markdown, `ts` spell check
- Git operations: `<leader>gg` (lazygit), `<leader>gd` (Hunk review), `<leader>g*` (hunk-local gitsigns actions), `]c`/`[c` (hunk navigation)
- LSP operations: `gr*` prefix (Neovim 0.11 defaults for rename/code action, Telescope overrides for references/definitions)
- Format: `<leader>f` (format buffer)
- Explorer: `<leader>e` (neo-tree toggle)
- Undo tree: `<leader>u` (toggle undotree)
- Path copy: `<leader>p*` (copy absolute/relative file paths)
- Debug: `<leader>b` (breakpoint), `F1-F3` (stepping), `F5` (continue), `F7` (DAP UI). These keys lazy-load and configure DAP on first use.
- Diagnostic quickfix: `<leader>q`

## Development Workflows

### Plugin Management

- `:lua vim.pack.update(nil, { offline = true })` - Inspect plugin state and pending updates
- `:lua vim.pack.update()` - Update all plugins
- `:Mason` - Manage LSP servers, formatters, and linters
- `:checkhealth` - Diagnose configuration issues
- `nvim --clean --headless -l nvim/tests/pack_spec.lua` - Verify native package build hooks

### Terminal Tool Launcher

- `nvim --clean --headless -l nvim/tests/terminal_tool_spec.lua` - Run the terminal-tool regression checks from the repository root
- `/usr/bin/expect nvim/tests/terminal_tool_hunk_render.exp` - Compare real Hunk in a direct PTY and through its production Tool Tab, then verify native resize behavior and host tmux prefix routing; requires Expect, tmux, Git, Hunk, and Neovim on `PATH`

### LSP and Language Support

Configured with multiple language servers (TypeScript, Python, Rust, Go, Lua, JSON, YAML, HTML, CSS, Haskell, Java, Kotlin). Four config layers (lowest to highest priority):

1. **`vim.lsp.config('*')` in `lua/kickstart/plugins/lsp.lua`** — shared client capabilities
2. **nvim-lspconfig defaults** — cmd, filetypes, root_dir, commands (no files needed)
3. **`after/lsp/*.lua`** — servers with substantial custom logic (only `lua_ls`)
4. **Named `vim.lsp.config()` calls in `lua/kickstart/plugins/lsp.lua`** — small overrides (settings, init_options)

Common language facts live as plain, read-only tables in the Language Tooling Inventory at `lua/custom/languages.lua`. Its `lsp_servers`, `mason_tools`, `formatters_by_ft`, and `linters_by_ft` fields use the data shapes consumed by Neovim, Mason Tool Installer, Conform, and nvim-lint. LSP enablement and Mason installation stay explicit because runtime configuration names and package names differ, and some project-owned tools should not be installed by Mason. Plugin setup, event wiring, invocation, and other runtime behavior remain in the plugin modules. Treesitter's package-build parser set remains in `lua/kickstart/parsers.lua`; it is intentionally separate from the Language Tooling Inventory.

Run `nvim -u NONE --headless -l nvim/tests/lsp_hover_spec.lua` to verify native `K` hover documentation renders without clipping.

Run `nvim --clean --headless -l nvim/tests/languages_spec.lua` to verify the production Language Tooling Inventory.

To add a new language server:

1. Add the server's nvim-lspconfig name to `lsp_servers` in `lua/custom/languages.lua`; add its Mason package to `mason_tools` only when Mason owns its installation.
2. Add native Conform or nvim-lint filetype mappings in the same Inventory when the language needs them.
3. Add a `vim.lsp.config()` override in `lua/kickstart/plugins/lsp.lua` if plugin-native settings are needed.
4. Only create `after/lsp/<server_name>.lua` if the server needs substantial logic such as `on_init`.
5. Run the Language Tooling regression check, then use `:Mason` to inspect installation status.

### Terminal Integration

Minimal terminal integration (tmux handles primary terminal functionality):

- `<Esc><Esc>` - Exit terminal mode when needed
- `<C-h/j/k/l>` - Navigate between windows
- flatten.nvim redirects nested `nvim +line file` calls from terminal tools back into the host Neovim instance. `terminal_tool.lua` privately owns the source marker and opaque handoff payload; declarations should not set handoff environment variables or override `EDITOR`.

### Neovim-Owned Terminal Tools

Use `lua/custom/lib/terminal_tool.lua` for any future flow that Neovim should launch as an interactive terminal tool, such as Hunk or lazygit. This is the standard shape:

```lua
require('custom.lib.terminal_tool').create {
  id = 'example',
  command = { 'example' },
  key = '<leader>gx',
  desc = 'Example',
}
```

- Start one persistent Neovim terminal job and Tool Tab per tool. Invoking a tool selects its existing Tool Tab; invoking its toggle from that tab returns directly to the latest non-tool Host Window.
- Keep multiple Tool Tabs independent. Switching tools must not replace the Host Window, and a tool-to-tool launch derives its working directory from the Host Window.
- Restart a tool job inside its existing Tool Tab when the Host Window's effective working directory changes. Native `:tabclose` only hides the live terminal buffer; the next invocation recreates its Tool Tab, while process exit removes the session.
- Let the shared module install the normal-mode mapping; declarations do not receive or inspect mutable buffer, window, tab, or job state. Terminal input stays untouched, so use `<Esc><Esc>` before a normal-mode tool key.
- Use ordinary full-tab windows inside and outside tmux. This keeps sizing native and the host tmux client upstream so its prefix, session picker, and pane navigation remain available while the tool is running.
- Pass through shell-owned `EDITOR`, `VISUAL`, and `GIT_EDITOR`; do not override the editor contract in tool-specific config.
- Keep tool-specific environment exceptions declarative in `env`; reserved editor and handoff variables are rejected so the source marker and shell-owned editor contract cannot be replaced.
- Hunk sets `OPENTUI_GRAPHICS=false` because its OpenTUI renderer otherwise mistakes inherited `TMUX` for its immediate terminal and sends tmux-wrapped graphics probes through Neovim's intervening terminal emulator.
- Editor Handoff opens in the Host Window while preserving the originating Tool Tab. Use `handoff = 'return-and-acknowledge'` only for tools such as lazygit that wait for an Enter after returning; the default `return` policy sends no acknowledgement. The shared module transports the originating process generation through flatten without source-specific branches.
- Keep each plugin file thin: declare the tool id, command, key, description, optional environment, and any exceptional handoff policy.

### Git Integration

Focused on in-editor git context and full working-tree review. Git transactions and object selection are handled by lazygit:

- **gitsigns**: In-editor git signs, blame, and hunk navigation
- `<leader>gg` - Toggle lazygit's Git transaction Tool Tab (custom plugin: `lua/custom/plugins/lazygit.lua`)
- `<leader>gd` - Toggle Hunk's stacked working-tree review Tool Tab (custom plugin: `lua/custom/plugins/hunk.lua`)
- Lazygit and Hunk use the shell-owned global editor contract (`EDITOR=nvim`) for native Editor Handoff; flatten.nvim returns nested Neovim invocations to the Host Window while preserving the originating Tool Tab.
- `<leader>tb` - Toggle git blame line
- `<leader>td` - Toggle inline git diff (deleted lines + word diff)
- `<leader>ga` / `<leader>gr` / `<leader>gu` / `<leader>gp` - Hunk-local actions (stage/add, reset, undo stage, preview)
- `]c` / `[c` - Navigate between git hunks

### File Explorer

Neo-tree file explorer is enabled with right-side positioning and minimal styling:

- `<leader>e` - Toggle neo-tree (reveals current file location)
- Supports multiple sources: filesystem, buffers, git status
- Key mappings: `?` for help, `a` to add files, `d` to delete, `r` to rename
- Switch sources with `<Tab>` (filesystem → buffers → git_status)
- Configured without icons for clean, text-based interface
- Git status colors match the main colorscheme (+, ~, -, etc.)

### Customization Points

- `lua/custom/plugins/` - Drop a new `*.lua` file here and it will be auto-imported by the custom plugin loader
- `lua/custom/languages.lua` - Add or change the native-shaped language-server, Mason-tool, formatter, and linter declarations
- `after/lsp/*.lua` - Add LSP server configs with substantial custom logic
- `vim.lsp.config()` in `lua/kickstart/plugins/lsp.lua` for small LSP server overrides

### Important Settings

- Leader key is Space (`vim.g.mapleader = ' '`)
- Auto-formatting on save enabled (can be disabled per filetype)
- Clipboard integration with system clipboard enabled
- Icons disabled - clean text-based interface without Nerd Font requirements

## Dependencies

External tools required:

- `git`, `make`, `unzip`, C compiler
- `ripgrep` (rg) for searching
- [`fd-find`](https://github.com/sharkdp/fd) for file finding (optional, Telescope uses it if available)
- [`tree-sitter-cli`](https://github.com/tree-sitter/tree-sitter) for Treesitter parser management (`brew install tree-sitter-cli`)
- Clipboard tool (`pbcopy` on macOS, `xclip`/`xsel` on Linux)
- Language-specific tools (npm for TypeScript, go for Golang, etc.)

## Configuration Philosophy

This configuration prioritizes:

- **Text editing focus**: Core LSP, search, and navigation functionality
- **Native Neovim first**: Use built-in LSP, diagnostics, `vim.pack`, Lua APIs, terminal buffers, and standard runtime behavior before adding plugin abstractions
- **Native Lua API first**: Prefer stable `vim.*`/`vim.api.*` Lua APIs where they exist (for example `vim.system()` for external commands and `vim.uv` for libuv). Use `vim.fn.*` for documented Vimscript-only functions such as `stdpath()`, `executable()`, registers, ranges, and prompts.
- **Minimal external dependencies**: Add plugins only for clear, durable capabilities; avoid wrapping native behavior in extra layers
- **Local performant tools**: For workflows outside Neovim's core job, prefer thin integrations with self-made or locally-owned CLI tools over large in-editor plugin surfaces
- **Readability and documentation**: Lean init.lua plus one file per plugin under `lua/kickstart/plugins/` and `lua/custom/plugins/`
- **Integration with ecosystem**: Works seamlessly with tmux-based workflows

## Coding Guidelines

### Comments

Only add comments when genuinely clarifying or documenting key behavior. Aim to write clear and readable code that is self-explanatory through:

- Descriptive variable and function names
- Logical code structure and organization
- Small, focused functions with clear purposes

Avoid redundant comments that simply restate what the code does. Reserve comments for:

- Complex algorithms or business logic
- Non-obvious configuration choices
- Important architectural decisions
- External API or plugin-specific requirements

## Memory

### Configuration Verification

- Always verify that there's only one way to do something in the configuration

### Development Practices

- Always read the latest source code and documentation (plugin READMEs, Neovim help, plugin source) before making any change
- Always explain your reasoning and cite sources before implementing — never change code without understanding why
- Always inline clear, concise and useful documentation in code
- Always explain choices and follow latest standards and best practices
- Before adding a plugin, check whether native Neovim, an existing local helper, or a small self-made tool can solve the problem with less long-term weight
- Prioritize reliable, cross-platform solutions over clever hacks
- The simplest solution is often the most correct and maintainable
- Never remove kickstart.nvim instructional comments or other educational comments
- Preserve multi-platform compatibility checks (e.g., Windows detection) even on a macOS-only setup
