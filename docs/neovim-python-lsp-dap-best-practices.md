# Python LSP and DAP best practices for Neovim

Status: implementation guidance

Evidence checked: 2026-08-16

Scope: the approved Python slice in this repository: BasedPyright, Ruff's
native language server, Conform, Mason-managed debugpy, and nvim-dap-python.
This document uses upstream tool documentation and source only.

## Decision

Use two complementary native LSP clients and one formatting path:

| Concern | Owner | Reason |
| --- | --- | --- |
| Semantic analysis, navigation, completion, rename, type diagnostics, inlay hints | `basedpyright` | BasedPyright is the sole Python semantic/type client. Do not disable its language services. |
| Lint diagnostics and Ruff quick fixes/source actions | `ruff server` | Ruff's native Rust LSP supersedes the separate `ruff-lsp` package. |
| Fixes, formatting, import sorting on save and `<leader>f` | Conform: `ruff_fix`, `ruff_format`, `ruff_organize_imports` | One deterministic mutation path; this is Ruff's documented Conform sequence. |
| Debug adapter process | Mason `debugpy`, registered by `nvim-dap-python` | The adapter may use an environment independent of the debug target. Mason remains the editor-tool owner. |
| Debug target interpreter | Project-derived interpreter | The target must use the project environment and dependencies, rather than the adapter's isolated debugpy environment. |

This does not replace mypy in projects whose CI uses mypy. BasedPyright reads
its own project configuration and reports its own diagnostic model; it neither
runs mypy nor consumes mypy configuration/plugins. Keep the repository's CI
type-checker authoritative unless that project intentionally migrates it.

## Native LSP configuration

Neovim 0.12 should use `vim.lsp.config()` and `vim.lsp.enable()`; this is the
current native LSP mechanism and is the exact setup documented by Ruff for
Neovim 0.11+. Continue using nvim-lspconfig only as the source of server
defaults, as this configuration already does. [Neovim LSP configuration](https://neovim.io/doc/user/lsp.html), [Ruff's Neovim setup](https://docs.astral.sh/ruff/editors/setup/)

Enable both `basedpyright` and `ruff` for Python buffers. Upstream
nvim-lspconfig defines BasedPyright as `basedpyright-langserver --stdio` with
the following useful roots: `pyrightconfig.json`, `pyproject.toml`,
`setup.py`, `setup.cfg`, `requirements.txt`, `Pipfile`, and `.git`.
[BasedPyright nvim-lspconfig definition](https://raw.githubusercontent.com/neovim/nvim-lspconfig/master/lsp/basedpyright.lua)

Ruff's upstream Neovim definition is `ruff server` and its roots are
`pyproject.toml`, `ruff.toml`, `.ruff.toml`, and `.git`. Its root may be
nearer than the semantic project root, which is appropriate: Ruff must load
the lint configuration that governs a file but should not dictate
BasedPyright's workspace. [Ruff's nvim-lspconfig definition](https://raw.githubusercontent.com/neovim/nvim-lspconfig/master/lsp/ruff.lua)

### Project configuration and interpreter policy

BasedPyright accepts `pyrightconfig.json`, `[tool.basedpyright]` in
`pyproject.toml`, and `[tool.pyright]` for compatibility. A
`pyrightconfig.json` takes precedence over `pyproject.toml`; all relative paths
are relative to the configuration file. Its `executionEnvironments` are
ordered, and the first matching environment supplies the settings for a source
file. [BasedPyright configuration files](https://docs.basedpyright.com/latest/configuration/config-files/)

Therefore the dotfiles must not impose a global `pythonPath`, `venvPath`,
`extraPaths`, `executionEnvironments`, `typeCheckingMode`, or
`useLibraryCodeForTypes`. These would override or conflict with an individual
repository's import model. BasedPyright documents `python.venvPath` as
discouraged and recommends an explicit `python.pythonPath` only when an editor
must select an interpreter; it also defaults semantic analysis to its
`recommended` rule set. [BasedPyright language-server settings](https://docs.basedpyright.com/latest/configuration/language-server-settings/)

The global configuration should set
`basedpyright.disableOrganizeImports = true`, because Conform/Ruff is the one
import organizer, and explicitly select workspace push diagnostics with
`basedpyright.analysis.diagnosticMode = "workspace"` plus
`init_options.disablePullDiagnostics = true`. This preserves immediate
cross-file feedback while avoiding a work-done progress cycle for every edit
under Neovim 0.12. Repositories should bound large workspaces through committed
include/exclude and execution-environment configuration. Leave language
services and auto-import completions enabled. [BasedPyright language-server
settings](https://docs.basedpyright.com/latest/configuration/language-server-settings/),
[BasedPyright progress research](neovim-basedpyright-fidget-progress-research.md)

For DAP launch targets, use a small, testable project resolver rather than
Neovim's process CWD:

1. locate the Python semantic root from `pyrightconfig.json` or
   `pyproject.toml`, then `setup.py`, `setup.cfg`, `requirements.txt`,
   `Pipfile`, and finally `.git`;
2. prefer an explicitly active `VIRTUAL_ENV` or `CONDA_PREFIX` only when it
   belongs to that root, then that root's `.venv`, `venv`, `.env`, or `env`;
3. finally use the visible Mise `python3` fallback.

The resolver must return an executable only after checking it exists. It must
not change global CWD, parse project dependency metadata, or guess that an
unrelated active virtualenv belongs to the current project. This mirrors the
documented nvim-dap-python candidates while making the repository's
buffer-derived project boundary authoritative. [nvim-dap-python virtualenv
resolution](https://github.com/mfussenegger/nvim-dap-python#python-dependencies-and-virtualenv)

## Preventing overlapping capabilities

Remove Python's `ruff` entry from nvim-lint. Otherwise the Ruff CLI and Ruff
LSP publish the same lint diagnostics through independent channels.

Keep the existing Conform sequence exactly as documented by Ruff:

```lua
python = { 'ruff_fix', 'ruff_format', 'ruff_organize_imports' }
```

Disable Ruff's document and range formatting capabilities in its `on_attach`;
Conform remains the only formatting owner. Also disable Ruff hover, retaining
BasedPyright's semantic hover. Ruff's own Neovim guide gives this exact
capability-routing pattern when Ruff runs alongside Pyright. [Ruff setup and
capability routing](https://docs.astral.sh/ruff/editors/setup/)

Do not suppress all BasedPyright analysis merely because Ruff is attached.
Ruff's documented option for a Ruff-only setup disables Pyright analysis; that
is incompatible with the goal of high-fidelity semantic/type editing.

## Debugging

Mason should install `basedpyright`, `ruff`, and `debugpy`; they are editor
tools, while Mise continues to supply the Python runtime. Mason installs
packages in Neovim's data directory and prepends its executable directory to
Neovim's PATH. [Mason documentation](https://github.com/mason-org/mason.nvim),
[Mason debugpy package](https://raw.githubusercontent.com/mason-org/mason-registry/main/packages/debugpy/package.yaml)

Load nvim-dap-python only for Python debug actions and pass it Mason's absolute
`debugpy-adapter` executable (or the Mason debugpy Python executable) to
`setup`. This avoids `setup('uv')`, which dynamically obtains debugpy at debug
time and violates the repository's Mason ownership boundary. nvim-dap-python
documents `debugpy-adapter` as a supported setup target, and its setup both
registers the Python adapter and its ordinary file/arguments/attach defaults.
[nvim-dap-python usage](https://github.com/mfussenegger/nvim-dap-python#usage)

Override nvim-dap-python's `resolve_python` with the project resolver above.
This preserves the important distinction between the adapter environment
(Mason's debugpy) and debuggee environment (the project venv). `pythonPath` in
a project `.vscode/launch.json` remains authoritative, and the existing
root-aware DAP provider must continue to resolve that file from the buffer's
project root.

nvim-dap-python supplies nearest test method and class actions and detects
`pytest`, `unittest`, and Django. Test targeting requires the Python
Tree-sitter parser, which this repository already installs. Do not add
Python-specific keymaps: expose those backend actions as commands until the
cross-language target-selection interface is implemented. [nvim-dap-python
test support](https://github.com/mfussenegger/nvim-dap-python#usage)

## Concrete implementation plan

1. Replace generic `pyright` with `basedpyright` in the declarative language
   inventory; add `ruff` beside it. Replace Mason `pyright` with
   `basedpyright`, retain `ruff`, and add `debugpy`.
2. Keep Python's Conform mapping, remove only Python's nvim-lint mapping, and
   add shared capability hooks: BasedPyright disables organize-imports; Ruff
   disables hover and formatting. Do not add global type-analysis or
   interpreter settings.
3. Expand `adapters/python.lua` into the Python-specific integration boundary.
   It should own the Python DAP registration, root profile, interpreter
   resolver, Mason debugpy location, lazy nvim-dap-python setup, and Python
   DAP project declaration. The shared DAP module stays language-neutral.
4. Configure nvim-dap-python with Mason's adapter, set its project interpreter
   resolver, retain default `launch`/`attach` configurations, and register the
   existing root-aware `launch.json` provider for `type = 'python'`.
5. Update the Neovim and dependency documentation to describe semantic,
   lint/action, formatting, adapter, and debug-target ownership separately.

## Verification plan

- Update the inventory spec to assert BasedPyright, Ruff, and debugpy Mason
  packages; assert Pyright and Python nvim-lint Ruff are absent; assert the
  Conform sequence remains unchanged.
- Add focused Python-adapter tests that stub Mason, nvim-dap-python, project
  context, and virtualenv paths. Verify lazy loading, the absolute Mason
  adapter, a Python-only DAP registration, root selection, `.venv` preference,
  safe activated-environment handling, and Mise fallback.
- Assert capability ownership directly: BasedPyright cannot organize imports;
  Ruff cannot provide hover, document formatting, or range formatting.
- Run all headless specs, `stylua --check` on changed Lua, `git diff --check`,
  and regenerate Neovim help tags after documentation changes.
- Smoke-test a temporary `pyproject.toml` project with a `.venv`: inspect both
  attached clients, completion/hover/code actions, save formatting/import
  sorting, a normal file launch, a debugpy attach, and nearest pytest plus
  unittest test target construction. Also open two same-named worktrees to
  prove roots and launch files remain isolated.
