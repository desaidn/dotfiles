# Neovim project-context best practices

Checked 2026-08-15 against Neovim 0.12-era upstream documentation, nvim-dap,
nvim-jdtls, and Eclipse JDT.LS. This reviews the proposed cross-project
context seam only; it makes no configuration change.

## Conclusion

The proposed direction is sound: derive context from the active buffer without
changing Nvim's process working directory, use Nvim's native root discovery,
and pass an explicit per-project directory to JDTLS. Two details should change
before implementation:

1. A context result must be **consumer/profile-specific**, not one cached
   `root`/`kind` per buffer. A Rust project nested in a Git monorepo and a
   Java project in the same tree legitimately have different roots.
2. A root-aware nvim-dap launch provider must also substitute
   `${workspaceFolder}` and `${workspaceFolderBasename}` from that root. Merely
   loading the correct `launch.json` still leaves nvim-dap's built-in
   substitutions tied to `getcwd()`.

## Native root and LSP semantics

Use `vim.fs.root(bufnr, markers)` as the low-level root operation. It accepts a
buffer or path; preserves ordered marker priority; supports equal-priority
marker groups with nested lists; and returns the directory containing the first
matching marker. [Neovim `vim.fs.root()` documentation](https://raw.githubusercontent.com/neovim/neovim/master/runtime/doc/lua.txt)

This is also the root-selection model Nvim's native LSP configuration uses:
`root_markers` are searched upward from the buffer in marker-priority order,
and the selected directory becomes the LSP workspace root. A `root_dir`
function may decide dynamically, per buffer, whether to start a client; Nvim's
default client reuse key includes client name and `root_dir`. [Neovim LSP
configuration](https://raw.githubusercontent.com/neovim/neovim/master/runtime/doc/lsp.txt)

Therefore, define profiles close to the consuming language adapter, then share
the mechanics:

```lua
-- illustrative shape, not a proposed implementation
context.root(bufnr, { 'Cargo.toml', 'rust-project.json', '.git' })
context.root(bufnr, { 'pyproject.toml', 'uv.lock', '.git' })
context.root(bufnr, { { 'pom.xml', 'build.gradle', 'build.gradle.kts' }, '.git' })
```

The nested Java group is intentional: Maven/Gradle markers at the same nearest
directory should have equal priority, with the VCS root only as fallback.
Keep the marker lists identical to each relevant LSP client's `root_markers`
or `root_dir` policy. The context module should not override LSP roots or
invent a universal `.git` root.

Nvim explicitly documents that an LSP workspace root does **not** change the
Nvim current directory. That is desirable here: changing global CWD to follow
the current buffer would make `:make`, terminal commands, and another
project's active window unpredictable. [Neovim LSP working-directory
documentation](https://raw.githubusercontent.com/neovim/neovim/master/runtime/doc/lsp.txt)

### Buffer and cache rules

`vim.fs.root()` starts unnamed or special buffers from current CWD. Do not use
that fallback as project context: return `nil` for unnamed/non-file buffers and
make a target/debug action report that it needs a saved project file. This
avoids silently assigning a scratch buffer to whichever tab or process CWD is
active. [Neovim `vim.fs.root()` documentation](https://raw.githubusercontent.com/neovim/neovim/master/runtime/doc/lua.txt)

Root lookup is an upward marker search, so begin without a persistent cache.
If profiling later justifies caching, key it by **canonical buffer path plus an
immutable marker-profile identity**, not only by buffer number/path, and
invalidate on `BufFilePost`, `BufWipeout`, and explicit context reset. Marker
files can appear, disappear, or be renamed outside Nvim, which cannot be made
correct with a buffer-change invalidation alone. Do not add directory watchers
for every project merely to optimize this small traversal: Nvim documents the
resource cost and platform limits of filesystem watches. [Neovim filesystem
watch guidance](https://raw.githubusercontent.com/neovim/neovim/master/runtime/doc/lua.txt)

Normalize paths for comparison, but do not resolve symlinks by default: a
worktree accessed through a symlink may intentionally be a separate user-facing
workspace. If a specific persistent cache needs physical-path identity, state
that policy explicitly and use `vim.uv.fs_realpath()` only for that cache key.
Nvim distinguishes path normalization from resolving links. [Neovim filesystem
path documentation](https://raw.githubusercontent.com/neovim/neovim/master/runtime/doc/lua.txt)

## DAP and VS Code launch configurations

nvim-dap already has a configuration-provider extension point. Providers are
called with the current buffer number when `dap.continue()` selects a
configuration; a provider returns a list of configurations. The documented
extension model supports adding a provider under the owning plugin/module name,
while the `dap.` namespace is reserved. [nvim-dap providers
documentation](https://raw.githubusercontent.com/mfussenegger/nvim-dap/master/doc/dap.txt)

The built-in `dap.launch.json` provider calls `dap.ext.vscode.getconfigs()`
without a path. That function defaults to
`getcwd()/.vscode/launch.json`. nvim-dap's built-in values for
`${workspaceFolder}` and `${workspaceFolderBasename}` also call `getcwd()`.
[nvim-dap provider source](https://raw.githubusercontent.com/mfussenegger/nvim-dap/master/lua/dap.lua)
[nvim-dap VS Code extension source](https://raw.githubusercontent.com/mfussenegger/nvim-dap/master/lua/dap/ext/vscode.lua)

Recommended implementation shape:

1. Replace only the built-in `dap.providers.configs['dap.launch.json']` entry
   with a repository-owned, root-aware equivalent; retain `dap.global`.
2. Resolve the active buffer's project root through the applicable context
   profile and call `require('dap.ext.vscode').getconfigs(explicit_path)` for
   `<root>/.vscode/launch.json`.
3. Deep-copy each returned configuration and recursively replace
   `${workspaceFolder}` and `${workspaceFolderBasename}` with the resolved
   root and its basename **before** nvim-dap's own expansion runs. Leave
   `${file}`, `${env:...}`, and supported `${input:...}` behavior to nvim-dap.
4. Filter/route configurations by an explicit adapter-type-to-filetype table
   owned by the corresponding language adapters, so unrelated launch types do
   not appear for the current buffer.

Do not use the deprecated `load_launchjs()` workaround: upstream says launch
files are read on demand through providers. [nvim-dap VS Code extension
source](https://raw.githubusercontent.com/mfussenegger/nvim-dap/master/lua/dap/ext/vscode.lua)

Do not solve workspace substitution by changing global or tab-local CWD around
debug selection. Aside from cross-window interference, nvim-dap evaluates
configurations asynchronously/coroutine-based. [nvim-dap providers
documentation](https://raw.githubusercontent.com/mfussenegger/nvim-dap/master/doc/dap.txt)

The launch-file reader is intentionally a subset of VS Code's format. It
supports standard JSON by default; trailing commas fail unless a JSON5 decoder
is installed. Treat unsupported VS Code variables or multi-root
`${workspaceFolder:name}` as an actionable warning, not a reason to guess a
root. [nvim-dap `launch.json` documentation](https://raw.githubusercontent.com/mfussenegger/nvim-dap/master/doc/dap.txt)

## JDTLS workspace data

JDTLS `-data` is its workspace/index data location and upstream requires it to
be unique per workspace/project. The server's command-line documentation calls
for an absolute path and says it stores workspace-specific information there.
[Eclipse JDT.LS command-line documentation](https://github.com/eclipse-jdtls/eclipse.jdt.ls#running-from-the-command-line)

nvim-jdtls likewise recommends explicitly setting `-data`; otherwise the
default lives below the temporary directory and its name derives from CWD,
which means cold re-indexing after a temp-directory cleanup and potential
cross-project ambiguity. Its ftplugin example independently derives
`root_dir` with `vim.fs.root()`. [nvim-jdtls configuration and data-directory
documentation](https://github.com/mfussenegger/nvim-jdtls#data-directory-configuration)

Use a durable XDG cache/state path plus a collision-resistant identity derived
from the resolved Java root, for example:

```text
stdpath('cache')/jdtls/<readable-project-name>-<stable-short-hash>
```

On Neovim 0.12, implement the stable short hash locally (or use a safe encoded
identity); do not use `vim.fs.slug()`, which is documented as new in 0.13.
[Neovim `vim.fs.slug()` documentation](https://raw.githubusercontent.com/neovim/neovim/master/runtime/doc/lua.txt)

Pass that exact directory in JDTLS's `cmd` as `'-data', workspace_dir`, and
build it from the Java root—not CWD or just a basename. Reuse is correct only
when both the JDTLS root and this data-directory identity match. nvim-jdtls
also warns not to enable the generic `jdtls` LSP path when using its ftplugin
`start_or_attach` lifecycle. [nvim-jdtls configuration
documentation](https://github.com/mfussenegger/nvim-jdtls#via-ftplugin)

## Validation matrix

Before adding any language backend, tests should cover:

- two nested package roots open simultaneously: each context/LSP/DAP lookup
  returns its own root and no test observes a changed global CWD;
- a marker-priority fixture: nearest language marker wins before `.git`, and
  equal-priority marker groups behave as intended;
- unnamed and special buffers: no accidental CWD-derived context;
- two roots with the same basename: their JDTLS data paths differ and remain
  stable on a second lookup;
- explicit per-root `launch.json`: the selected configuration comes from the
  active buffer's root and embedded workspace placeholders use that same root;
- `launch.json` mutation: fresh debug selection reads the changed file (do not
  cache launch configurations unless invalidation is designed and tested).

## Recommended refined public seam

Keep the interface small and profile-based:

```lua
-- `profile` belongs to the caller/language adapter.
context.for_buffer(bufnr, profile)
-- { root = absolute_path, path = absolute_buffer_path }

context.workspace_data('jdtls', root)
-- durable, collision-resistant per-root directory
```

The DAP provider constructs and checks `<root>/.vscode/launch.json`; context
does not know that DAP-specific convention. `targets.lua` can later consume
`context.for_buffer()` without making context know how Rust, Python, Java, or
TypeScript discover targets. This preserves the desired common user interface
while keeping root semantics and target discovery with their respective adapters.
