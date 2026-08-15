# AGENTS.md

Guidance for coding agents working on the nvim config. See [`../AGENTS.md`](../AGENTS.md) for monorepo-level conventions.

## Neovim Configuration Overview

This is a Neovim configuration based on kickstart.nvim, providing a well-documented starting point for Neovim customization. `init.lua` handles core settings, basic keymaps, native `vim.pack` build hooks, and core UI plugins; each modular plugin configuration lives under `lua/kickstart/plugins/` or `lua/custom/plugins/`.

## Core Architecture

### File Structure

- `init.lua` - Core settings, basic keymaps, autocommands, native `vim.pack` build hooks, core UI plugins, and top-level module imports
- `colors/custom.lua` - Custom colorscheme (transparent backgrounds, peach accents)
- `lua/kickstart/plugins/` - Auto-imported by `lua/kickstart/plugins/init.lua` in the established startup order; each plugin file calls `vim.pack.add()` for the plugin(s) it owns and then configures them:
  - `lsp.lua` - nvim-lspconfig, Mason, fidget, and generic application of the Language Tooling Inventory's native LSP configurations
  - `blink-cmp.lua` - blink.cmp completion with LuaSnip
  - `conform.lua` - conform.nvim formatter config and format-on-save
  - `telescope.lua` - Telescope pickers and LSP reference/definition keymaps
  - `treesitter.lua` - nvim-treesitter and treesitter-context, restricted to the Inventory's parser whitelist
  - `gitsigns.lua` - Git signs, blame, and hunk navigation keymaps
  - `neo-tree.lua` - File explorer (right-side, text-based icons)
  - `debug.lua` - DAP debugger keymaps; shared setup stays lazy until a debug action or Rust LSP attachment
  - `rust.lua` - rustaceanvim-owned rust-analyzer and CodeLLDB integration
  - `lint.lua` - nvim-lint with eslint_d and ruff; ESLint runs from the nearest config root
  - `autopairs.lua` - Auto-close brackets, quotes, etc.
- `lua/kickstart/health.lua` - Health check for `:checkhealth`
- `lua/custom/lib/pack.lua` - Shared `vim.pack` helper, GitHub URL helper, and `PackChanged` build hooks
- `lua/custom/lib/dap.lua` - Shared lazy nvim-dap, DAP UI, and debugpy setup used by generic debugger keymaps and Rust attachment
- `lua/custom/lib/plugins_loader.lua` - Shared sorted directory plugin module loader used by `kickstart.plugins` and `custom.plugins`
- `lua/custom/lib/terminal_tool.lua` - Shared launcher for Neovim-owned terminal tools; use this for future flows that should run in a persistent Tool Tab while leaving host tmux navigation available when Neovim is running in the tmux fallback
- `lua/custom/languages.lua` - Canonical read-only Language Tooling Inventory: native LSP configurations, Mason packages, the Treesitter parser whitelist, Conform formatting policy, and nvim-lint mappings
- `lua/custom/plugins/` - Auto-imported by `lua/custom/plugins/init.lua`; every sibling `*.lua` file is required, following symlinks:
  - `init.lua` - Custom plugin loader
  - `fff.lua` - fff.nvim fuzzy file/grep finder (owns `<leader>sf` and `<leader>sg`)
  - `lazygit.lua` - Thin lazygit Git transaction launcher over `lua/custom/lib/terminal_tool.lua` (owns `<leader>gg`)
  - `hunk.lua` - Thin Hunk stacked review launcher over `lua/custom/lib/terminal_tool.lua`; declares its working-tree and staged input variants (owns `<leader>gd` and `<leader>gD`)
  - `flatten.lua` - Editor handoff for nested `nvim` calls launched from Neovim-owned tools
- `tests/terminal_tool_spec.lua` - Headless regression harness for the terminal-tool declaration interface, Tool Tab persistence, Host Window return, editor shutdown, handoff, failure/race recovery, environment handling, and host tmux input routing
- `tests/pack_spec.lua` - Headless checks for native package build hooks, including nvim-treesitter parser/query installation and updates
- `tests/neo_tree_spec.lua` - Headless regression harness for selected-node path copying and refreshing a visible filesystem tree after its watcher misses an external change
- `tests/lint_spec.lua` - Headless regression harness for nearest ESLint config CWD selection and fallback behavior
- `tests/rust_spec.lua` - Headless regression harness for rustaceanvim ownership, lazy DAP initialization, and the shared keymap boundary
- `tests/terminal_tool_hunk_render.exp` and `tests/terminal_tool_hunk_render_init.lua` - Real-PTY regression harness loading the production Hunk declaration and proving two sessions render without graphics-protocol artifacts, survive switching and resize, isolate process exit, and stop test-owned processes during teardown
- `nvim-pack-lock.json` - Native `vim.pack` plugin version lockfile

### Plugin Management

Uses native `vim.pack` as the plugin manager. Plugin modules should stay simple and idiomatic: call `vim.pack.add()` for the package(s) they own, configure them directly, and avoid recreating lazy.nvim's trigger DSL. Prefer native Neovim APIs before adding plugins, and keep each plugin responsible for a clear capability that is not already covered by core Neovim or a local helper. Core plugins include:

- **LSP**: nvim-lspconfig with Mason for auto-installation. Native Neovim 0.11+ server configuration lives in the Language Tooling Inventory and is applied by `lua/kickstart/plugins/lsp.lua`
- **Completion**: blink.cmp with LuaSnip for snippets
- **Fuzzy Finding**: fff.nvim for files and live grep (`<leader>sf`, `<leader>sg`); Telescope with fzf-native for help, keymaps, diagnostics, buffers, LSP symbols, and word-under-cursor grep
- **Git Integration**: gitsigns (in-editor signs, blame, local hunks); Hunk (working-tree and staged review); lazygit (Git transaction UI)
- **Treesitter**: Syntax highlighting, code parsing, and context (nvim-treesitter-context)
- **Formatting**: conform.nvim for auto-formatting
- **Linting**: nvim-lint with eslint_d, ruff
- **Debugging**: nvim-dap with Python (debugpy via uv) and Rust (rustaceanvim + Mason CodeLLDB)
- **UI**: which-key, mini.nvim (statusline, surround, text objects), undotree, todo-comments

### Key Bindings Structure

- Leader key: `<Space>`
- Search operations: `<leader>s*` (files, grep, help, keymaps, diagnostics, etc.)
- Toggle options: `<leader>t*` — `th` inlay hints, `tb` git blame line, `td` inline git diff, `ts` spell check
- Git operations: `<leader>gg` (lazygit), `<leader>gd` / `<leader>gD` (Hunk working-tree and staged review), `<leader>g*` (hunk-local gitsigns actions), `]c`/`[c` (hunk navigation)
- LSP operations: `gr*` prefix (Neovim 0.11 defaults for rename/code action, Telescope overrides for references/definitions)
- Format: `<leader>f` (format buffer)
- Explorer: `<leader>e` (neo-tree toggle)
- Undo tree: `<leader>u` (toggle undotree)
- Path copy: `<leader>p*` (copy absolute/relative file paths)
- Debug: `<leader>b` (breakpoint), `F1-F3` (stepping), `F5` (continue), `F7` (DAP UI). These keys lazy-load and configure DAP on first use; Rust also initializes it when rust-analyzer attaches so rustaceanvim can create CodeLLDB configurations.
- Diagnostic quickfix: `<leader>q`

The editing and debugging interface is language-neutral. Language plugins may
provide backend-specific commands, but must not claim a separate keymap
namespace or override shared LSP mappings. Rustaceanvim's advanced actions are
available through `:RustLsp runnables`, `:RustLsp testables`, `:RustLsp
debuggables`, `:RustLsp expandMacro`, and `:RustLsp hover actions` while a
common target-selection interface is designed.

## Development Workflows

### Plugin Management

- `:lua vim.pack.update(nil, { offline = true })` - Inspect plugin state and pending updates
- `:lua vim.pack.update()` - Update all plugins
- `:Mason` - Manage LSP servers, formatters, linters, and debuggers
- `:checkhealth` - Diagnose configuration issues
- `nvim --clean --headless -l nvim/tests/pack_spec.lua` - Verify native package build hooks

### Terminal Tool Launcher

- `nvim --clean --headless -l nvim/tests/terminal_tool_spec.lua` - Run the terminal-tool regression checks from the repository root
- `/usr/bin/expect nvim/tests/terminal_tool_hunk_render.exp` - Compare real Hunk in a direct PTY and through two production Tool Tabs, then verify switching, isolated exit, native resize behavior, and host tmux prefix routing; requires Expect, tmux, Git, Hunk, and Neovim on `PATH`

### LSP and Language Support

Configured with multiple language servers (TypeScript, Python, Rust, Lua, JSON, YAML, HTML, CSS, Haskell, Java, Kotlin). Three config layers (lowest to highest priority):

1. **`vim.lsp.config('*')` in `lua/kickstart/plugins/lsp.lua`** — shared client capabilities
2. **nvim-lspconfig defaults** — cmd, filetypes, root_dir, commands (no files needed)
3. **Named configurations in `lua/custom/languages.lua`** — server-specific settings and callbacks applied through `vim.lsp.config()`

Common language facts live in the Language Tooling Inventory at `lua/custom/languages.lua`. Its fields use the native data shapes consumed by Neovim, Mason Tool Installer, nvim-treesitter, Conform, and nvim-lint. `treesitter_parsers` is authoritative: only listed parsers attach or install at runtime, and the same list is installed or updated after nvim-treesitter package changes. LSP enablement and Mason installation stay explicit because runtime configuration names and package names differ, and some project-owned tools should not be installed by Mason. Plugin setup, event wiring, invocation, and other runtime behavior remain in the plugin modules.

To add a new language server:

1. Add the server's nvim-lspconfig name and native configuration to `lsp_servers` in `lua/custom/languages.lua`; use an empty table when nvim-lspconfig defaults are sufficient.
2. Add its Mason package to `mason_tools` only when Mason owns installation, and add the required Treesitter parsers to `treesitter_parsers`.
3. Add native Conform or nvim-lint filetype mappings and any format-on-save policy in the same Inventory when the language needs them.
4. Restart Neovim, then use `:Mason` to inspect installation status.

### Terminal Integration

Minimal terminal integration: Herdr owns the daily top-level workspace, tmux remains the top-level fallback/compatibility multiplexer, and Neovim does not duplicate either manager's navigation:

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
  instances = 'cwd', -- Optional; declarations are singleton by default.
}
```

A tool whose single surface should review more than one input declares `variants` instead of a top-level `command`/`key`/`desc`, and each variant owns its own key:

```lua
require('custom.lib.terminal_tool').create {
  id = 'example',
  variants = {
    { command = { 'example' }, key = '<leader>gx', desc = 'Example' },
    { command = { 'example', '--other-input' }, key = '<leader>gX', desc = 'Example (other input)' },
  },
}
```

- Start one persistent Neovim terminal job and Tool Tab per selected tool instance. Invoking a tool selects its existing Tool Tab; invoking its running variant's toggle from that tab returns directly to the latest non-tool Host Window. Before Neovim exits, the shared module stops and briefly waits for every active terminal-tool job across all instances.
- Variants share one Tool Tab, one process slot, one `env`, and one handoff identity within each instance. Selecting a variant other than the running one restarts that instance's job in place; only the running variant's own key hides the Tool Tab. Prefer variants over a second tool id when one CLI's inputs are alternative views of the same review, since duplicate processes within a repository make session selectors ambiguous.
- A `variants` list must be a gapless list of two or more entries with distinct keys and distinct commands; use a top-level `command` for a single input. These are load-time assertions because a silently dropped entry would leave a documented key doing nothing.
- Keep declarations singleton by default. A singleton restarts inside its existing Tool Tab when the Host Window's effective working directory changes; this remains LazyGit's policy.
- Use `instances = 'cwd'` only when a tool should retain concurrent instances selected by canonical Host Window working directory. Hunk uses this policy so reviews in different repositories or worktrees remain live together.
- Keep every Tool Tab instance independent. Switching tools or contexts must not replace the Host Window, and a tool-to-tool launch derives its working directory from the Host Window. Native `:tabclose` hides only that instance's live terminal buffer; the next invocation recreates its Tool Tab, while process exit removes only that instance.
- Let the shared module install the normal-mode mapping; declarations do not receive or inspect mutable buffer, window, tab, or job state. Terminal input stays untouched, so use `<Esc><Esc>` before a normal-mode tool key.
- Use ordinary full-tab windows inside and outside tmux. This keeps sizing native and, when using the tmux fallback, keeps the host tmux client upstream so its prefix, session picker, and pane navigation remain available while the tool is running.
- Pass through shell-owned `EDITOR`, `VISUAL`, and `GIT_EDITOR`; do not override the editor contract in tool-specific config.
- Keep tool-specific environment exceptions declarative in `env`; reserved editor and handoff variables are rejected so the source marker and shell-owned editor contract cannot be replaced.
- Hunk sets `OPENTUI_GRAPHICS=false` because its OpenTUI renderer otherwise mistakes inherited `TMUX` for its immediate terminal and sends tmux-wrapped graphics probes through Neovim's intervening terminal emulator.
- Editor Handoff opens in the global latest Host Window while preserving the originating Tool Tab. Use `handoff = 'return-and-acknowledge'` only for tools such as lazygit that wait for an Enter after returning; the default `return` policy sends no acknowledgement. The shared module validates the opaque originating instance identity and process generation through flatten without source-specific branches.
- Keep each plugin file thin: declare the tool id, either a command with its key and description or a `variants` list carrying those per input, optional instance policy and environment, and any exceptional handoff policy.

### Git Integration

Focused on in-editor git context and full review of the working tree and the index. Git transactions and object selection are handled by lazygit:

- **gitsigns**: In-editor git signs, blame, and hunk navigation
- `<leader>gg` - Toggle lazygit's Git transaction Tool Tab (custom plugin: `lua/custom/plugins/lazygit.lua`)
- `<leader>gd` / `<leader>gD` - Toggle Hunk's stacked review Tool Tab on the working tree or the index (custom plugin: `lua/custom/plugins/hunk.lua`). Each working directory owns one instance; both keys drive that instance's Tool Tab and process, and pressing the other input's key retargets the review in place. This keeps `--watch` live and keeps the `--repo .` selector on `hunk session` subcommands matching exactly one session per repository for agent notes.
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
- `<leader>pa` / `<leader>pr` - Copy the selected file or directory's absolute/tree-root-relative path
- Switch sources with `<Tab>` (filesystem → buffers → git_status)
- Configured without icons for clean, text-based interface
- Git status colors match the main colorscheme (+, ~, -, etc.)
- `nvim --clean --headless -l nvim/tests/neo_tree_spec.lua` - Verify selected-node path copying and refresh on `FocusGained` after a watcher failure

### Customization Points

- `lua/custom/plugins/` - Drop a new `*.lua` file here and it will be auto-imported by the custom plugin loader
- `lua/custom/languages.lua` - Add or change native-shaped LSP, Mason, Treesitter, formatter, format-on-save, and linter declarations

### Important Settings

- Leader key is Space (`vim.g.mapleader = ' '`)
- Auto-formatting on save enabled (can be disabled per filetype)
- Clipboard integration with system clipboard enabled. Remote sessions with no
  display and no tmux fall back to a copy-only OSC 52 provider (`init.lua`)
- Icons disabled - clean text-based interface without Nerd Font requirements

## Dependencies

Keep installation ownership aligned with the repository-level dependency
inventory:

- The host provides exactly stable Neovim 0.12.4, `git`, `curl`, `tar`,
  `gzip`, `unzip`, `diff`, a C compiler, `rg`, and tree-sitter CLI 0.26.1 or
  newer.
- The host also provides `lazygit` and `hunk` for their production Tool Tabs,
  plus a platform clipboard provider where a display is available; remote
  sessions rely on the OSC 52 fallback instead.
- Hunk must be version 0.18.1 or newer for concurrent watch sessions.
- Mise owns Node.js/npm, Python, Rust with Cargo, Clippy, rustfmt, and rust-src, and
  Amazon Corretto JDK 21 (`corretto-21.0.12.8.1`). Python debugging
  additionally requires the standalone `uv` CLI.
- Haskell is an explicit ownership exception: the current Mason HLS recipe
  invokes `ghcup`, so `ghcup` must be available before Mason performs a clean
  inventory install.
- Neovim owns plugins and Treesitter parsers; Mason owns the packages listed in
  `mason_tools`. Do not duplicate those tools as machine packages.

`make` is optional and only enables telescope-fzf-native and LuaSnip's
jsregexp build. `fd` is not a base dependency because fff.nvim owns normal file
finding. `/usr/bin/expect` is required only by the real-PTY Hunk regression
test. See `../docs/dependency-research.md` for package mappings and source
evidence.

## Configuration Philosophy

This configuration prioritizes:

- **Text editing focus**: Core LSP, search, and navigation functionality
- **Native Neovim first**: Use built-in LSP, diagnostics, `vim.pack`, Lua APIs, terminal buffers, and standard runtime behavior before adding plugin abstractions
- **Native Lua API first**: Prefer stable `vim.*`/`vim.api.*` Lua APIs where they exist (for example `vim.system()` for external commands and `vim.uv` for libuv). Use `vim.fn.*` for documented Vimscript-only functions such as `stdpath()`, `executable()`, registers, ranges, and prompts.
- **Minimal external dependencies**: Add plugins only for clear, durable capabilities; avoid wrapping native behavior in extra layers
- **Local performant tools**: For workflows outside Neovim's core job, prefer thin integrations with self-made or locally-owned CLI tools over large in-editor plugin surfaces
- **Readability and documentation**: Lean init.lua plus one file per plugin under `lua/kickstart/plugins/` and `lua/custom/plugins/`
- **Integration with ecosystem**: Works inside the Herdr daily workspace while preserving tmux-specific host routing when tmux is chosen as the fallback

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
