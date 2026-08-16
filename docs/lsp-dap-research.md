# High-fidelity LSP and DAP for the primary language set

Status: investigation and implementation recommendation
Evidence checked: 2026-08-14
Scope: Rust, Kotlin, Java, Python, TypeScript/JavaScript for Node.js and browsers, Fish, and Bash/POSIX `sh` in this repository's Neovim 0.12.4 environment. Zsh is deliberately excluded from this implementation scope.

## Executive decision

The present configuration has a sound shared base—native Neovim LSP, `nvim-dap`, Mason provisioning, project runtimes in Mise, and one formatting pipeline—but it does not yet provide high-fidelity, cross-project language and debug support. It enables generic LSPs for all five language families, while DAP is configured only for Python. Several generic LSP choices also leave important server-specific features inaccessible.

The target should remain native-first:

| Language              | Primary semantic server                                                                   | Auxiliary analysis                              | Debug adapter/integration                                                                                                | Decision                                                                                                                                    |
| --------------------- | ----------------------------------------------------------------------------------------- | ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------- |
| Rust                  | Mason `rust-analyzer`, owned at runtime by `rustaceanvim`                                 | Clippy through rust-analyzer                    | Mason `codelldb`, configured through rustaceanvim/nvim-dap                                                               | Replace the generic `rust_analyzer` enablement with rustaceanvim; keep Mason as binary owner and add `rust-src` to the Mise Rust toolchain. |
| Java                  | Mason `jdtls`, owned per project by `nvim-jdtls`                                          | Existing Google Java Format only                | Mason `java-debug-adapter` and `java-test`, injected into JDT LS by nvim-jdtls                                           | Replace generic `jdtls` startup with nvim-jdtls and a collision-proof workspace-data path.                                                  |
| Kotlin                | Mason's official JetBrains `kotlin-lsp`                                                   | Existing ktlint only                            | Pilot JetBrains' experimental attach-only DAP; keep Mason `kotlin-debug-adapter` only as an explicitly degraded fallback | LSP is the best current upstream choice but remains alpha and JVM-centric. Full, stable Kotlin DAP does not exist for this client today.    |
| Python                | Mason `basedpyright`                                                                      | Mason native `ruff` LSP                         | Mason `debugpy` through `nvim-dap-python`                                                                                | Prefer basedpyright for maximum generic-LSP fidelity; Ruff owns lint/actions, Conform owns formatting, and neither duplicates the other.    |
| TypeScript/JavaScript | Project-local TypeScript 7 `tsc --lsp --stdio`, selected by upstream nvim-lspconfig `tsc` | Project-local ESLint through Mason `eslint-lsp` | Mason `js-debug-adapter` directly through nvim-dap                                                                       | TypeScript 7 made `ts_ls` a legacy default in July 2026. Keep a routed TypeScript 6 fallback only for embedded-language/plugin projects.    |
| Fish                  | Mason `fish-lsp`, selected by upstream nvim-lspconfig `fish_lsp`                          | Fish LSP diagnostics/actions                    | None — no broadly supported Fish DAP                                                                                    | Add the Fish parser and LSP. Let Fish LSP remain the single Fish formatting/diagnostic owner; it has the appropriate language-aware surface. |
| Bash/POSIX `sh`       | Mason `bash-language-server`, selected by upstream nvim-lspconfig `bashls`                | BashLS + its Mason `shellcheck` integration     | None — no broadly supported shell DAP                                                                                   | Add BashLS, ShellCheck, and `shfmt`; constrain workspace scanning and keep Conform/`shfmt` as the sole formatter.                            |

Two language plugins are justified exceptions to a pure generic-client configuration. [rustaceanvim](https://github.com/mrcjkb/rustaceanvim) exposes rust-analyzer extensions and converts project-derived runnables, tests, and debuggables into editor actions. [nvim-jdtls](https://github.com/mfussenegger/nvim-jdtls) exposes JDT LS refactors, class-file viewing, test discovery, and the Java debugger commands that a generic LSP client does not model. Both continue to use Neovim's native LSP and nvim-dap rather than introducing parallel clients.

The implementation must enforce one primary semantic server, one save-format owner, one lint/action owner, and one debug adapter for each buffer/runtime. Cross-project fidelity depends as much on correct roots, project-local toolchains, unique server state, and root-aware debug configuration as it does on installing binaries.

## What “full” means here

LSP and DAP are protocols, not guarantees that every server implements every capability. The [LSP 3.17 specification](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/) lets clients and servers negotiate capabilities, and the [Debug Adapter Protocol](https://microsoft.github.io/debug-adapter-protocol/overview) does the same for debugger features. A defensible acceptance target is therefore “the highest-fidelity supported surface for each upstream tool,” not artificial feature parity across languages.

For LSP, the acceptance matrix should cover:

- completion, signature help, hover, declarations, definitions, type definitions, implementations, references, rename, document/workspace symbols, call/type hierarchy, code actions and refactors;
- whole-project diagnostics where the server supports them, semantic tokens, inlay hints, folding, formatting ownership, and project configuration reloads;
- navigation across modules, workspace members, generated sources, dependencies, standard libraries, jars, type stubs, and declaration files;
- exact root, toolchain, build model, and project-local configuration selection when several unrelated projects and Git worktrees are open in one Neovim process.

For DAP, it should cover launch and attach where the adapter supports them; normal, conditional, hit-count, log, and exception breakpoints; pause, continue, step in/over/out; threads, stacks, scopes, variables, watches/evaluation, console output, restart/terminate; test-target discovery; source maps or source-path mappings; and project `.vscode/launch.json` configurations. An adapter may legitimately report that a capability is unavailable. Kotlin's current upstream limitations are called out separately below.

The result will still not be a single proprietary, polyglot semantic index. LSP clients can aggregate UI results from attached servers, but a refactor is performed by the server that owns the source file and workspace. Mixed Java/Kotlin and cross-runtime TypeScript behavior therefore need explicit fixture tests rather than assumptions.

## Current-state inventory

### Shared editor layer

`nvim/lua/custom/languages/lsp.lua` uses the Neovim 0.11+ `vim.lsp.config`/`vim.lsp.enable` API, merges Blink completion capabilities, attaches standard mappings, document highlights, and capability-gated inlay hints. This follows the current [Neovim LSP configuration model](https://neovim.io/doc/user/lsp/). `nvim-lspconfig` supplies executable, filetype, and root defaults.

`nvim/lua/custom/languages/dap.lua` owns the shared lazy `nvim-dap`, `nvim-dap-ui`, and `nvim-nio` stack plus the common controls; [`adapters/python.lua`](../nvim/lua/custom/languages/adapters/python.lua) separately owns lazy nvim-dap-python/debugpy setup for Python buffers. [nvim-dap](https://github.com/mfussenegger/nvim-dap) supports the required generic launch, attach, breakpoint, stepping, inspection, and REPL operations; adapters are intentionally language-specific dependencies.

Provisioning boundaries are clear:

- Mise pins Node 24.18.0, Python 3.14.6, Rust 1.97.1 with Clippy/rustfmt, and Amazon Corretto 21.0.12.8.1.
- Mason owns editor servers, formatters, linters, and debuggers.
- Homebrew owns standalone applications, while Mason owns the Python adapter and language tools.
- Conform is the save-format path; nvim-lint currently owns Ruff and `eslint_d` lint runs.

### Per-language state and gaps

| Language              | Current configuration                                                                                                  | Material gaps                                                                                                                                                                                                                                                                            |
| --------------------- | ---------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Rust                  | Generic `rust_analyzer`; globally enables every Cargo feature and uses Clippy; Mason installs rust-analyzer            | No rust-analyzer extensions, runnable/test/debug target discovery, macro expansion UI, or DAP adapter. `allFeatures = true` can make mutually exclusive feature sets invalid and is not a faithful universal default. Mise lacks `rust-src`.                                             |
| Java                  | nvim-jdtls starts Mason JDT LS per Java build root; Google Java Format via Conform; Mason Java debug/test bundles       | A real Gradle/Maven multi-module and JUnit/TestNG DAP fixture is still needed; the server and project JDK selection must remain visible when diagnosing build-model issues.                                                                                                              |
| Kotlin                | Official `kotlin_lsp`; ktlint via Conform                                                                              | Server is alpha/JVM-focused. No configured DAP. Android is experimental, Kotlin Multiplatform is not yet supported, and official DAP is experimental and attach-only.                                                                                                                    |
| Python                | BasedPyright semantic LSP; native Ruff LSP for diagnostics/actions; Conform runs Ruff fix/format/imports; Mason debugpy powers nvim-dap-python | Workspace diagnostics and mypy remain project-level choices; representative multi-package/test/attach fixtures are still needed. |
| TypeScript/JavaScript | `ts_ls`; Mason `typescript-language-server`; prettier/prettierd; `eslint_d`; no DAP                                    | It selects the old TypeScript 6 tsserver bridge rather than TypeScript 7's first-party native LSP. No Node/browser debugger, source-map configuration, ESLint code-action LSP, or explicit Node-versus-browser project contract.                                                         |
| Fish                  | Tree-sitter is not installed; no LSP, formatter, lint/action owner, or debugger                                                 | The primary interactive shell's functions, completions, abbreviations, and sourced configuration have no semantic navigation, diagnostics, or Fish-aware formatting.                                                                                                                      |
| Bash/POSIX `sh`       | Tree-sitter `bash` only; no LSP, formatter, or diagnostics                                                                   | Shell scripts lack cross-file navigation, ShellCheck analysis, and an explicit formatting owner.                                                                                                                                                                                              |

The initial cross-project foundation replaces nvim-dap's CWD-based `.vscode/launch.json` provider with one that receives the initiating buffer, resolves its declared project root, and substitutes all CWD-sensitive file/workspace values before nvim-dap expands them. The upstream provider's CWD behavior remains visible in the current [launch-file reader](https://raw.githubusercontent.com/mfussenegger/nvim-dap/master/lua/dap/ext/vscode.lua) and [configuration provider/variable expansion](https://raw.githubusercontent.com/mfussenegger/nvim-dap/master/lua/dap.lua). Adding a second manual `load_launchjs` call is not an alternative: it is deprecated in current nvim-dap.

## Shared target architecture

### One project-context boundary

Add one small locally owned module that resolves a named buffer through a caller-owned marker profile and derives collision-resistant workspace-data paths. Each consumer supplies its own profile: a Rust Cargo root, Python environment root, and Java build root can legitimately differ within one repository. Paths should be normalized with `vim.fs.normalize` without resolving symlinks by default; distinct Git worktrees must remain distinct roots.

This is a boundary, not a universal root algorithm or LSP-root replacement. It makes explicit project paths reusable by DAP, health reporting, JDTLS, and tests. It must not set global `cwd`, mutate every LSP root, or turn `.git` into a one-size-fits-all root. Unnamed and special buffers return no context rather than inheriting CWD.

### Root and client-reuse policy

| Ecosystem             | Root policy                                                                                                                                                             | Why                                                                                                                                                                                                                               |
| --------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Rust                  | Attached rust-analyzer root; otherwise nearest `Cargo.toml`, then `rust-project.json`/Git fallback                                                                     | Cargo workspace membership, target discovery, build scripts, and dependency graphs are semantic inputs.                                                                                                                           |
| Java                  | Highest applicable Gradle/Maven build root: wrapper, `settings.gradle[.kts]`, or reactor `pom.xml`; module build files are fallback                                     | JDT LS imports a build model. Starting one server for every module loses cross-module references; using the Git root for unrelated builds over-indexes.                                                                           |
| Kotlin                | `settings.gradle[.kts]`, Maven reactor `pom.xml`, supported build file, or JetBrains `workspace.json`; avoid a bare `.git` fallback when no supported JVM build exists  | The official server currently imports JVM Gradle/Maven models and has had nested-project import fixes; unrelated directories should not share its large index.                                                                    |
| Python                | Nearest `pyrightconfig.json` or relevant `pyproject.toml`, then packaging/project markers; Git only as a last fallback                                                  | Python monorepos often need explicit execution environments, import roots, and distinct virtual environments. Ruff may have a nearer lint configuration without becoming the semantic root.                                       |
| TypeScript/JavaScript | Package-manager lockfile/workspace root for one TypeScript 7 process; TypeScript selects nested `tsconfig.json`/`jsconfig.json` projects internally; exclude Deno roots | Upstream nvim-lspconfig's [`tsc` configuration](https://raw.githubusercontent.com/neovim/nvim-lspconfig/master/lsp/tsc.lua) is explicitly designed to run one native server for a monorepo and prefer the project-local compiler. |
| Fish                  | Nearest `config.fish`, otherwise the Git root; use the canonical configuration directory for the dotfiles checkout                | Upstream [`fish_lsp`](https://raw.githubusercontent.com/neovim/nvim-lspconfig/master/lsp/fish_lsp.lua) uses `config.fish` then `.git`. This gives functions and sourced files one intended configuration workspace without treating all of `$HOME` as a project. |
| Bash/POSIX `sh`       | Bounded script-project Git root; standalone/home-directory scripts retain the local, non-recursive scan policy                    | Upstream [`bashls`](https://raw.githubusercontent.com/neovim/nvim-lspconfig/master/lsp/bashls.lua) deliberately overrides BashLS's recursive default with `*@(.sh|.inc|.bash|.command)` so opening `~/foo.sh` does not recursively index the home directory. |

Neovim should reuse a client only when server identity and canonical root match. This allows two projects—or two worktrees whose leaf directory names are identical—to stay independent. Java's JDT data directory must be a stable hash of the full canonical root under `stdpath('cache')`, not simply the root basename. [JDT LS requires a unique `-data` directory per workspace](https://github.com/eclipse-jdtls/eclipse.jdt.ls#running-from-the-command-line).

### Root-aware DAP configuration

Keep nvim-dap's on-demand configuration-provider mechanism, but replace the default `dap.providers.configs['dap.launch.json']` function with a root-aware provider that, at debug-selection time:

- reads the active buffer's project root from the shared context module;
- reads that root's `.vscode/launch.json` on demand, with an explicit adapter-type mapping;
- recursively pre-resolves nvim-dap's CWD-sensitive file and workspace placeholders in keys and nested values against that same root, and supplies default `cwd` from it without changing global `cwd`;
- resolves prompts and functions at launch time rather than at Neovim startup;
- merges small language defaults only when no project configuration exists.

The project launch file is authoritative for bundlers, test runners, main classes, environment variables, remote source mappings, and browser URLs. nvim-dap supports a useful subset of VS Code launch configuration, not arbitrary VS Code extension commands. Its current Neovim 0.12 reader accepts comments, but standard JSON maximizes portability; if trailing commas or broader JSON5 syntax are required, choose and test one decoder rather than silently accepting different grammars.

Direct adapter registration is preferable to generic wrapper plugins when nvim-dap already models the adapter. The two server-specific LSP extensions remain because they expose semantics and target discovery that DAP alone cannot infer.

### Capability and ownership discipline

- Primary semantic client: rust-analyzer, JDT LS, Kotlin LSP, basedpyright, TypeScript 7, Fish LSP, or BashLS respectively.
- Auxiliary LSP: Ruff and ESLint only. Disable Ruff hover in favor of basedpyright; disable Ruff and ESLint formatting because Conform is the save-format owner.
- Import actions: disable basedpyright's organize-imports action when Ruff owns Python import sorting. Keep TypeScript import actions with the TypeScript server unless a project deliberately delegates them.
- Diagnostics: remove Ruff and `eslint_d` from nvim-lint once their LSPs attach, avoiding duplicate messages and two processes analyzing the same edits.
- Formatting: retain Ruff's existing Conform chain for Python, Google Java Format for Java, ktlint for Kotlin, prettier/prettierd for JavaScript/TypeScript, and Conform/`shfmt` for Bash/POSIX `sh`. Fish LSP's formatter is the sole Fish formatter; do not also add a save-time `fish_indent` command. For Rust, choose exactly one rustfmt path (rust-analyzer formatting is sufficient unless Conform is adopted deliberately).
- Keymaps and UI must remain capability-gated. Server-specific commands should be buffer-local and appear only for their language.

## Rust

### Recommended LSP

Use rustaceanvim v9 with the existing Mason rust-analyzer binary, and remove `rust_analyzer` from the table passed to generic `vim.lsp.enable`. rustaceanvim explicitly warns against separately enabling the same server. Its current v9 line targets Neovim 0.12 and exposes rust-analyzer-specific grouped code actions, hover actions, macro expansion, diagnostic explanations, dependency-aware workspace symbols, runnables, testables, and debuggables that generic LSP cannot represent. Those capabilities are the reason to accept this extra plugin for the high-fidelity goal; [rustaceanvim describes the built-in/lspconfig route as lowest-common-denominator support](https://github.com/mrcjkb/rustaceanvim).

Keep the rust-analyzer executable Mason-owned to match this repository's editor-tool policy. This is a conscious local-policy tradeoff: rustaceanvim's troubleshooting guide [strongly recommends a toolchain-matched rust-analyzer instead of Mason](https://github.com/mrcjkb/rustaceanvim) because version skew can cause subtle failures. Add `rust-src` to the exact Mise Rust toolchain components because rust-analyzer requires standard-library sources for full navigation and analysis; the [official installation guide](https://rust-analyzer.github.io/book/installation.html) documents the source requirement and support expectations around current stable Rust. Project `rust-toolchain.toml` overrides remain authoritative. Health checks must display both rust-analyzer and Cargo/Rust versions. If the compatibility fixture fails for supported toolchain overrides, move rust-analyzer into the Mise Rust components and remove its Mason entry—never install both.

Do not globally set `cargo.allFeatures = true`. The [rust-analyzer configuration reference](https://rust-analyzer.github.io/book/configuration) shows that the modern `cargo.features` default is an empty list and accepts selected features or `"all"`; all features can be wrong for crates with mutually exclusive feature gates. Default to Cargo's configured/default feature set and let a trusted local Neovim setting or an explicitly parsed `.vscode/settings.json` opt into selected/all features. rustaceanvim does not load that file by itself without a settings provider, so the implementation must choose and document the mechanism rather than implying automatic project config. Preserve Clippy-on-check if its latency is acceptable, but make it a measured default rather than coupling it to all features. For large workspaces, `cargo.targetDir` isolation can avoid Cargo/rust-analyzer lock contention at the cost of duplicate artifacts and disk usage; it should be opt-in and tested.

### Recommended DAP

Install Mason `codelldb` and let rustaceanvim translate rust-analyzer debug targets into nvim-dap configurations. This is more faithful than guessing a binary path from the current file: rust-analyzer already knows Cargo packages, targets, features, and build output. Retain root `.vscode/launch.json` support for explicit attach, environment, source-map, and remote cases. CodeLLDB supports Cargo launch semantics, source languages/maps, process selection, and Rust-aware data formatting; see its [upstream manual](https://github.com/vadimcn/codelldb/blob/master/MANUAL.md).

Acceptance must include a multi-crate Cargo workspace, a proc macro/build script, dependency and standard-library navigation, a crate with mutually exclusive features, a test debug target, a normal binary target, conditional/log breakpoints, expression evaluation, and two same-basename worktrees open at once.

## Java

### Recommended LSP

Continue using Mason JDT LS, but start it per Java project through nvim-jdtls and remove `jdtls` from generic `vim.lsp.enable`. nvim-jdtls provides the JDT-specific refactors, extended symbols, class-file content, bytecode/jshell tools, test helpers, and debug wiring needed for high fidelity. Its own configuration documentation says not to use generic `vim.lsp.enable('jdtls')` when using the project/ftplugin startup route. [Its supported extension surface is documented upstream](https://github.com/mfussenegger/nvim-jdtls#extensions).

Run the server on the existing Mise Corretto 21: current JDT LS requires Java 21, while it can analyze projects targeting other installed JDKs through `java.configuration.runtimes`. [nvim-jdtls documents that separation](https://github.com/mfussenegger/nvim-jdtls#configuration), and [JDT LS documents its Java and build-tool support](https://github.com/eclipse-jdtls/eclipse.jdt.ls). Do not force every Java project to target 21; project Gradle/Maven toolchains remain authoritative.

Construct the command and bundle paths through Mason APIs/registry locations, not hardcoded platform paths. Give each root a `-data` directory whose name includes a readable basename plus a hash of the full normalized root. Stop or reuse a client only for an exact root match. Keep JDT formatting disabled so Google Java Format through Conform remains the only formatting path.

### Recommended DAP and tests

Install Mason `java-debug-adapter` and `java-test`, add their plugin jars to JDT LS `init_options.bundles`, and call nvim-jdtls's DAP setup after nvim-dap is available. [Microsoft's Java debug server](https://github.com/microsoft/java-debug) is a DAP implementation layered through JDT LS and supports launch/attach, JDI stepping, variables, exceptions, threads, and console operations. [VS Code Java Test](https://github.com/microsoft/vscode-java-test) provides JUnit and TestNG run/debug support; nvim-jdtls exposes class/nearest-method test commands when those bundles are installed.

Load order matters because the current DAP stack is lazy. The Java setup must be able to ensure nvim-dap without recursively re-running global setup, then register project configurations after JDT LS is ready. Main-class and test discovery should drive generated configurations; project launch files remain available for custom arguments, modules, and attach sessions.

Acceptance must include Gradle and Maven multi-module projects, mixed source/test trees, library and generated-source navigation, source-level refactors, a project targeting a JDK other than the server JDK, JUnit and TestNG test debugging, main-class discovery, attach, and two same-basename projects with different hashed data directories.

## Kotlin

### Best attainable LSP

Keep the official JetBrains Kotlin LSP. As of this review, Mason packages v262.9593.0 and exposes the new `intellij-server` launcher. The [upstream project](https://github.com/Kotlin/kotlin-lsp) calls the server alpha, partially closed source, focused on JVM Gradle/Maven projects, experimental for Android, and not yet available for Kotlin Multiplatform. It nevertheless has the strongest current lineage: IntelliJ-based indexing, completion, diagnostics/quick fixes, navigation, references/rename, semantic highlighting, inlay information, hierarchy, formatting, and ongoing build-model work.

The upstream release line has recently improved nested-project import behavior, persistent workspace models, cross-language references, nonstandard source sets, and compiler-plugin support; consult the [official release history](https://github.com/Kotlin/kotlin-lsp/blob/main/RELEASES.md) whenever the Mason package moves. Because it remains alpha and releases are principally exercised through the VS Code integration, pin the Neovim plugin lock as usual, record the Mason package version in health output, and keep a representative Gradle/Maven acceptance corpus.

The server documentation says JDK 25 is required, but the current standalone Mason artifact bundles JetBrains Runtime 25 and its native launcher uses that runtime; the [Mason recipe](https://raw.githubusercontent.com/mason-org/mason-registry/main/packages/kotlin-lsp/package.yaml) installs JetBrains' platform-specific standalone archives, while the [official release history](https://raw.githubusercontent.com/Kotlin/kotlin-lsp/main/RELEASES.md) records the zero-dependency distribution and launcher transition. Do not replace Mise Corretto 21 or add a second global JDK merely to launch this packaged server. Project JDK selection remains a build-model concern. If the deployment ever switches to a non-bundled Kotlin LSP distribution, provision its server JDK as a tool-scoped runtime rather than changing every Java/Kotlin project's default.

Use the real Gradle/Maven/workspace root and one client per imported build. Keep ktlint/Conform as formatter owner and disable the Kotlin LSP formatting capability if both would otherwise be offered. Validate mixed Java/Kotlin navigation from both directions; do not claim a unified IntelliJ index until the fixture proves it.

### DAP limitation and decision gate

JetBrains' [release notes](https://raw.githubusercontent.com/Kotlin/kotlin-lsp/main/RELEASES.md) describe an experimental DAP with attach to an already-running JVM, line breakpoints, pause/resume, stepping, threads, stacks, variables, and simple evaluation. The same release line records a hotfix that disabled faulty parts of the work-in-progress JVM adapter. It does not yet provide a documented, stable, editor-agnostic launch contract. This is the largest blocker to the requested “full DAP” state.

Implementation should first run a bounded protocol spike against the exact Mason standalone artifact:

1. start a fixture through its Gradle/Maven wrapper with JDWP enabled;
2. determine the supported adapter entry point and transport from upstream artifacts/documentation, without reverse-engineering a private VS Code-only contract into permanent config;
3. attach through nvim-dap and verify breakpoints, source mapping, frames, variables, evaluation, disconnect, and a test task;
4. ship it only if the interface is stable enough to health-check and test on macOS and Linux.

Mason's [`kotlin-debug-adapter` 0.4.4](https://github.com/fwcd/kotlin-debug-adapter) is the best currently packaged launch/attach fallback, but it comes from an older Kotlin 1.9.10-era implementation. It requires an already compiled Maven/Gradle project plus explicit absolute `projectRoot` and `mainClass` information. It is not parity-grade and should not become the silent default. If the JetBrains pilot fails, either expose this adapter under a clearly named “legacy Kotlin debug” opt-in or leave Kotlin debugging documented as blocked pending upstream maturity. Kotlin/JS can sometimes be debugged as emitted JavaScript through js-debug and correct source maps, but that is a project-specific runtime path, not proof of general KMP/Native DAP support.

## Python

### Recommended LSP and analysis split

Replace `pyright` with Mason `basedpyright` for the stated maximum-fidelity objective, with a documented provenance tradeoff. basedpyright is a maintained community fork of Microsoft's Pyright. It brings capabilities normally associated with Pylance to generic LSP clients: semantic highlighting, inlay hints, import quick fixes, module/package rename, operator navigation, go-to-implementation, compiled-builtin docstrings, and richer completions/diagnostic controls. Its [Pylance-feature comparison](https://docs.basedpyright.com/latest/benefits-over-pyright/pylance-features/) and [language-server improvements](https://docs.basedpyright.com/latest/benefits-over-pyright/language-server-improvements/) specify the additions. If first-party provenance is later judged more important than that capability surface, plain Pyright is the supported rollback; never attach both.

Set workspace diagnostics explicitly for repository-scale feedback. Use project `pyrightconfig.json` or `pyproject.toml` for include/exclude paths, Python version/platform, and strictness. In multi-package repositories, define execution environments rather than pretending one import root applies everywhere; the [official Pyright configuration reference](https://github.com/microsoft/pyright/blob/main/docs/configuration.md) documents `executionEnvironments` and interpreter settings. Avoid committing a user-specific absolute `venvPath`.

Enable Mason's native `ruff` LSP rather than the deprecated `ruff-lsp` bridge. Per [Ruff's official editor setup](https://docs.astral.sh/ruff/editors/setup/), disable Ruff hover when paired with a type checker, and disable basedpyright's organize-imports action when Ruff owns import sorting. Also disable Ruff formatting at the LSP capability boundary because the existing Conform `ruff_fix` → `ruff_format` → `ruff_organize_imports` chain remains the only save-format route. Remove Python Ruff from nvim-lint so diagnostics and fixes are not duplicated.

The active environment resolver should prefer an explicit configuration/activated environment and then a root-local `.venv`/`venv`, with a visible fallback to the Mise Python. The same resolved interpreter and root must feed basedpyright and DAP. A monorepo with multiple execution environments may require a per-launch prompt or project launch configuration rather than a single root interpreter.

### Recommended DAP

Keep nvim-dap-python, but make Mason `debugpy` the deterministic adapter owner rather than relying on `uv` to fetch/resolve a debugger on first use. Pass nvim-dap-python either Mason's `debugpy-adapter` executable or the Python interpreter in Mason's debugpy environment, rather than a project interpreter that may not contain debugpy. nvim-dap-python already provides project-environment discovery, pytest/unittest/Django support, nearest method/class/selection test debugging, and launch-file integration; see its [upstream documentation](https://github.com/mfussenegger/nvim-dap-python). Add the missing test mappings and root-aware configurations while preserving the generic DAP UI.

Use launch for normal scripts/modules/tests and attach for long-running or container processes. Debugpy should listen on loopback unless a user deliberately configures remote access; [debugpy's upstream documentation](https://github.com/microsoft/debugpy) warns that a public listener without access controls allows arbitrary clients to connect and execute code.

Acceptance must include a uv-locked project, root-local `.venv`, module launch, arguments/environment, pytest nearest method and class, subprocess handling, attach, multiple Python packages with execution environments, compiled-builtin/stub navigation, and no duplicate Ruff diagnostics or import actions.

## TypeScript and JavaScript: Node and browser

### TypeScript 7 changes the default

TypeScript 7.0 became stable on 2026-07-08 and ships a first-party native LSP in the project `tsc` executable. The [official announcement](https://devblogs.microsoft.com/typescript/announcing-typescript-7-0/) says editors can run the project-installed compiler via LSP and lists auto-imports, hovers, inlay hints, code lenses, source-definition navigation, JSX linked editing, semantic highlighting, and import actions. Microsoft also reports substantially lower command-failure and crash rates than TypeScript 6 in its telemetry. This makes a generic `typescript-language-server`/tsserver bridge the wrong default for ordinary Node and browser TypeScript projects.

Update the nvim-lspconfig package lock to a revision containing its upstream [`tsc` config](https://raw.githubusercontent.com/neovim/nvim-lspconfig/master/lsp/tsc.lua), then replace `ts_ls` with `tsc`. That config searches `node_modules/.bin/tsc` (or the transitional native executable) before PATH, starts `--lsp --stdio`, supports a monorepo in one process, lets TypeScript select the nested tsconfig/jsconfig project, and excludes Deno projects. Harden its permissive Git/`cwd` fallback for this multi-project setup: require a recognized project root and project-local TypeScript, or an explicit local opt-in, rather than accidentally starting an ambient global compiler in the wrong workspace. The compiler must be a project dependency so editor analysis and command-line builds use the same TypeScript version. Remove Mason `typescript-language-server` from the normal inventory. Its [current Mason recipe](https://raw.githubusercontent.com/mason-org/mason-registry/main/packages/typescript-language-server/package.yaml) deliberately pins TypeScript 6.0.3 because TypeScript 7 removed `tsserver.js`.

TypeScript 7.0 has one important boundary: it does not expose a stable language-service API. The TypeScript team says Vue, MDX, Astro, Svelte, Angular templates, and other language-service-plugin/embedded-language workflows still need TypeScript 6 editor support until a new API arrives. Keep a documented, project-routed fallback using project TypeScript 6 plus vtsls or `ts_ls`, selected from unambiguous project/framework markers or an explicit local setting. [vtsls](https://github.com/yioneko/vtsls) can provide a close-to-VS-Code TS6 experience but is a community best-effort server, so it is a compatibility lane, never a concurrently attached second TypeScript server. TypeScript's official side-by-side `@typescript/typescript6` package is the preferred compiler compatibility mechanism.

Project tsconfig files, not editor globals, distinguish runtimes. Node packages should model Node's module/type environment; browser/bundler packages should model DOM libraries and bundler resolution. TypeScript 7 changes defaults—including explicit `types`, and `nodenext` or `bundler` replacing legacy Node/classic resolution—so the migration must run project builds as well as LSP checks. A pnpm/npm/yarn workspace may intentionally contain both Node and browser packages under one native server.

### ESLint LSP

Replace `eslint_d` through nvim-lint with Mason `eslint-lsp`, backed by the project's local ESLint/config/plugins. Microsoft's [VS Code ESLint server](https://github.com/microsoft/vscode-eslint) supports live diagnostics, code actions, flat configuration, and per-workspace working directories. Set working directories explicitly or use its auto mode for package-based monorepos. Disable its formatting capability so Prettier/Conform remains the only save formatter; expose ESLint fix-all as a deliberate code action rather than another automatic format pass.

The Mason `eslint-lsp` package uses the extracted VS Code language-server distribution and can lag the latest editor extension. Treat registry version and flat-config compatibility as health/fixture assertions rather than assuming parity with whichever project ESLint version is newest.

### Node and browser DAP

Install Mason `js-debug-adapter` and register its executable directly as an nvim-dap server adapter, passing the selected port. Do not add `nvim-dap-vscode-js`: nvim-dap can register server adapters natively, and the wrapper's own compatibility notes have lagged upstream build changes and describe browser support as partial. Microsoft's [js-debug](https://github.com/microsoft/vscode-js-debug) is the upstream DAP used for Node.js and Chromium-family browser debugging; it supports source maps, workers/child processes, minified variable remapping, launch, and attach.

Provide only safe, small defaults:

- Node launch of the current JavaScript/TypeScript entry with project root as `cwd`;
- Node attach with process selection;
- browser launch/attach using a project-specified URL, `webRoot`, and executable where needed.

Register the adapter types used by js-debug launch files (notably the modern Node and Chromium types) so nvim-dap's root-aware launch provider can load project `.vscode/launch.json`. Project configurations should own dev-server commands, Jest/Vitest behavior, transpilers, runtime executables, environment files, source maps, workers, and remote path mappings. Do not guess a global test runner or browser application path. A browser is a runtime prerequisite for browser debugging, not a new baseline Homebrew editor dependency.

Acceptance must include plain Node JavaScript, TypeScript executed through the project's chosen loader/build output, child processes, a source-mapped browser bundle in Chromium, breakpoints in original TypeScript, a worker, project launch-file selection, a Node package and browser package in one monorepo, and the explicit TypeScript 6 embedded-language fallback without a duplicate `tsc` client.

## Fish and Bash/POSIX shell

### Fish

Install Mason `fish-lsp`, add the `fish` Tree-sitter parser, and enable upstream nvim-lspconfig `fish_lsp`. Its command is `fish-lsp start`, it attaches only to the `fish` filetype, and its standard roots are `config.fish` and `.git`; the [current lspconfig definition](https://raw.githubusercontent.com/neovim/nvim-lspconfig/master/lsp/fish_lsp.lua) and [Mason package mapping](https://raw.githubusercontent.com/mason-org/mason-registry/main/packages/fish-lsp/package.yaml) establish those names. The pinned nvim-lspconfig revision already provides this configuration.

Fish LSP is a genuine high-fidelity shell server: its [upstream feature matrix](https://github.com/ndonfris/fish-lsp) includes completion, signature help, definition/implementation/references, rename, document/workspace symbols, diagnostics/actions, semantic tokens, inlay hints, indexing, and full/range/on-type formatting. Leave its formatter enabled and do not also add a Conform formatter or save-time `fish_indent`; that preserves one Fish formatting owner. `fish_indent` remains the authoritative Fish command-line formatter for CI or manual use, as [Fish documents](https://fishshell.com/docs/current/cmds/fish_indent.html), but it is not a second interactive formatter.

The server indexes Fish configuration and source files. Preserve single-workspace behavior, avoid injecting broad Fish-LSP environment variables into `fish/config.fish`, and keep indexing bounded: its documented defaults include configuration/data directories, ignores for `.git`, `node_modules`, `containerized`, and `docker`, and a maximum workspace depth. Configure any stricter ignore/depth limit through the Neovim-launched process only after exercising this dotfiles workspace. Do not turn `$HOME` into a root or recursively index all user files. The [upstream configuration reference](https://raw.githubusercontent.com/ndonfris/fish-lsp/master/README.md) documents `fish_lsp_single_workspace_support`, indexed/ignored paths, background-file limits, and depth controls.

### Bash and POSIX `sh`

Install Mason `bash-language-server`, `shellcheck`, and `shfmt`; enable lspconfig `bashls` only for `bash` and `sh` filetypes. BashLS supplies declarations, references, symbols, occurrences, completion, hover, rename, and formatting; it automatically uses installed ShellCheck for debounced linting and `shfmt` for its formatting action, as documented by [the upstream server](https://github.com/bash-lsp/bash-language-server). Keep `shellcheck` out of nvim-lint for these buffers so the same diagnostic does not arrive through two processes. ShellCheck is the Bash/POSIX analysis owner through BashLS; it is not a Fish or Zsh analyzer.

Disable BashLS formatting capability and configure Conform `shfmt` for both `bash` and `sh`, making Conform the sole save-format path. The current [Conform `shfmt` definition](https://raw.githubusercontent.com/stevearc/conform.nvim/master/lua/conform/formatters/shfmt.lua) deliberately defers to a nearest `.editorconfig` when present; preserve that project contract rather than forcing editor indentation flags. `shfmt` supports POSIX shell and Bash (as well as other shells), but that does not make BashLS semantically suitable for them all.

Keep the safe lspconfig `bashIde.globPattern` default, `*@(.sh|.inc|.bash|.command)`. Upstream changed it from BashLS's recursive `**/*...` default specifically to avoid recursively scanning the home directory when a standalone script is opened. A recursively scanned glob is permitted only in a deliberately bounded script repository and must exclude generated/vendor directories. Node 24 already satisfies BashLS's upstream Node 20+ requirement; do not globally npm-install it because Mason owns this editor tool.

### Explicit Zsh boundary

Do not attach `bashls` to `zsh`, even though Mason categorizes its package broadly. BashLS's current Neovim configuration intentionally lists only `bash` and `sh`, and Bash/POSIX diagnostics cannot faithfully model Zsh syntax and semantics. This change adds no Zsh LSP, linter, formatter, or DAP configuration; a future Zsh-specific server would need a separate, fixture-backed evaluation. Do not mistake nvim-lspconfig's `zls` for Zsh support—it is the Zig language server.

Acceptance fixtures should cover: this repository's `fish/config.fish`, an autoloaded Fish function and completion with cross-file navigation/rename, Fish formatting and diagnostics without a second formatter; a POSIX script with `#!/bin/sh`, a Bash script with arrays/functions and ShellCheck findings, `.editorconfig`-controlled `shfmt`, a sourced sibling script, and a standalone script opened below `$HOME` without workspace recursion. Run a Fish configuration check with `fish -n` where appropriate and ShellCheck in the fixture/CI command; editor integration complements rather than replaces those commands. Shell debugging is intentionally outside this scope because no comparably established, cross-shell DAP is available.

## Provisioning and ownership changes

The versions below are an observation of the Mason registry on 2026-08-13, not a recommendation to hardcode registry internals in Lua. Mason's named package installs float under the current repository policy; the resolved version should be shown by health checks and captured in failure reports.

| Mason package                                                                                                                                    | Observed package version              | Action                                                                                 |
| ------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------- | -------------------------------------------------------------------------------------- |
| [`rust-analyzer`](https://raw.githubusercontent.com/mason-org/mason-registry/main/packages/rust-analyzer/package.yaml)                           | 2026-08-03                            | Keep; rustaceanvim becomes lifecycle owner.                                            |
| [`codelldb`](https://raw.githubusercontent.com/mason-org/mason-registry/main/packages/codelldb/package.yaml)                                     | 1.12.2                                | Add.                                                                                   |
| [`jdtls`](https://raw.githubusercontent.com/mason-org/mason-registry/main/packages/jdtls/package.yaml)                                           | 1.60.0 / 20260626 snapshot            | Keep; nvim-jdtls becomes lifecycle owner.                                              |
| [`java-debug-adapter`](https://raw.githubusercontent.com/mason-org/mason-registry/main/packages/java-debug-adapter/package.yaml)                 | extension 0.59.0 / plugin 0.53.2      | Add.                                                                                   |
| [`java-test`](https://raw.githubusercontent.com/mason-org/mason-registry/main/packages/java-test/package.yaml)                                   | extension 0.45.0 / plugin 0.43.1      | Add.                                                                                   |
| [`kotlin-lsp`](https://raw.githubusercontent.com/mason-org/mason-registry/main/packages/kotlin-lsp/package.yaml)                                 | 262.9593.0                            | Keep; use bundled JBR/native launcher.                                                 |
| [`kotlin-debug-adapter`](https://raw.githubusercontent.com/mason-org/mason-registry/main/packages/kotlin-debug-adapter/package.yaml)             | 0.4.4                                 | Conditional legacy fallback only, after the official DAP pilot.                        |
| [`basedpyright`](https://raw.githubusercontent.com/mason-org/mason-registry/main/packages/basedpyright/package.yaml)                             | 1.39.9                                | Add, replacing `pyright`.                                                              |
| [`ruff`](https://raw.githubusercontent.com/mason-org/mason-registry/main/packages/ruff/package.yaml)                                             | 0.16.2                                | Keep, now as native LSP plus existing Conform formatter executable.                    |
| [`debugpy`](https://raw.githubusercontent.com/mason-org/mason-registry/main/packages/debugpy/package.yaml)                                       | 1.8.21                                | Add.                                                                                   |
| [`js-debug-adapter`](https://raw.githubusercontent.com/mason-org/mason-registry/main/packages/js-debug-adapter/package.yaml)                     | 1.117.0                               | Add.                                                                                   |
| [`eslint-lsp`](https://raw.githubusercontent.com/mason-org/mason-registry/main/packages/eslint-lsp/package.yaml)                                 | `vscode-langservers-extracted` 4.10.0 | Add, replacing `eslint_d`.                                                             |
| [`typescript-language-server`](https://raw.githubusercontent.com/mason-org/mason-registry/main/packages/typescript-language-server/package.yaml) | 5.3.0 with TypeScript 6.0.3           | Remove from the default; only add a routed TS6 fallback if a real project requires it. |
| [`fish-lsp`](https://raw.githubusercontent.com/mason-org/mason-registry/main/packages/fish-lsp/package.yaml)                                     | 1.1.3                                 | Add; `fish_lsp` becomes Fish's sole semantic/formatting owner.                         |
| [`bash-language-server`](https://raw.githubusercontent.com/mason-org/mason-registry/main/packages/bash-language-server/package.yaml)             | 5.6.0                                 | Add; enable only for Bash/POSIX `sh`, with bounded workspace scanning.                 |
| [`shellcheck`](https://raw.githubusercontent.com/mason-org/mason-registry/main/packages/shellcheck/package.yaml)                                 | 0.11.0                                | Add; used by BashLS, not separately through nvim-lint.                                 |
| [`shfmt`](https://raw.githubusercontent.com/mason-org/mason-registry/main/packages/shfmt/package.yaml)                                           | 3.13.1                                | Add; Conform's only Bash/POSIX `sh` formatter.                                         |

The [Mason registry recipes](https://github.com/mason-org/mason-registry/tree/main/packages) are the primary evidence for packaged versions, executable names, platforms, and artifact layouts. The implementation should resolve package install paths through Mason registry/package APIs and fail with a useful health message when an expected executable or bundle is absent.

Mise changes are intentionally small:

- keep the exact Node, Python, Rust, and Corretto pins;
- add `rust-src` to the Rust components;
- do not add JDK 25 for Mason's bundled Kotlin LSP;
- do not install TypeScript globally through Mise/npm; each project owns TypeScript 7 and any TypeScript 6 compatibility package;
- do not make project Python environments or Java build toolchains global defaults.

Homebrew needs no LSP or DAP formula. Mason owns debugger/server packages. Project repositories own Cargo manifests/toolchain overrides, Gradle/Maven wrappers and toolchains, Python dependency locks/environments/config, TypeScript/compiler/ESLint dependencies and configuration, browser bundler/source maps, and `.vscode/launch.json`.

Neovim plugin changes are limited to rustaceanvim and nvim-jdtls. Pin them through the existing `vim.pack` lock workflow. No new generic DAP wrapper is required for JavaScript, Python, or Kotlin's pilot.

## Verification strategy

### Fast static and headless checks

Extend the existing Neovim runtime-test effort with assertions that:

- every configured LSP name exists in the pinned nvim-lspconfig/runtime state;
- `tsc` is present before enabling the TypeScript 7 migration;
- `fish_lsp` is present before enabling Fish support, and `bashls` is configured only for `bash`/`sh`, never `zsh`;
- no buffer can attach two primary semantic servers for one language;
- rust-analyzer and JDT LS are absent from generic `vim.lsp.enable` when their extension owns startup;
- Mason package names resolve, expected executables/bundles exist, and adapter commands are executable on the platform;
- every filetype has a single format-on-save owner and no Ruff/ESLint nvim-lint duplication;
- root selection handles nested modules, unrelated projects in one Git repository, symlinks, and two worktrees with the same leaf basename;
- Java data-directory hashes differ for distinct canonical roots;
- root-aware launch configuration resolves the active buffer's root without mutating global `cwd`;
- debug setup remains lazy and idempotent when Java/Rust setup asks for nvim-dap.

Run `:checkhealth vim.lsp`, `:checkhealth dap`, Mason status checks, Lua formatting/static checks, and the repository's normal headless Neovim tests. Installer/Mise changes also require `tests/install_test.sh` under the root install contract.

### LSP integration fixtures

Create small, deterministic fixtures outside the production config or generate them in test temp directories:

- Rust: multi-crate workspace, proc macro/build script, dependency source, mutually exclusive feature sets.
- Java: Gradle multi-module mixed Java/Kotlin project and Maven reactor; two target JDKs.
- Kotlin: supported Gradle and Maven JVM layouts, nested builds, Java cross-references, compiler plugin/nonstandard source set where feasible.
- Python: uv project with `.venv`, multi-package execution environments, tests, compiled/stubbed dependency.
- TypeScript: package-manager monorepo with project references, Node and browser packages, source maps, and a Deno subtree; separate embedded-language fixture for the TypeScript 6 route.

For each fixture, open a buffer headlessly, wait for attachment, and assert primary client name, executable, canonical root, project-local tool version, negotiated capabilities, and absence of a duplicate. Exercise definition, references, rename, workspace symbol, diagnostics, semantic tokens/inlay hints, code actions, and dependency navigation across module boundaries. Server-specific features—Rust macro expansion/runnables and Java refactors/test discovery—need their own assertions or scripted manual checks.

### DAP protocol smoke tests

Each supported runtime needs a tiny program with a deterministic breakpoint. Drive nvim-dap through listeners and assert initialized → stopped → stack/thread/scope/variable/evaluate → continued → terminated. Cover:

- Rust binary and test via rust-analyzer discovery/CodeLLDB;
- Java main, JUnit/TestNG test, and attach via JDT LS;
- Python module, nearest test, subprocess, and attach via debugpy;
- Node launch/attach plus TypeScript source maps;
- Chromium launch/attach with a source-mapped browser bundle in an opt-in environment where a compatible browser is installed;
- Kotlin attach only if the official pilot passes, otherwise a separately labeled legacy-adapter test.
- Fish: `config.fish`, an autoloaded function, and a completion definition with workspace navigation, diagnostics, and one formatting edit.
- Bash/POSIX `sh`: a sourced sibling script, ShellCheck findings, `.editorconfig`-driven `shfmt`, and a standalone home-directory script proving that recursive workspace scanning is not enabled.

Also verify conditional, log, hit-count, and exception breakpoints wherever the adapter advertises support. Run two same-basename projects in one Neovim process and confirm launch files, build artifacts, source maps, and server caches do not cross. macOS arm64 and Linux x86_64 are the minimum useful platform matrix; CodeLLDB signing/ptrace restrictions and browser availability should be reported as environment skips, not disguised as language failures.

### Manual acceptance

A final manual pass should confirm discoverability and ergonomics: capability-gated keymaps, project/root/tool version visible in health/status, library/dependency source buffers, correct inlay hints and semantic highlighting, target/test pickers, REPL/evaluation, restart/terminate, log points, and usable error messages for a missing adapter or unsupported project. It must also confirm that saving once produces one formatting edit and one set of diagnostics.

## Phased implementation plan

### Phase 0 — Lock the contract and fixtures

1. Turn the LSP/DAP capability lists above into an acceptance matrix.
2. Add root-selection fixtures, including same-basename worktrees and nested builds.
3. Update the nvim-lspconfig lock to a revision containing `tsc`, and run the existing Neovim regression suite before behavior changes.
4. Record baseline startup time, resident memory, indexing time, diagnostic latency, and existing formatter/linter output.

Exit criterion: tests describe roots, ownership, and capability expectations before servers are swapped.

### Phase 1 — Shared project and debug foundation

1. Implement the active-buffer project-context module with explicit primary-client priority.
2. Replace nvim-dap's cwd-based launch-file provider with the root-aware on-demand provider, and add adapter path resolution without adding a duplicate manual loader.
3. Add logpoint/exception controls and reusable test-debug mapping conventions without loading DAP at startup.
4. Add health output for roots, attached clients, commands, runtimes, Mason packages/adapters, and server-specific data paths.

Exit criterion: a synthetic two-project session selects the correct root/launch file and does not change global `cwd`.

### Phase 2 — Rust vertical slice

1. Add rustaceanvim and codelldb; add `rust-src` to Mise.
2. Remove generic rust-analyzer enablement while keeping Mason installation.
3. Remove global all-features; preserve measured Clippy behavior and add project overrides.
4. Wire project runnables, testables, debuggables, launch files, macro/hover/code-action commands, and integration tests.

Exit criterion: the Rust fixture passes the full supported LSP/DAP matrix with one rust-analyzer client per Cargo workspace.

### Phase 3 — Python vertical slice

1. Replace Pyright with basedpyright; explicitly enable workspace diagnostics.
2. Enable native Ruff LSP with hover/format disabled and basedpyright organize-imports disabled.
3. Remove Python Ruff from nvim-lint; keep the Conform chain.
4. Add Mason debugpy, root/interpreter resolution, and nearest test/class/selection debug mappings.

Exit criterion: type/navigation features, whole-workspace diagnostics, Ruff actions, formatting, and debug tests pass without duplicates.

### Phase 4 — Java vertical slice

1. Add nvim-jdtls, java-debug-adapter, and java-test.
2. Replace generic startup with exact-root `start_or_attach`, hashed data directories, Mason bundle discovery, and configured JDK runtimes.
3. Add refactor/source/test/main/debug commands and ensure DAP lazy-load ordering is safe.

Exit criterion: Gradle and Maven multi-module fixtures pass, including tests and same-basename workspace isolation.

### Phase 5 — TypeScript/JavaScript vertical slice

1. Replace `ts_ls` with project-local TypeScript 7 through `tsc`; remove default Mason typescript-language-server.
2. Replace `eslint_d`/nvim-lint with ESLint LSP and keep Prettier/Conform formatting.
3. Register Mason js-debug-adapter directly for Node and browser adapter types.
4. Add Node/browser/source-map fixtures and a narrowly routed TS6 embedded-language compatibility fixture.

Exit criterion: ordinary Node/browser projects run only TypeScript 7, source-mapped breakpoints bind, and the TS6 fallback never attaches concurrently.

### Phase 6 — Kotlin pilot and best-attainable slice

1. Harden official Kotlin LSP root selection, launcher discovery, format ownership, cache observation, and JVM build fixtures.
2. Execute the JetBrains DAP attach pilot against the exact packaged release.
3. If successful, ship/test the supported attach surface and label missing launch/test functionality. If unsuccessful, offer the old Mason Kotlin adapter only as an explicit degraded option or leave the capability blocked.
4. Re-evaluate official upstream releases before every meaningful Kotlin tooling update.

Exit criterion: Kotlin LSP support is truthful and tested; DAP is either demonstrably working with a named capability boundary or explicitly reported unavailable.

### Phase 6a — Fish and Bash/POSIX shell slice

1. Add Tree-sitter `fish`, `fish_lsp`, and the four Mason-owned shell tools.
2. Configure the exact Fish root/indexing policy and retain Fish LSP as its only formatter.
3. Configure BashLS only for `bash`/`sh`, preserve its non-recursive glob, disable its formatter, and route saves through Conform/`shfmt` while BashLS owns ShellCheck diagnostics.
4. Add Fish and Bash/POSIX fixture coverage, including the home-directory scan guard and an assertion that Zsh has no BashLS client.

Exit criterion: Fish and Bash/POSIX scripts have their stated LSP/format/diagnostic surfaces with one owner per capability, no home-directory scan, and no accidental Zsh attachment.

### Phase 7 — Cross-platform and operational polish

1. Run the full fast suite and opt-in integration matrix on macOS arm64 and Linux x86_64.
2. Measure cold install, startup, index/caches, CPU, memory, and disk costs.
3. Document project-level TypeScript, Python, Cargo, Java/Kotlin build, and launch-file prerequisites.
4. Keep every language slice independently revertible.

## Risks and tradeoffs

- **Kotlin maturity:** Official Kotlin LSP is alpha, JVM-first, partially closed source, large, and rapidly moving. Android remains experimental, KMP unsupported, and DAP undocumented/attach-only. This is an upstream capability ceiling, not a configuration bug.
- **TypeScript transition:** TypeScript 7 is newly stable and has no 7.0 API. Ordinary projects benefit from its native LSP, but embedded languages and language-service plugins require a TypeScript 6 route until the ecosystem migrates. The current nvim-lspconfig lock predates `tsc` and must move first.
- **basedpyright provenance:** It maximizes generic-client capability but is a community fork. Pin/observe it, retain a documented Pyright rollback, and validate behavior against real projects.
- **Extension maintenance:** rustaceanvim and nvim-jdtls add plugin surface, but they are narrowly justified by non-standard server functionality and target/test/debug discovery. Avoid comparable wrappers where native nvim-dap is enough.
- **Moving Mason artifacts:** Current named installs float. A clean install can receive a newer server than an existing machine. Health output, fixture tests, the Neovim plugin lock, and deliberate registry updates are necessary; raw artifact paths must not be copied into config.
- **Toolchain skew:** A Mason rust-analyzer may encounter an old project Rust toolchain; JDT LS runs on 21 while projects use other JDKs; Kotlin LSP bundles JBR 25; TypeScript must be project-local. Make both server and project runtime visible when diagnosing failures.
- **Resource cost:** workspace Python diagnostics, Rust Clippy, JDT/Kotlin indexes, TypeScript workers, and isolated Cargo targets consume CPU, RAM, disk, or all three. Measure large projects and expose project-specific reductions instead of weakening global fidelity preemptively.
- **Root mistakes:** roots that are too broad index unrelated projects and collide state; roots that are too narrow lose cross-module navigation. Same-basename worktrees are a mandatory regression case.
- **Launch-file portability:** nvim-dap is not the VS Code extension host. Extension-specific command substitutions, input providers, and JSON-with-comments behavior may not transfer. Keep portable data in launch files and implement only small documented substitutions.
- **Security:** Debug adapters execute project code. Attach listeners on non-loopback interfaces, remote browser endpoints, and downloaded project scripts require workspace trust and network care. Defaults should bind locally and never auto-run a project just because a file opened.
- **Platform constraints:** CodeLLDB may need OS debugging permissions; Chromium paths differ; Mason artifacts are architecture-specific. The current [Kotlin LSP Mason recipe](https://raw.githubusercontent.com/mason-org/mason-registry/main/packages/kotlin-lsp/package.yaml) contains a malformed template token in its Linux ARM64 binary path, so that platform must remain a known install blocker until the registry recipe is corrected and exercised; do not claim portability from the existence of an upstream archive alone.
- **Mixed-language limits:** Java and Kotlin servers can share a Gradle/Maven build root while owning different buffers, but cross-language rename/navigation quality is server-specific. A fixture is the only credible acceptance proof.

## Final assessment

High-fidelity LSP plus DAP is achievable now for Rust, Java, Python, and ordinary Node/browser TypeScript/JavaScript without abandoning this repository's native-first design. The largest architectural work is project context and debug routing, not UI. TypeScript 7's first-party native LSP is the most important current-source change: retaining `ts_ls` as the default would build the new system around a compatibility path that is already legacy.

Kotlin LSP can reach a useful, high-fidelity JVM editing experience, but “full Kotlin DAP” cannot honestly be promised on 2026-08-13. Treat the official JetBrains adapter as a bounded pilot and the old packaged adapter as a degraded fallback, with KMP/Native and stable Android support explicitly outside the achieved state. That transparent boundary is preferable to installing more overlapping tools and calling the gap solved.
