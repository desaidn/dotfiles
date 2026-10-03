# AGENTS.md

Guidance for coding agents working on the nvim config. See [`../AGENTS.md`](../AGENTS.md) for monorepo-level conventions.

Usage, keybindings, maintenance commands, and troubleshooting belong in
[README.md](README.md). Keep this file focused on configuration ownership,
constraints, and required validation.

## Core Architecture

### File Structure

- `init.lua` - Core settings, basic keymaps, autocommands, native `vim.pack` build hooks, core UI plugins, and top-level module imports
- `colors/custom.lua` - Custom colorscheme (transparent backgrounds, peach accents)
- `lua/kickstart/plugins/` - Upstream-oriented Kickstart modules, explicitly loaded by `lua/kickstart/plugins/init.lua`.
  - `blink-cmp.lua` - blink.cmp completion with native Neovim snippets
  - `telescope.lua` - Telescope pickers and LSP reference/definition keymaps
  - `gitsigns.lua` - Git signs, blame, and hunk navigation keymaps
  - `neo-tree.lua` - File explorer (right-side, text-based icons)
  - `autopairs.lua` - Auto-close brackets, quotes, etc.
- `lua/kickstart/health.lua` - Health check for `:checkhealth`
- `lua/custom/lib/neovim.lua` - One Neovim minimum-version rule shared by the installer, startup, and health check; accept newer releases and keep prerelease advice in health reporting
- `lua/custom/lib/pack.lua` - Shared `vim.pack` helper, GitHub URL helper, and `PackChanged` build hooks
- `lua/custom/lib/terminal_tool.lua` - Shared launcher for Neovim-owned terminal tools; use this for future flows that should run in a persistent Tool Tab while leaving host tmux navigation available when Neovim is running in the tmux fallback
- `lua/custom/languages/` - Repository-owned language tooling, loaded explicitly by `init.lua`:
  - `init.lua` - deterministic language-tooling bootstrap
  - `config.lua` - explicit adapter selection, inventory collection, ownership validation, and activation
  - `context.lua` - buffer-derived project roots and collision-resistant workspace-data paths; it never changes Neovim's current directory
  - `capabilities.lua` - shared LSP capability policy, including single-owner formatting
  - `lsp.lua`, `treesitter.lua`, and `format.lua` - shared LSP, parsing, and formatting surfaces
  - `dap.lua` - shared lazy DAP lifecycle, UI, controls, buffer-specific debugger registration, and root-aware `launch.json` provider
  - `adapters/` - one file per language family with LSP/DAP support, plus `supporting.lua` for families without either capability; each owns its settings and project behavior
- `lua/custom/plugins/` - Repository-owned plugin modules, explicitly required by `lua/custom/plugins/init.lua`:
  - `init.lua` - Custom plugin imports
  - `fff.lua` - fff.nvim fuzzy file/grep finder (owns `<leader>sf` and `<leader>sg`)
  - `lazygit.lua` - Thin lazygit Git transaction launcher over `lua/custom/lib/terminal_tool.lua` (owns `<leader>gg`)
  - `hunk.lua` - Thin Hunk stacked review launcher over `lua/custom/lib/terminal_tool.lua`; declares its working-tree and staged input variants (owns `<leader>gd` and `<leader>gD`)
  - `flatten.lua` - Editor handoff for nested `nvim` calls launched from Neovim-owned tools
- `tests/terminal_tool_spec.lua` - Headless regression harness for the terminal-tool declaration interface, Tool Tab persistence, Host Window return, editor shutdown, handoff, failure/race recovery, environment handling, and host tmux input routing
- `tests/flatten_swap_spec.lua` - Two-Neovim regression proving that a live swap collision cannot abort a production Flatten handoff after Neovim installs the requested buffer
- `tests/pack_spec.lua` - Headless checks for native package build hooks, including nvim-treesitter parser/query installation and updates
- `tests/neovim_spec.lua` - Headless checks for Neovim version boundaries and consistent startup/health behavior
- `tests/neo_tree_spec.lua` - Headless regression harness for selected-node path copying and refreshing a visible filesystem tree after its watcher misses an external change
- `tests/languages/` - Headless language-tooling regression harnesses for configuration, project context, JDTLS, linting, DAP, JavaScript/TypeScript, Python, Rust, and C/C++ behavior
- `tests/terminal_tool_hunk_render.exp` and `tests/terminal_tool_hunk_render_init.lua` - Real-PTY regression harness loading the production Hunk declaration and proving two sessions render without graphics-protocol artifacts, survive switching and resize, isolate process exit, and stop test-owned processes during teardown
- `nvim-pack-lock.json` - Native `vim.pack` plugin version lockfile

### Plugin Management

Use native `vim.pack`. Plugin modules own their `vim.pack.add()` calls and
configure packages directly; do not recreate lazy.nvim's trigger DSL. Each
plugin must supply a clear capability not already covered by Neovim or a local
helper. Keep fff.nvim responsible for files/live grep and Telescope for the
other pickers. Keep Blink's native snippet engine and personal VS Code source;
bundled friendly-snippets discovery stays disabled.

### Keymap ownership

Use the [documented keybindings](README.md#key-bindings). The editing and
debugging interface is language-neutral: language plugins may expose
backend-specific commands, but must not claim a separate keymap namespace or
override shared LSP mappings. Keep DAP lazy on first use, with the Rust
attachment initialization needed by rustaceanvim.

## Development Workflows

### Headless Specs

Run one language-tooling spec in an isolated Neovim process:

```sh
nvim --clean --headless -l nvim/tests/languages/context_spec.lua
```

Run every Lua `*_spec.lua` harness:

```sh
for spec in nvim/tests/**/*_spec.lua; do
  nvim --clean --headless -l "$spec" || exit 1
done
```

`--clean` excludes the normal user configuration. Each harness adds this
repository's `nvim/lua` directory to `package.path` and loads the production
module under test, using focused API/plugin stubs where a real server or
adapter is outside the test's scope.

Run the matching checks when their surface changes:

- `nvim --clean --headless -l nvim/tests/diagnostics.lua` scans every Neovim Lua file, including tests, with the installed Lua language server and this configuration's Neovim workspace settings. It checks every diagnostic severity and requires the Mason-managed `lua-language-server`.
- `nvim --clean --headless -l nvim/tests/neovim_spec.lua` for the shared Neovim minimum, prerelease handling, and startup/health consumers.
- `nvim --clean --headless -l nvim/tests/pack_spec.lua` for native package build hooks.
- `nvim --clean --headless -l nvim/tests/languages/treesitter_spec.lua` for parser attachment after asynchronous installation and buffer lifetime changes.
- `nvim --clean --headless -l nvim/tests/neo_tree_spec.lua` for selected-node path copying and refresh after a missed filesystem change.
- `nvim --clean --headless -l nvim/tests/terminal_tool_spec.lua` for terminal-tool lifecycle, handoff, and host input routing.
- `/usr/bin/expect nvim/tests/terminal_tool_hunk_render.exp` for real Hunk rendering, switching, isolated exit, resize, and host tmux prefix routing. It requires Expect, tmux, Git, Hunk, and Neovim on `PATH`.

### LSP and Language Support

Three config layers apply, from lowest to highest priority:

1. **`vim.lsp.config('*')` in `lua/custom/languages/lsp.lua`** — shared client capabilities
2. **nvim-lspconfig defaults** — cmd, filetypes, root_dir, commands (no files needed)
3. **Named configurations in `lua/custom/languages/adapters/`** — server-specific settings, callbacks, and declared DAP root/type routing collected by `config.lua` and applied through `vim.lsp.config()` and the DAP provider

Each language adapter owns its native configuration and language-specific behavior. Importing an adapter must not load plugins, register commands/autocommands, or start servers. `config.lua` collects one explicit ordered adapter list, shared tooling initializes, then the same adapters' optional `setup()` functions activate integration. Keep debugger setup lazy. JavaScript owns ESLint scheduling and project policy; Python owns Ruff capability overlap.

C/C++ owns clangd, the C/C++ parsers, Conform's `clang-format` mapping, and lazy
CodeLLDB registration. Preserve clangd's upstream callbacks and source/header
commands; disable its formatting through the shared capability helper on
attachment. Keep Conform's native filename/range behavior when selecting an
explicit `b:clang_format` executable, and keep C/C++ save formatting disabled.
Projects own compilation databases, flags, formatter versions, and builds; never
add DuckDB paths, global include flags, or automatic build commands here.

C/C++ and Rust share CodeLLDB. Preserve a previously registered adapter and use
the loopback server form expected by rustaceanvim. Launch defaults and project
launch files use the same buffer-derived context; C/C++'s explicit launch root
takes priority over an ancestor clangd root. Run `c_cpp_spec.lua`,
`dap_launch_spec.lua`, `dap_spec.lua`, `languages_spec.lua`, and `rust_spec.lua`
after changing this integration. `c_cpp_spec.lua` uses installed Conform,
nvim-lspconfig, nvim-dap, and rustaceanvim; provide writable Neovim state/cache
directories when running it in a sandbox. Verify live compiler, clangd,
formatter, and debug behavior separately when changing their runtime contract.

Adapters explicitly declare their full Mason and parser requirements, including names shared with other adapters. The collector deduplicates only these lists and rejects duplicate LSP or filetype mappings within a category, naming both owners. Its fields retain the native shapes consumed by Neovim, Mason Tool Installer, nvim-treesitter, Conform, nvim-lint, and nvim-dap. `treesitter_parsers` is authoritative: only listed parsers attach or install at runtime, and the same list is installed or updated after nvim-treesitter package changes. See [ADR 0014](../docs/adr/0014-co-locate-language-settings-and-behavior.md) for the ownership decision.

Parser installation can outlive the buffer that requested it. Recheck that the
buffer is valid, loaded, and still uses the requested language before attaching;
apply buffer-local settings to that buffer explicitly.

Java and Rust are intentional lifecycle exceptions: nvim-jdtls and rustaceanvim own their respective language-server startup, so neither server appears in generic `vim.lsp.enable` configuration. Java's adapter starts JDTLS per project and initializes its DAP integration before attachment.

Preserve the [TypeScript semantic-ownership contract](README.md#language-project-requirements):
only the exact root-local compiler/language service may supply project
semantics, selected by version after root recognition and Deno exclusion.
The compatibility client must reject fallback or mismatched version reports.
Mason owns the compatibility transport, js-debug, and `eslint_d`; projects own
TypeScript, ESLint, runtime semantics, and non-trivial Node/browser
`.vscode/launch.json` files.

This personal configuration explicitly assumes opened development repositories
are trusted. JavaScript/TypeScript startup executes the root-local compiler to
select a semantic route, and lint configuration may execute project code. Keep
debug launches user-triggered and loopback-bound; do not add automatic project
tasks or silent trust expansion.

To add a new language server:

1. Add or extend the language family's adapter under `lua/custom/languages/adapters/`. Declare the server's nvim-lspconfig name and native configuration in `lsp_servers`; use an empty table when upstream defaults suffice.
2. Declare its complete Mason-owned packages and Treesitter parsers in that adapter, including shared tools such as Prettier.
3. Keep native formatter/linter/DAP mappings, format-on-save policy, project roots, and optional integration setup in the same adapter. Java and Rust retain their specialized LSP startup.
4. Add a new adapter to the one ordered list in `config.lua`; files are not automatically enabled. Families without LSP/DAP belong in `supporting.lua`.
5. Restart Neovim, then use `:Mason` to inspect installation status.

### Terminal Integration

Herdr owns the daily workspace and tmux remains the top-level fallback. Do not
duplicate either manager's navigation in Neovim. `terminal_tool.lua` privately
owns the source marker and opaque Editor Handoff payload used by flatten.nvim;
declarations must not set handoff environment variables or override `EDITOR`.
See [terminal navigation](README.md#terminal-navigation) for usage.

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

A variant may also declare an `ex_command` when an external workflow needs a
deterministic Neovim entry point. The command and key invoke the exact same
private toggle callback; declarations still receive no lifecycle controller.
Keys and Ex commands must be unclaimed when the declaration loads. Ex command
names follow Neovim's uppercase-leading alphanumeric syntax, and registration
is atomic so a rejected declaration preserves existing mappings and commands.

- Start one persistent Neovim terminal job and Tool Tab per selected tool instance. Invoking a tool selects its existing Tool Tab; invoking its running variant's toggle from that tab returns directly to the latest non-tool Host Window. Before Neovim exits, the shared module stops and briefly waits for every active terminal-tool job across all instances.
- Variants share one Tool Tab, one process slot, one `env`, and one handoff identity within each instance. Selecting a variant other than the running one restarts that instance's job in place; only the running variant's own key hides the Tool Tab. Prefer variants over a second tool id when one CLI's inputs are alternative views of the same review, since duplicate processes within a repository make session selectors ambiguous.
- A `variants` list must be a gapless list of two or more entries with distinct keys and distinct commands; use a top-level `command` for a single input. These are load-time assertions because a silently dropped entry would leave a documented key doing nothing.
- Keep declarations singleton by default. A singleton restarts inside its existing Tool Tab when the Host Window's effective working directory changes; this remains LazyGit's policy.
- Use `instances = 'cwd'` only when a tool should retain concurrent instances selected by canonical Host Window working directory. Hunk uses this policy so reviews in different repositories or worktrees remain live together.
- Keep every Tool Tab instance independent. Switching tools or contexts must not replace the Host Window, and a tool-to-tool launch derives its working directory from the Host Window. Native `:tabclose` hides only that instance's live terminal buffer; the next invocation recreates its Tool Tab, while process exit removes only that instance.
- Let the shared module install the normal-mode mapping; declarations do not receive or inspect mutable buffer, window, tab, or job state. Terminal input stays untouched, so use `<Esc><Esc>` before a normal-mode tool key.
- Let the shared module register an optional variant `ex_command`; do not duplicate a mapping's launch behavior in plugin-specific command callbacks. If an external workflow invokes that shared callback during Neovim startup, the module coalesces requests and waits until after `UIEnter` before starting the terminal job so automatic terminal-capability detection matches an interactive mapping.
- Use ordinary full-tab windows inside and outside tmux. This keeps sizing native and, when using the tmux fallback, keeps the host tmux client upstream so its prefix, session picker, and pane navigation remain available while the tool is running.
- Pass through shell-owned `EDITOR`, `VISUAL`, and `GIT_EDITOR`; do not override the editor contract in tool-specific config.
- Keep tool-specific environment exceptions declarative in `env`; reserved editor and handoff variables are rejected so the source marker and shell-owned editor contract cannot be replaced.
- Hunk sets `OPENTUI_GRAPHICS=false` because its OpenTUI renderer otherwise mistakes inherited `TMUX` for its immediate terminal and sends tmux-wrapped graphics probes through Neovim's intervening terminal emulator.
- Editor Handoff opens in the global latest Host Window while preserving the originating Tool Tab. Use `handoff = 'return-and-acknowledge'` only for tools such as lazygit that wait for an Enter after returning; the default `return` policy sends no acknowledgement. The shared module validates the opaque originating instance identity and process generation through flatten without source-specific branches.
- Keep each plugin file thin: declare the tool id, either a command with its key and description or a `variants` list carrying those per input, optional instance policy and environment, and any exceptional handoff policy.

### Git Integration

Keep gitsigns actions hunk-local and use LazyGit for Git transactions and object
selection. Hunk owns full stacked working-tree and staged review. Hunk's two
review inputs share a Tool Tab and process per working directory to keep
`--watch` live and the `--repo .` selector on `hunk session` subcommands unambiguous. See the
[Git guide](README.md#git) for mappings and Editor Handoff behavior.

When `HUNK_REVIEW_BASE_OID` and `HUNK_REVIEW_HEAD_OID` supply full commit
object IDs, `<leader>gd` and `:HunkReview` share the aggregate `BASE...HEAD`
review toggle. If either variable is present, the Neovim adapter must reject
incomplete, malformed, or mismatched-length IDs before registration. The caller
owns commit resolution, review-base selection, and launching Neovim in the
intended checkout. Hunk's `e` action returns through flatten.nvim to that
review's Neovim with normal project-root discovery and full language tooling.
Keep the environment contract independent of any workflow CLI or agent harness.

## Dependencies

Follow the [root dependency inventory](../README.md#dependency-ownership),
including its Neovim minimum and tool version floors. Neovim owns
plugins and parsers; Mason owns `mason_tools`. Do not duplicate those tools as
machine packages or move Mise-owned runtimes into Homebrew. Keep display-aware
clipboard selection and the copy-only OSC 52 fallback in `init.lua`.

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
