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
- Debugging through nvim-dap: js-debug for JavaScript/TypeScript, nvim-jdtls with Java debug/test bundles, debugpy for Python, and CodeLLDB for C/C++ and Rust (through rustaceanvim).
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
while debug targets use their project environments. Both `python` and `debugpy`
project launch types are supported. Python test commands initialize the debugger
on first use and select the runner, test target, and directory from the source
project; changing the editor's directory is unnecessary. The nearest test or
project marker sets the test directory, so nested `pytest.ini` or `manage.py`
files can change it without changing the project interpreter or `launch.json`
lookup. Explicit `python` or `pythonPath` launch
settings take precedence. JavaScript/TypeScript DAP
uses Mason's js-debug adapter while projects own non-trivial launch
configuration. Restart Neovim after changing a project's installed TypeScript
version so its semantic route is recalculated.

Node lockfile roots include `npm-shrinkwrap.json`. ESLint runs from the source
buffer's nearest package/config directory (or its own directory when neither
exists), with the project's installed ESLint. An absent project installation
is skipped instead of using eslint_d's bundled version. A newly installed
eslint_d becomes available on the next lint event without restarting Neovim.

This personal editor configuration assumes repositories opened for development
are trusted: JavaScript/TypeScript startup executes the project's root-local
compiler to select a semantic route, and project lint configuration can execute
code. Review untrusted checkouts before opening them in Neovim. Debug launches
remain explicit user actions and bind the adapter to loopback.

### C and C++

Open a `.c`, `.cpp`, or header file to start clangd automatically. It provides
completion, diagnostics, definitions, references, rename, and hover information.
Use `grd`, `grr`, `grn`, and `K`, plus `:LspClangdSwitchSourceHeader` to move
between an implementation and its header. C/C++ Treesitter parsers provide
highlighting. Opening a file never starts a build or debug session.

**Give clangd the project's build settings.** Most substantial projects need
`compile_commands.json`: a generated list of compiler commands, including the
header paths and options for each source file. Follow the project's own setup
instructions first. For a typical CMake project, run these from its root:

```sh
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Debug \
  -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
cmake --build build
ctest --test-dir build --output-on-failure
```

clangd searches parent directories and their `build/` subdirectory for the
database. If your build directory has another name, point to it with the
project's `.clangd` file:

```yaml
CompileFlags:
  CompilationDatabase: build/debug
```

The project chooses the compiler, C/C++ standard, dependencies, and test targets.
Refresh its build settings when these change, and build targets that generate
headers before expecting navigation into those headers. For other build systems,
use their compilation-database export instructions; simple projects can use
`compile_flags.txt`. clangd guesses when neither exists, which is often
insufficient for large repositories. `.clangd` and `.clang-tidy` control analysis;
there is no second C/C++ lint runner.

**Format with `<leader>f`.** Conform runs clang-format using the source file's
nearest `.clang-format` or `_clang-format`. C/C++ formatting on save stays off.
Mason supplies the default executable. When a project requires a particular
version, install that version through the project's workflow, then select it for
the buffer with an absolute executable path:

```vim
:let b:clang_format = '/absolute/path/to/project/formatter/bin/clang-format'
```

This also applies to selection formatting. An unavailable explicit executable
reports an error instead of silently using another version. A style file does
not select a formatter version. For repeated use, set this buffer variable from
your own `FileType` autocommand with a project-path condition; the shared adapter
contains no project-specific paths or version guesses.

**Debug with the existing controls.** Build an executable with debug information,
open its source, set a breakpoint with `<leader>b`, then press `F5` and choose
**Launch executable** or **Attach to process**. Attach is subject to operating
system permissions. Project launch settings replace these generic choices; put
non-trivial arguments, environment, or input handling in `.vscode/launch.json`:

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "Debug app",
      "type": "lldb",
      "request": "launch",
      "program": "${workspaceFolder}/build/app",
      "cwd": "${workspaceFolder}",
      "args": ["--example", "two words"],
      "env": { "APP_MODE": "development" }
    }
  ]
}
```

Both CodeLLDB's VS Code name `lldb` and nvim-dap's `codelldb` are accepted here.
These are CodeLLDB settings, not the separate `lldb-dap` adapter's schema.
For redirected standard input, CodeLLDB also accepts
`"stdio": ["${workspaceFolder}/input.txt", null, null]`. VS Code extension
commands and `preLaunchTask` are not run by this setup; build in the terminal.
The source buffer selects the project, so another tab's working directory does
not redirect the launch. A nearer launch file wins within a Git checkout;
otherwise compiler metadata or the checkout root is used.

Build/test tools remain terminal commands. Use the project's documented
AddressSanitizer/UndefinedBehaviorSanitizer or coverage build options when needed;
these are separate build configurations, not editor switches. For a small project,
`-g -O0` is a useful debug baseline, while sanitizer builds commonly add
`-fsanitize=address,undefined -fno-omit-frame-pointer` at compilation and linking.
Support depends on the compiler and target.

For troubleshooting, use `:checkhealth vim.lsp`, `:ConformInfo`, and `:Mason`.
Run `clangd --check=path/to/source.cpp` using the Mason executable
(`:lua print(vim.fn.exepath('clangd'))`) to inspect which compilation command was
selected. Missing headers usually mean missing/stale build settings or generated
files. Native macOS is exercised locally; Linux bootstrap is fixture-tested.
Mason's current clangd package does not cover Linux ARM64, so that platform needs
a separately verified clangd installation before claiming the same support.

#### DuckDB example

From the DuckDB checkout, prepare navigation once using its existing target:

```sh
CMAKE_GENERATOR='Unix Makefiles' make clangd \
  EXTRA_CMAKE_VARIABLES='-DDISABLE_UNITY=ON'
```

Its `.clangd` already points to `.cache/clangd/compile_commands.json`. This
configures the project without compiling DuckDB. Disabling its unity build keeps
individual source-file commands available; later builds may replace the database,
so keep them non-unity or repeat this command. Opening a file then starts code
navigation without another setup command.

DuckDB currently requires clang-format 11.0.1. Run `make format_venv` to provision
its formatter, then set `b:clang_format` to the absolute path of
`.cache/format-venv/bin/clang-format` in that checkout before formatting a buffer.
The pinned 11.0.1 executable currently hangs on this machine even outside Neovim;
DuckDB formatting is therefore not locally verified. The shared Mason formatter
passes, but should not be substituted silently for DuckDB's required version.
Use DuckDB's own build/test instructions to produce a debug executable; the
navigation-only command above does not build one.

## Clipboard

Use `pbcopy`/`pbpaste` on macOS or a working Wayland/X11 clipboard provider on
Linux. A remote session inside tmux explicitly uses its clipboard provider,
including on macOS. A remote session with no display and no tmux falls back to OSC 52 so the
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

Lazygit and Hunk open files through the shell-owned `EDITOR=nvim` contract.
flatten.nvim routes nested Neovim calls back into the host editor and hides the
originating Git surface. Start a review from the intended checkout so pressing
`e` opens in that review's Neovim with normal project-root discovery and full
language tooling using the checkout's project and build context.

To open an aggregate commit review, resolve the base and head to full commit
object IDs, then launch this Neovim configuration from the checkout root:

```sh
env HUNK_REVIEW_BASE_OID='<full-base-oid>' \
  HUNK_REVIEW_HEAD_OID='<full-head-oid>' nvim +HunkReview
```

Replace both placeholders with lowercase hexadecimal IDs of the same length
(40 for SHA-1 or 64 for SHA-256). Both variables must be supplied together;
malformed or incomplete context stops Hunk's declaration before registration.
This configuration validates their format; the caller owns commit resolution
and review-base selection. `:HunkReview` and `<leader>gd` share one toggle for
`hunk diff BASE...HEAD --watch --mode stack`. Without either variable,
`<leader>gd` reviews the working tree and `:HunkReview` is not registered.
`<leader>gD` continues to select staged changes in either context.

Each terminal tool uses a persistent Tool Tab. LazyGit restarts in its existing
tab when the working directory changes; Hunk keeps an instance per canonical
Git checkout root. Subdirectories and aliases share that instance; different
repositories and worktrees remain live independently. Working-tree and
staged review share the same Hunk tab and process: choosing the other input
retargets that review, and invoking its active toggle returns to the Host
Window. Choosing another input while viewing a Hunk tab retargets that tab's
checkout. Jobs stop when Neovim exits. Ordinary unsaved splits are preserved
if they prevent a finished tool's tab from closing safely.

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

If macOS stalls while starting or attaching to a native process, try Apple LLDB
from a visible terminal and check for a Developer Tools authorization prompt.
Local C/C++ acceptance reached CodeLLDB initialization and breakpoint setup, but
both CodeLLDB and Apple LLDB stalled at macOS process access; breakpoint hits,
variables, and stepping are not yet verified on this host. See the
[runtime findings](../docs/c-cpp-support-research.md#implementation-status).

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
