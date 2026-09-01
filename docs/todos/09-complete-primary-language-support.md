# Complete the Primary Neovim Language-Support Plan

## Outcome

Finish the remaining work in the primary Neovim LSP/DAP plan so Rust, Java,
Kotlin, Python, TypeScript/JavaScript, Fish, and Bash/POSIX `sh` have truthful,
project-aware support with one owner per capability and evidence from real
language-server or debugger sessions. Kotlin is the next new language slice;
the previously landed slices still need acceptance work before the plan can be
retired.

## Context / current state

The source plan is [`docs/lsp-dap-research.md`](../lsp-dap-research.md). A
2026-09-01 audit of the plan, recent language commits, the production
configuration, installed tools, and tests found that implementation has reached
Phase 6 even though earlier exit criteria remain open:

- Rust uses rustaceanvim, rust-analyzer, `rust-src`, and CodeLLDB, but lacks the
  planned project feature-override mechanism and real multi-crate LSP/DAP
  acceptance.
- Python uses BasedPyright, Ruff, and debugpy, but its resolved project
  interpreter is not yet one shared LSP/DAP decision and selection, subprocess,
  attach, and multi-package scenarios are unverified.
- Java uses nvim-jdtls with isolated workspace data and Mason debug/test bundles,
  but configured project runtimes, shared completion capabilities, stable server
  path resolution, and real Gradle/Maven/test/debug scenarios remain open.
- TypeScript/JavaScript has mutually exclusive project-local routing and the
  js-debug adapter, but source-mapped Node, browser, worker, child-process, and
  Deno scenarios still need live verification.
- Fish and Bash/POSIX `sh` have their intended servers, formatters, and diagnostic
  ownership in configuration, but only inventory-level tests cover them.
- Kotlin still has generic `kotlin_lsp` enablement plus ktlint. It has no
  language-specific root/lifecycle adapter, explicit LSP-formatting suppression,
  build fixtures, health visibility, or verified DAP boundary.

The existing language specs and installer integration suite pass, but most
language checks use stubs or static inventory assertions rather than attaching
real servers or driving a DAP protocol session. Phase 0's acceptance matrix and
performance baselines were never recorded. Phase 1's project context and
root-aware launch provider landed, while language health output, richer
breakpoint controls, and strict project-launch fallback behavior did not.

The audit also found repository-contract regressions that should be
closed with the plan: nvim-dap-ui's former ASCII control icons were lost, the
equal-priority ESLint root-marker rationale was dropped, the Neovim dependency
inventory omits `rust-src`, and the current language tree has Stylua
drift. The plan's current-state table itself is stale and should not be treated
as an implementation record until reconciled.

Related active items remain separate. The [runtime test harness](01-neovim-runtime-test-harness.md)
owns extraction of the general fake-Neovim seam. The [unified language actions](06-unify-neovim-language-actions.md)
item owns the eventual user-facing run/test/debug target selector. [OCaml and
OxCaml](03-ocaml-and-oxcaml.md) are a later language expansion outside the
primary plan.

## Scope and resume order

1. Close the shared foundation and make acceptance executable:
   - reconcile the plan's current-state and phase-status text with the code;
   - turn the promised capability, root, ownership, and platform expectations
     into an acceptance matrix;
   - record the pre-change startup time, resident memory, indexing time,
     diagnostic latency, and formatter/linter output required by Phase 0;
   - add reusable real-LSP and DAP fixture support without duplicating or
     pre-empting the general runtime-harness TODO;
   - cover nested projects, symlinks, unrelated modules in one repository, and
     two same-basename worktrees without changing global `cwd`;
   - expose roots, attached clients, commands, project runtimes, Mason packages,
     adapter executables, and server data/cache paths through health output;
   - add conditional/log/hit-count/exception breakpoint controls where supported
     while preserving lazy DAP loading;
   - make generated debugger defaults available only when no compatible project
     launch configuration exists; and
   - restore ASCII debugger controls, the ESLint marker rationale, `rust-src`
     documentation, and clean formatting.
2. Use Rust as the first end-to-end acceptance tracer. Exercise a multi-crate
   workspace, proc macro/build script, dependency source navigation, mutually
   exclusive feature sets, measured Clippy behavior, project overrides, and
   CodeLLDB binary/test debugging.
3. Implement the Kotlin Phase 6 slice against freshly checked upstream evidence:
   - harden Gradle/Maven root selection and official launcher discovery;
   - keep ktlint/Conform as the sole formatting owner by disabling Kotlin LSP
     formatting if the server advertises it;
   - expose the selected root, launcher/JBR, package version, and cache path;
   - verify Gradle, Maven, nested-build, and mixed Java/Kotlin fixtures; and
   - run a bounded official DAP attach pilot, then either ship its demonstrated
     surface, offer the legacy Mason Kotlin adapter as an explicitly degraded
     option, or report debugging unavailable with an explicit capability
     boundary. Recheck the known Mason Linux ARM64 recipe blocker before making
     a portability claim.
4. Reuse the same acceptance seam to close the remaining landed slices:
   - Python: one interpreter decision for LSP and DAP, uv/`.venv` and
     multi-package roots, nearest class/method/selection tests, subprocess, and
     attach;
   - Java: Mason-resolved server/bundles, project runtime visibility, shared LSP
     capabilities, Gradle and Maven multi-module projects, main, JUnit/TestNG,
     attach, and same-basename isolation;
   - TypeScript/JavaScript: exact project compiler provenance, Node launch/attach
     and child processes, source-mapped TypeScript, Chromium bundles/workers,
     and Deno exclusion/routing;
   - Fish: cross-file navigation/rename, diagnostics, and one formatting edit
     across config, function, and completion fixtures; and
   - Bash/POSIX `sh`: sourced siblings, ShellCheck, `.editorconfig`-driven shfmt,
     a standalone home-directory script with no recursive scan, and no BashLS
     attachment to Zsh.
5. Complete Phase 7 on macOS arm64 and Linux x86_64. Record cold install,
   startup, indexing/cache, CPU, memory, and disk observations; document project
   prerequisites and environmental skips; and leave each language slice
   independently reviewable and revertible.

## Boundaries / non-goals

- Keep the primary scope to Rust, Java, Kotlin, Python, TypeScript/JavaScript,
  Fish, and Bash/POSIX `sh`. Zsh language-server support remains deliberately
  excluded.
- Keep Kotlin support to JVM projects using supported Gradle or Maven layouts.
  Kotlin Multiplatform/Native and stable Android support remain outside the
  achieved scope unless freshly checked upstream evidence justifies a separately
  reviewed expansion.
- Do not fold OCaml/OxCaml into this item or begin it as a substitute for closing
  the primary plan.
- Do not solve the unified target-selection interface here beyond the shared DAP
  controls and per-language setup required by this plan.
- Do not rewrite the general Neovim runtime test harness inside the language
  work. Reuse its interface if available; otherwise keep language fixtures
  narrow enough to migrate later.
- Do not enable overlapping semantic servers, formatters, diagnostics, or debug
  wrappers for the same capability.
- Do not install project TypeScript, Python environments, Cargo settings, or
  Java/Kotlin build toolchains as global dotfiles dependencies.
- Do not hardcode Mason, Homebrew, JDK, virtual-environment, or user-specific
  paths. Resolve owned artifacts through their owning APIs or project context.
- Do not describe experimental Kotlin debugging, browser automation, or an
  architecture-specific package as supported without a successful fixture or an
  explicit environment skip.
- Keep language work separate from unrelated workflow, installer, terminal, or
  UI changes so review and rollback remain meaningful.

## Open decisions

- What is the smallest real-process fixture interface that can serve all language
  checks and later compose with the general runtime harness?
- How should Rust projects declare non-default rust-analyzer feature profiles
  without returning to a global all-features policy?
- Which supported BasedPyright setting or client notification should share the
  resolved project interpreter with debugpy without fighting server discovery?
- How should JDT LS learn configured project JDK runtimes without hardcoded
  machine paths or overriding Gradle/Maven toolchains?
- Does the current official Kotlin package provide a stable enough attach surface
  to ship? If it does not, is the legacy adapter reliable enough for an explicit
  degraded option, or should health/documentation report debugging unavailable?
- Which browser, OS-debugger, and architecture scenarios belong in the normal
  suite versus an opt-in matrix with explicit environment skips?
- What baseline measurements are stable enough to catch material regressions
  without turning machine variance into false failures?

## Acceptance criteria

- The plan and maintained Neovim documentation accurately distinguish completed
  implementation from remaining acceptance work.
- A checked-in acceptance matrix names the supported LSP, formatting,
  diagnostics, project-root, runtime, and DAP behavior for every primary
  language.
- Each primary language attaches exactly one intended semantic client per
  project and has one formatting and diagnostic owner for each filetype.
- Real-server fixtures prove roots, tool provenance, negotiated capabilities,
  navigation/refactoring, diagnostics, and formatting across the stated project
  shapes; tests do not claim these outcomes from inventory assertions alone.
- Supported Rust, Java, Python, Node/browser, and conditional Kotlin DAP surfaces
  complete deterministic protocol smoke tests. A legacy Kotlin adapter is labeled
  degraded, and unsupported Kotlin behavior is reported explicitly rather than
  emulated silently.
- Project launch files and generated defaults select the active buffer's
  canonical project without crossing same-basename worktrees or mutating global
  `cwd`.
- Health output identifies the active root, client/server command, project
  runtime or compiler, adapter, and relevant cache/data path well enough to
  diagnose skew or a missing artifact.
- Fish and Bash/POSIX `sh` meet their navigation, formatting, diagnostic, and
  scan-boundary claims, and Zsh never receives BashLS.
- The configuration remains usable without a Nerd Font; dependency inventories
  agree; Lua formatting and the repository's existing tests are green.
- The supported matrix is exercised on macOS arm64 and Linux x86_64, with
  environment limitations reported as skips rather than language failures.
- Startup, indexing/cache, CPU, memory, disk, and install observations are
  recorded, and project prerequisites are documented.

## Verification

Run each narrow language spec while iterating, then the full current language
suite:

```sh
for spec in nvim/tests/languages/*_spec.lua; do
  nvim --clean --headless -l "$spec"
done
```

Run the new real-LSP fixture suite and opt-in DAP matrix through the commands
introduced with their harness. For every fixture, assert the executable,
canonical root, project-local runtime/compiler where applicable, client count,
capabilities, and at least one meaningful cross-file operation. Drive supported
DAP adapters through initialized, stopped, stack/thread/scope/variable/evaluate,
continued, and terminated events.

Also run:

```sh
stylua --check nvim/lua/custom/languages nvim/tests/languages
nvim --headless '+qa'
git diff --check
```

Use `:checkhealth vim.lsp`, the language-specific health output, Mason status,
and an interactive manual pass for discoverability, launch selection, source
maps, evaluation, restart/terminate, and missing-tool messages. Run
`tests/install_test.sh` whenever the installer, Mise manifest, Mason inventory,
or dependency documentation changes. Exercise the final supported matrix on
both required platforms.

## Starting points / references

- [`docs/lsp-dap-research.md`](../lsp-dap-research.md) — source decisions,
  capability expectations, fixture designs, phased plan, and risks.
- [`nvim/lua/custom/languages/config.lua`](../../nvim/lua/custom/languages/config.lua)
  — language, Mason, formatter, linter, and DAP inventory.
- [`nvim/lua/custom/languages/context.lua`](../../nvim/lua/custom/languages/context.lua)
  — active-buffer project context.
- [`nvim/lua/custom/languages/dap.lua`](../../nvim/lua/custom/languages/dap.lua)
  — shared lazy DAP lifecycle and project launch provider.
- [`nvim/lua/custom/languages/adapters/`](../../nvim/lua/custom/languages/adapters/)
  — current Rust, Java, Python, and JavaScript/TypeScript ownership adapters.
- [`nvim/tests/languages/`](../../nvim/tests/languages/) — current static and
  stubbed language checks to preserve and deepen.
- [`docs/neovim-typescript-javascript-best-practices.md`](../neovim-typescript-javascript-best-practices.md)
  — implemented TypeScript/JavaScript decisions and remaining live checks.
- [`nvim/AGENTS.md`](../../nvim/AGENTS.md) — language ownership, dependency,
  documentation, testing, and no-Nerd-Font contracts.
- [Official Kotlin LSP README](https://github.com/Kotlin/kotlin-lsp/blob/main/README.md),
  [release notes](https://github.com/Kotlin/kotlin-lsp/blob/main/RELEASES.md), and
  [Mason recipe](https://github.com/mason-org/mason-registry/blob/main/packages/kotlin-lsp/package.yaml)
  — time-sensitive evidence to recheck before implementing Kotlin.
