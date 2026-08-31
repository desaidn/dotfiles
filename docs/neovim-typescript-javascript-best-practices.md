# TypeScript and JavaScript LSP/DAP best practices for Neovim

Status: implemented; automated browser/source-map verification remains follow-up

Evidence checked: 2026-08-24

Implemented: 2026-08-23

Scope: the TypeScript/JavaScript vertical slice proposed after Python support in
this repository. This document compares the repository's pinned code and
existing research with current upstream TypeScript, Neovim, ESLint, Mason,
nvim-dap, and js-debug contracts. External claims use primary sources.

## Decision

Implement one mutually exclusive TypeScript semantic router, retain the existing
diagnostic and formatting owners, and leave the ESLint LSP migration
conditional:

| Concern | Decision | Owner |
| --- | --- | --- |
| JS/TS semantic LSP | Route a recognized non-Deno root by its project-local TypeScript version: 7+ uses native `tsc --lsp --stdio`; earlier versions with a root-local `typescript/lib/tsserver.js` use `ts_ls`. | The project owns TypeScript semantics and compiler; Neovim selects exactly one client. |
| Pre-TypeScript-7 compatibility | Install Mason's `typescript-language-server` only as transport and initialize it with the exact project's `node_modules/typescript/lib/tsserver.js`. | Mason owns the wrapper transport; the project owns the language service. |
| ESLint diagnostics | Retain the working `nvim-lint` + `eslint_d` integration for now. | Mason owns `eslint_d`; the project owns ESLint and its config/plugins. |
| Formatting | Keep Prettier/Prettierd through Conform as the only save formatter. | Conform owns buffer mutation. |
| Node/browser debugging | Add Mason's `js-debug-adapter` directly through nvim-dap; do not add a wrapper plugin. Send js-debug's canonical `pwa-*` types on the wire. | Mason owns the adapter; the project owns runtime and launch details. |
| Launch configuration | Keep using the existing buffer-rooted, on-demand `.vscode/launch.json` provider. | Each project owns non-trivial launch and attach recipes. |

This corrects two recommendations in
[`lsp-dap-research.md`](lsp-dap-research.md): its nvim-lspconfig prerequisite
is stale because the pinned revision already contains `lsp/tsc.lua`, and an
ESLint LSP migration is not justified while Mason still packages the old
third-party extraction. Removing `nvim-lint` is therefore conditional, not
part of the initial slice.

## TypeScript 7 is the correct native route

TypeScript 7 is stable and its `tsc` executable contains the native language
server. Microsoft explicitly documents `tsc --lsp --stdio`, editor support
through standard LSP, and the completed editor features expected for normal
JavaScript and TypeScript work. This replaces the TypeScript 6 tsserver bridge
as the ordinary default. [TypeScript 7 announcement](https://devblogs.microsoft.com/typescript/announcing-typescript-7-0/)

The compiler must remain a project dependency. That keeps editor analysis,
command-line builds, CI, and each repository's migration schedule on the same
TypeScript release. Do not add Mason's new `tsc` package to the global editor
inventory: although Mason now distributes TypeScript 7.0.2 as both a compiler
and LSP, doing so would create a second compiler owner and permit the editor to
analyze a project with a version the project does not declare. [Mason `tsc`
recipe](https://github.com/mason-org/mason-registry/blob/main/packages/tsc/package.yaml)

The current upstream nvim-lspconfig `tsc` definition verifies that a candidate
is TypeScript 7 or newer, prefers a root-local executable, starts one server at
the workspace root, routes nested `tsconfig.json`/`jsconfig.json` projects
inside that server, and excludes nearer Deno roots. One server per workspace is
the intended monorepo shape; one client per TSConfig would waste resources and
fight TypeScript's own project routing. [nvim-lspconfig `tsc`
definition](https://github.com/neovim/nvim-lspconfig/blob/master/lsp/tsc.lua),
[TypeScript project routing](https://github.com/microsoft/typescript-go/blob/main/internal/project/projectcollection.go)

### Repository hardening

The repository now pins nvim-lspconfig at `221c438`, whose `tsc` definition
contains upstream's TypeScript-major guard and current `js/ts` settings. The
previous `51dbf535` revision had the initial server definition but not those
corrections. The lock refresh is intentionally limited to nvim-lspconfig and
is covered by the full Neovim regression suite.

Even current upstream deliberately permits PATH and CWD fallbacks. Those are
reasonable general-purpose defaults but conflict with this repository's
project-owned compiler and buffer-derived-root policies. The local
configuration should therefore narrow, not recreate, upstream behavior:

1. require a named JS/TS buffer under a recognized package-manager or Git
   root;
2. suppress attachment when a nearer/equal Deno root owns the file;
3. require that root's `node_modules/.bin/tsc` and parse its version;
4. for TypeScript 7+, start that exact executable with `--lsp --stdio`;
5. for an earlier version, additionally require
   `node_modules/typescript/lib/tsserver.js`, then start Mason's
   `typescript-language-server` transport with that exact path in
   `initializationOptions.tsserver.path`;
6. attach neither client for a missing/unparseable compiler, a pre-7 project
   without that language-service file, an unowned buffer, or a Deno root;
7. accept the compatibility server only when its `$/typescriptVersion`
   notification reports the expected version from `user-setting`; terminate it
   if the configured path fell through to workspace or bundled TypeScript;
8. never fall back to process CWD, PATH, or a wrapper-bundled TypeScript, and
   let exactly one root client own all nested TSConfig/JSConfig projects.

The resolved project version and paths are cached for the Neovim session.
Restart Neovim after installing, removing, or changing that project's
TypeScript version so routing is recalculated. Until restart, the notification
guard makes a stale compatibility route fail closed instead of accepting a
different language service.

Project `tsconfig.json` files must continue to own Node-versus-browser module
resolution, libraries, types, paths, JSX, emit, and strictness. TypeScript's
official module guidance distinguishes `nodenext` for modern Node projects and
`bundler` for bundler-owned resolution; dotfiles should not impose either
globally. [TypeScript module reference](https://www.typescriptlang.org/docs/handbook/modules/reference.html)

## Pre-TypeScript-7 is a compatibility lane, not a second default

TypeScript 7.0 intentionally has no stable programmatic compiler/language-
service API. Microsoft identifies Vue, MDX, Astro, Svelte, Angular template
tooling, and language-service plugins as workflows that may still require
TypeScript 6 editor support. It provides `@typescript/typescript6`/`tsc6` and
npm-alias guidance for running 6 and 7 side by side. [TypeScript 7 embedded
languages and side-by-side guidance](https://devblogs.microsoft.com/typescript/announcing-typescript-7-0/#typescript-and-embedded-languages)

That does not justify attaching both `tsc` and `ts_ls` to every TypeScript
buffer or guessing from framework-looking files. Duplicate semantic clients
would overlap diagnostics, navigation, completion, rename, and imports. The
real compatibility requirement is simpler and testable: a recognized project
whose local TypeScript major is below 7 routes only to `ts_ls`, and only when
that same root supplies `typescript/lib/tsserver.js`; TypeScript 7+ routes only
to native `tsc`.

The `desaidn.dev` pnpm workspace demonstrated why this lane is necessary. Its
root-local TypeScript 5.9.3 and `tsserver.js` were valid, but removing `ts_ls`
left `packages/assets/app/components/common/AppLayout.tsx` with no semantic
client. The compatibility route restores that project without weakening the
TypeScript 7 default or adding a global compiler.

Mason therefore keeps `typescript-language-server` in the editor inventory,
but it owns only the transport executable. Its bundled TypeScript is not the
semantic fallback: initialization explicitly selects the root-local
`node_modules/typescript/lib/tsserver.js`, following the server's documented
`initializationOptions.tsserver.path` contract. Because that server otherwise
falls through after an invalid configured path, Neovim also terminates the
client unless `$/typescriptVersion` reports the expected project version with
source `user-setting`. [Mason TypeScript language
server recipe](https://github.com/mason-org/mason-registry/blob/main/packages/typescript-language-server/package.yaml),
[typescript-language-server configuration](https://github.com/typescript-language-server/typescript-language-server/blob/master/docs/configuration.md)

## Retain eslint_d until the LSP distribution passes a gate

The architectural case for an ESLint LSP is valid: one long-lived server can
publish diagnostics and code actions, choose a per-document working directory
in a monorepo, and use the project's local ESLint. Microsoft's current server
supports flat config and current ESLint behavior, and nvim-lspconfig supplies
monorepo root selection plus `workingDirectory = { mode = "auto" }`.
[Microsoft vscode-eslint](https://github.com/microsoft/vscode-eslint),
[nvim-lspconfig `eslint`](https://github.com/neovim/nvim-lspconfig/blob/master/lsp/eslint.lua)

The available Mason package is the blocker. Its `eslint-lsp` recipe still
installs `vscode-langservers-extracted@4.10.0`, a third-party extraction
published in 2024, rather than the current Microsoft server. Microsoft is now
at stable release 3.0.34 and its current source includes later ESLint 10 and
flat-config work. Version numbers between the projects are not comparable, but
their publication age and source lineage are: behavior from current
`microsoft/vscode-eslint` cannot be assumed present in the extracted package.
[Mason ESLint LSP recipe](https://github.com/mason-org/mason-registry/blob/main/packages/eslint-lsp/package.yaml),
[`vscode-langservers-extracted` releases](https://github.com/hrsh7th/vscode-langservers-extracted/releases),
[Microsoft vscode-eslint releases](https://github.com/microsoft/vscode-eslint/releases)

The current repository path is supported and maintained: `eslint_d` supports
ESLint 4 through 10 and current Node LTS versions, loads the project's ESLint,
and documents nvim-lint integration. The local adapter already passes the
nearest ESLint-config directory as `cwd`, solving the project-root problem
without changing Neovim's global CWD. [eslint_d](https://github.com/mantoni/eslint_d.js),
[`neovim-eslint-project-root-research.md`](neovim-eslint-project-root-research.md)

Adopt the ESLint LSP later only if its exact Mason artifact passes fixtures for
ESLint 8.57 legacy/flat selection, ESLint 9, ESLint 10, package-local configs in
a monorepo, typed linting, ignored files, and fix-all code actions. Switch
diagnostic ownership atomically; never run `eslint_d` and ESLint LSP for the
same filetypes.

If that gate passes, disable ESLint formatting with
`settings.format = false`. Do not replace nvim-lspconfig's `on_attach` with the
repository's generic formatting-disabler: native `vim.lsp.config()` uses a
force deep merge, so replacing the function would silently discard upstream's
buffer-local `:LspEslintFixAll` command. [Neovim LSP config merge](https://github.com/neovim/neovim/blob/master/runtime/lua/vim/lsp.lua),
[nvim-lspconfig ESLint `on_attach`](https://github.com/neovim/nvim-lspconfig/blob/master/lsp/eslint.lua)

## Use js-debug directly

Microsoft describes js-debug as a standalone DAP server usable by Neovim. It
supports Node, Chrome, Edge, workers/child processes, and source maps. Mason's
current recipe packages the official v1.117.0 standalone server and exposes a
`js-debug-adapter` shim, so no `nvim-dap-vscode-js` wrapper is needed.
[Microsoft js-debug](https://github.com/microsoft/vscode-js-debug),
[Mason js-debug recipe](https://github.com/mason-org/mason-registry/blob/main/packages/js-debug-adapter/package.yaml)

Register a native nvim-dap server adapter with `host = "127.0.0.1"`,
`port = "${port}"`, executable `vim.fn.exepath("js-debug-adapter")`, and
arguments `"${port}"`, `"127.0.0.1"`. The explicit matching host avoids a
localhost/IPv4 mismatch; nvim-dap owns free-port allocation and process
lifecycle for this adapter shape.
[nvim-dap adapter contract](https://github.com/mfussenegger/nvim-dap/blob/master/doc/dap.txt)

The supported repository baseline is macOS and Linux, where Mason exposes an
executable shim. Mason exposes a `.cmd` wrapper on native Windows, while
nvim-dap starts server executables through libuv; that path needs a live
Windows smoke test or an explicit Node-script launcher before Windows js-debug
support is claimed.

The standalone server's canonical debug types are `pwa-node`, `pwa-chrome`,
and `pwa-msedge`. VS Code accepts the public `node`, `chrome`, and `msedge`
names because its extension translates them before the DAP request; merely
registering those names as extra nvim-dap adapter keys does not translate the
`config.type` sent to the standalone server. The implementation preserves
launch-file interoperability by normalizing public aliases to their canonical
`pwa-*` type in the existing launch provider; adapter aliases apply the same
normalization to direct nvim-dap configurations, and the built-in Node default
is `pwa-node`. Focused tests prove normalization and adapter lookup; a live smoke
with Mason's installed artifact also initialized and completed a public `node`
configuration after normalization to `pwa-node`. A durable real-adapter fixture
is still desirable. Do not
advertise VS Code-specific terminal/extension-host
integrations as generic Neovim features. [js-debug type
mappings](https://github.com/microsoft/vscode-js-debug/blob/main/src/common/contributionUtils.ts),
[js-debug configuration dispatch](https://github.com/microsoft/vscode-js-debug/blob/main/src/configuration.ts),
[nvim-dap adapter lookup](https://github.com/mfussenegger/nvim-dap/blob/master/lua/dap.lua)

A plain JavaScript current-file Node launch is a safe dotfiles default only
inside a recognized non-Deno project. Unowned buffers abort instead of
inheriting Neovim's current directory. TypeScript execution, test runners,
browser URLs/executables, transpilers, environment files, output paths, remote
mappings, and source-map overrides are project facts and belong in
`.vscode/launch.json`. The existing provider already reads that file from the
initiating buffer's project root, filters by declared adapter types, expands
its supported variables recursively, defaults `cwd` to the project root, and
rereads the file for every selection.

nvim-dap supports only a subset of VS Code launch files. Its current loader
tolerates comments but still rejects trailing commas unless the repository
deliberately adds a JSON5 decoder. Only `promptString` and `pickString` inputs
are implemented; VS Code tasks, compounds, and arbitrary extension commands
are not supplied by Neovim. [nvim-dap launch-file
contract](https://github.com/mfussenegger/nvim-dap/blob/master/doc/dap.txt)

## Operational boundaries

The architecture and dependency ownership follow the repository's stated
principles: project dependencies own semantic behavior, Mason owns editor
executables, Conform is the sole formatter, LSP/DAP roots come from the buffer,
and DAP setup is lazy and guarded by one idempotence flag. Three operational
boundaries remain explicit:

1. **Workspace trust.** This personal configuration assumes repositories
   opened for development are trusted. Opening a project runs its root-local `tsc
   --version`, then starts that executable automatically; linting also loads
   executable project ESLint configuration and plugins. Do not open an
   untrusted checkout with this setup before reviewing it. If untrusted-project
   editing becomes a supported workflow, Neovim 0.12 can persist a
   non-recursive directory decision through `vim.secure.read(root)` and that
   decision should gate project-local executable/config evaluation. Debug
   launch remains user-triggered, binds the adapter to loopback, and must not
   gain automatic `preLaunchTask` or arbitrary command execution.
   [Neovim secure-read contract](https://github.com/neovim/neovim/blob/v0.12.5/runtime/doc/lua.txt)
2. **Real compatibility fixtures.** The exact Mason js-debug artifact has
   completed a plain Node launch, but that manual smoke is not a durable
   regression fixture. Automate launch/attach and the browser/source-map cases,
   and run the exact Mason ESLint LSP artifact against the promised ESLint
   matrix before changing its compatibility claim. Keep `eslint_d` until the
   latter passes.
3. **Actionable health.** `:checkhealth vim.lsp`, Mason, and nvim-dap expose
   generic state, but the repository has no JS/TS-specific health output. Add a
   small check reporting the selected root, trusted status, local TypeScript
   path/version, chosen semantic client, local ESLint version/owner, and Mason
   js-debug path/version. It should explain that Deno is intentionally excluded
   and that pre-7 projects without a root-local `tsserver.js` receive no
   TypeScript client. [Neovim LSP health guidance](https://github.com/neovim/neovim/blob/v0.12.5/runtime/doc/lsp.txt)

## Implementation

The completed vertical slice has a small production surface and a
verification-heavy edge:

1. Refreshed only the nvim-lspconfig lock to `221c438`.
2. Added mutually exclusive semantic routes: hardened project-local TypeScript
   7+ through native `tsc`, and project-local pre-7 TypeScript through Mason's
   `typescript-language-server` transport with the exact root-local
   `tsserver.js`; a version-notification guard terminates any workspace/bundled
   fallback or version mismatch. Both clients disable formatting so
   Prettier/Conform remains the only owner. Added Mason `js-debug-adapter`;
   left `eslint_d`, nvim-lint, and Conform unchanged.
3. Added one shared JS/TS project profile for LSP and DAP. It uses package
   manager lockfiles before `.git`, rejects Deno ownership, and never falls
   back to PATH or Neovim's current directory.
4. Added a small adapter module that lazily registers one js-debug server and
   one recognized-project JavaScript launch default using `pwa-node`. The
   launch provider and direct adapter aliases normalize the public
   `node`/`chrome`/`msedge` names to canonical `pwa-*` types. TypeScript and
   browser launches remain project-owned.
5. Extended inventory, context, version routing, native LSP activation, adapter
   lifecycle, and launch-file provider specs; updated Neovim and dependency
   documentation.

Production changes are concentrated in
`nvim/lua/custom/languages/config.lua`, a new language adapter,
`nvim/lua/custom/languages/init.lua`, a narrow resolver correction in
`context.lua`, and the plugin lock. Existing `dap.lua` supplies the shared lazy
lifecycle and launch-file provider unchanged. Keeping ESLint unchanged avoids
deleting `lint.lua`/nvim-lint or rewriting its regression fixture in this
slice.

## Verification

- Unit-tested that a recognized, non-Deno project with root-local TypeScript 7+
  starts only native `tsc`, while a root-local pre-7 installation with
  `typescript/lib/tsserver.js` starts only `ts_ls` with that exact language
  service. Missing, unparseable, unowned, Deno, and incomplete pre-7 projects
  attach neither; no PATH/CWD fallback occurs. Simulated bundled and mismatched
  version notifications are terminated while the exact project report remains
  attached.
- Tested that nested Node- and bundler-configured packages resolve to one
  workspace-root client while keeping their runtime options in project TSConfig
  files.
- Asserted both LSP configurations survive native nvim-lspconfig merging,
  remain mutually exclusive for TSX buffers, preserve upstream `ts_ls`
  commands, and leave ESLint/Prettier ownership unchanged. Mason owns the
  `typescript-language-server` transport but no TypeScript compiler.
- Live-verified
  `desaidn.dev/packages/assets/app/components/common/AppLayout.tsx`: exactly one
  `ts_ls` client attached at the workspace root, and the server's
  `$/typescriptVersion` notification reported version `5.9.3` from
  `user-setting`, proving it used the project language service rather than its
  bundled TypeScript.
- Unit-tested lazy, retryable, idempotent js-debug setup, canonical alias
  normalization, and adapter lookup without loading DAP merely by opening a
  JS/TS buffer. Live-smoked the exact Mason adapter with a public `node`
  configuration; it normalized to `pwa-node`, initialized, ran Node, and
  completed normally.
- Extended the launch-provider fixture with JS/TS buffers and Node/browser
  configurations; verified type filtering, buffer root, variables, default
  CWD, and fresh rereads without changing Neovim's CWD.
- Ran every headless spec, `stylua --check` on changed Lua, and
  `git diff --check`.

Remaining live verification covers project-defined TypeScript execution with
original-source breakpoints, Node attach and child processes, and a
source-mapped Chromium bundle including a worker. A live fixture should also
confirm that a Deno file receives neither TypeScript semantic route.
