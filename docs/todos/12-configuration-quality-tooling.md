# Establish Shared Configuration Quality Tooling

## Outcome

Provide consistent commands for typechecking, linting, formatting, native
configuration validation, and testing across the dotfiles repository. Use each
configuration's appropriate tools, with clear coverage, prerequisites, results,
and limitations. Put all tracked tests, fixtures, and test helpers under the
repository's top-level `tests/` directory.

## Agreed scope and open design

The user requested discussion before implementation, then asked to retain the
work as a TODO with linked research. The confirmed requirements are:

- Cover all configurations using each tool's native checks where available.
- Consolidate all tracked test code under top-level `tests/`, including the
  current `nvim/tests/` tree and tests in any other application directory.
- Preserve the repository's Lua-and-shell automation policy and documented
  exceptions for native formats and focused language fixtures.

No task runner, replacement test framework, new dependency, command naming
scheme, or CI integration has been selected. The research below is a starting
point for those decisions, not approval of a particular implementation.

## Current evidence

Inspected on 2026-11-01 at `a924e88de1fe5def9ac699ad1380767c58812475`.
Recheck the current tree before implementation.

- There is no tracked repository-wide Makefile, Mise task setup, Justfile, or
  Taskfile. Validation commands are spread across the root and tool guides.
- [`nvim/tests/diagnostics.lua`](../../nvim/tests/diagnostics.lua) invokes the
  installed Lua language server through Hint severity for both the Neovim
  workspace and repository-level Lua tests. [`tests/.luarc.json`](../../tests/.luarc.json)
  provides the latter's LuaJIT and Neovim library settings.
- [`nvim/.stylua.toml`](../../nvim/.stylua.toml) owns the Lua formatting policy.
  A shared command must also apply that policy to Lua outside `nvim/` and keep
  editor discovery working through the installed Neovim configuration symlink.
- The 24 Lua `*_spec.lua` harnesses currently run as separate
  `nvim --clean --headless -l` processes. Some use focused stubs; installed-plugin
  and real-terminal regressions cover selected runtime behavior separately.
- Root-level [`tests/install_test.sh`](../../tests/install_test.sh),
  [`tests/shell_test.lua`](../../tests/shell_test.lua), and
  [`tests/nvim_performance_test.sh`](../../tests/nvim_performance_test.sh) already
  exist. Test discovery must include the performance harness rather than
  treating the Neovim spec glob as the entire repository suite.
- Type annotations exist on some module interfaces, but other structured
  arguments and results use inferred tables or broad `table` types. Clean
  diagnostics alone do not establish complete type coverage. Test code that
  replaces `_G.vim` also needs deliberate static-analysis scoping so fake
  definitions do not become the production API model. This is a design concern
  from source inspection, not a newly reproduced defect.
- Recent validation passed the installer suite, 24 Lua specs, LuaLS diagnostics,
  shell regressions, and the real-PTY Hunk suite. It used installed dependencies:
  installed `nvim-lspconfig` was `77b7432`, while the new lockfile selected
  `3bccb6f`. The new upstream source was inspected, but that installation was
  not provisioned for those tests. Shared tooling should make this distinction
  visible instead of implying that a lockfile proves which version ran.

The existing [runtime-harness TODO](01-neovim-runtime-test-harness.md) owns
extraction of the fake Neovim runtime and safe restoration of globals and module
state. Coordinate path changes with it; shared commands and test relocation do
not require that separate architectural refactor to be completed first.

## Configuration coverage to establish

This inventory records existing repository guidance, not newly executed checks
or a claim that every application has a safe standalone validator.

| Configuration family | Existing foundation and remaining investigation |
| --- | --- |
| Lua and Neovim | LuaLS, StyLua, isolated Lua specs, installed-plugin tests, and real-PTY Hunk tests; strengthen interface annotations and unify editor/CLI settings. |
| Bash/POSIX shell | Mason-owned ShellCheck and shfmt, syntax checks, installer and performance harnesses; define tracked-file coverage and shell dialects. |
| Fish | `fish -n` and `fish_indent` are documented; real-shell integration tests already exist. |
| Zsh | Native shell parsing and real-shell integration tests; do not treat ShellCheck's Bash/sh analysis as Zsh support. Verify formatter dialect support in the installed version. |
| Herdr | [`herdr/AGENTS.md`](../../herdr/AGENTS.md) documents `herdr config check`; confirm how to target the checkout's file independently of live/user configuration. Reload is a separate mutation. |
| tmux | [`tmux/AGENTS.md`](../../tmux/AGENTS.md) documents a fresh server, unique socket, and harmless pane. Validation must never use or terminate the user's active server. |
| Ghostty, Hunk, and LazyGit | Investigate upstream configuration validation and file-selection options; their repository guides do not currently define standalone validation commands. Report gaps explicitly. |
| JSON, YAML, and TOML | Existing editor support can help, but syntax parsing alone does not validate an application's accepted keys or values. Prefer native validation or supported schemas and name the coverage provided. |
| Brewfile and Mise manifest | Installer fixtures already verify inventory and pins. Keep configuration validation separate from package installation or upgrade. |
| Rex | [`rex/macos.sh`](../../rex/macos.sh) changes macOS preferences. Check its shell safely; never execute it against real preferences as an automatic validation step. |
| Documentation and repository control files | Decide which link, schema, or formatting checks add useful coverage, and record exclusions rather than silently omitting these files. |

## Research and candidate approach

Primary sources below were consulted on 2026-11-01. Verify current installed
versions and documentation again when choosing commands.

### Task orchestration

Both Make and Mise fit the existing dependency inventory. Make is supplied by
the platform development tools; Mise is already installed for runtimes. Use one
shared entry point that invokes the underlying tools and existing harnesses.
Keep test execution and check reporting independent of Git review/approval
policy; this is not a replacement agent workflow executable.

- [GNU Make's phony targets](https://www.gnu.org/software/make/manual/html_node/Phony-Targets.html)
  express commands such as checks and tests without pretending they produce
  build artifacts. A small Makefile is a conventional option with little
  environment management. Account for the Make versions shipped on supported
  hosts before depending on newer syntax.
- [Mise task execution](https://mise.jdx.dev/tasks/running-tasks.html) provides
  task dependencies, parallel execution, timeouts, discovery, and dry runs.
  It also loads tools and environment and can install missing tools; its
  `--skip-tools` option disables that installation step. Decide this behavior
  explicitly so verification does not silently provision the machine.
- [Mise task discovery](https://mise.jdx.dev/tasks/task-discovery.html) supports
  TOML tasks and executable shell file tasks. If selected, keep repository tasks
  project-local and separate from the globally linked
  [`mise/conf.d/00-dotfiles.toml`](../../mise/conf.d/00-dotfiles.toml) runtime defaults.

Working recommendation: consolidate invocation, prerequisite checks, temporary
environment setup, and reporting before writing a custom runner or replacing
existing tests. Choose between Make and Mise after agreeing the command
interface and environment contract. Neither has been selected.

### Lua typechecking, linting, and formatting

[LuaLS type checking](https://luals.github.io/wiki/type-checking/) uses inference
and annotations to report likely type errors; it does not provide a complete
TypeScript-style type system. The most direct improvement is to describe module
inputs, return values, and shared configuration tables accurately using
[annotations](https://luals.github.io/wiki/annotations/). Avoid broad casts or
global diagnostic suppression merely to obtain a clean result.

Start from the existing LuaLS diagnostics for both type and lint feedback.
Evaluate another Lua linter only against a concrete useful rule or failure that
the existing checks miss. Luacheck and Selene remain possible follow-up research,
not validated selections from this investigation.

[LuaLS configuration](https://luals.github.io/wiki/configuration/) recommends
workspace `.luarc.json` files and gives `--configpath` precedence over workspace
and client settings. Keep editor and command-line analysis consistent. Moving
tests changes workspace discovery and relative library/module paths; verify
those explicitly, including how fake Neovim globals are kept from polluting
runtime definitions.

[StyLua](https://github.com/JohnnyMorganz/StyLua) supplies a read-only `--check`
mode and an optional `--verify` pass that reparses formatted output. Its own
documentation says verification can have false positives and negatives, so
formatting does not replace behavior tests. Reuse one deliberate Lua style
across the editor and shared commands.

### Other formats and execution tests

[ShellCheck](https://github.com/koalaman/shellcheck) targets Bash/sh problems,
while [shfmt](https://github.com/mvdan/sh) handles shell formatting. Current
shfmt upstream documents Zsh support as well; confirm that support in the
installed release before assigning Zsh files to it. Fish has its own
[formatter and check-only mode](https://fishshell.com/docs/current/cmds/fish_indent.html).
Do not route every shell dialect through the same parser merely because files
look similar.

Keep existing real Neovim, shell, installer, and terminal-process tests. Shared
commands can improve discovery, isolation, logs, and failure reporting without
requiring a wholesale migration to another assertion framework. Separate quick
static checks from process-launching integration tests and host-specific checks.

## Scope and boundaries

- Inventory all tracked configurations and tests, including extensionless and
  hidden files. Define inclusion, platform applicability, and exclusions.
- Move all tracked tests, fixtures, and test helpers into top-level `tests/`.
  Application-specific subdirectories within that tree are compatible with this
  requirement; the exact layout remains open. Generated temporary fixtures still
  belong in scratch directories rather than the working tree.
- Preserve behavior and coverage during relocation. Update root discovery,
  module/runtime paths, LuaLS workspace settings, fixture references, shell
  launch commands, documentation, and related active TODO links together.
- Keep each existing prerequisite owner: Homebrew for applications, Mise for
  runtimes, Neovim/Mason for editor tools. Do not install duplicate copies merely
  to put a formatter or linter on the task runner's PATH.
- Make check-only formatting and explicit rewrite operations distinguishable.
  Verification must not rewrite configuration, reload live applications, install
  packages, or modify personal state as an incidental side effect.
- Preserve per-process isolation and real-runtime checks. Do not claim simulated
  Linux fixtures are native Linux acceptance, or syntax checks are application
  behavior tests.
- Keep test relocation, task orchestration, annotation improvements, and any
  newly reproduced product defects independently understandable in review.
- Do not bundle new language support, application preference changes, a large
  formatter rewrite, a new test framework, or CI/hook installation without a
  separate decision. No tooling implementation is part of recording this brief.

## Open decisions

- Make or project-local Mise tasks? What environment must each command inherit
  or isolate, and how should missing or mismatched installed tools be handled?
- What is the directory layout under `tests/`, and how are shared helpers and
  application-specific fixtures discovered without coupling them to invocation
  from one working directory?
- Which commands separate format checking, type/lint checks, native validation,
  quick tests, full integration tests, and performance checks?
- Which Lua module interfaces need stronger annotations first? How should
  production definitions and test fakes be scoped after relocation?
- Which applications offer reliable native validation of an explicit file, and
  which need schema-only checks or an isolated startup fixture?
- Which checks are required on each host, which are explicitly inapplicable,
  and which unavailable prerequisites make a selected run incomplete?
- Should CI later call these same commands, and on which OS/runtime matrix?

## Acceptance criteria

- All tracked tests, fixtures, and test helpers are under top-level `tests/`;
  old locations and maintained references have been migrated consistently.
- A documented shared interface covers the configuration inventory with explicit
  coverage and exclusions. Editor and command-line formatting/type settings agree.
- Lua checking exercises meaningful declared contracts as well as syntax, with
  scoped runtime definitions and documented exceptions.
- Existing assertions and real-process coverage remain available through the
  shared commands, including the performance harness and real-PTY Hunk suite.
- Results distinguish failures, intentional platform exclusions, and unavailable
  prerequisites. Missing required checks cannot produce an unqualified pass.
- Runs identify relevant executable versions and installed plugin revisions so
  a passing result can be attributed to the actual tested environment.
- Verification is read-only with respect to tracked files and personal state;
  tests clean up only their own fixtures, sockets, processes, and temporary data.
- Repository automation remains Lua/shell with the existing native-format and
  focused-fixture exceptions. No duplicate dependency owner is introduced.
- Root and tool documentation name the shared entry points and link to the
  authoritative ownership and validation guidance without parallel instructions.

## Verification when implemented

Inventory tests before and after relocation and compare discovery results.
Run migrated harnesses from the checkout root and another working directory,
including a checkout path with spaces or a symlink where those are supported.
Check native Lua editor discovery after the move rather than relying only on a
command-line configuration override.

Use representative temporary fixtures to show that the selected tools catch a
realistic wrong Lua argument type, a lint issue, a formatting difference, an
invalid application setting where native checking supports it, and a failing
test. Verify their exit statuses and the aggregate result. Check missing-tool
reporting, platform exclusions, failure cleanup, and unchanged tracked files and
personal state. Do not construct impossible application or environment states
to justify implementation changes.

Run the full migrated installer, shell, Neovim Lua, diagnostics, performance,
and Hunk PTY suites plus the selected native configuration checks. Record which
platforms and installed versions actually ran. Use the existing
[dependency inventory](../../README.md#dependency-ownership),
[Neovim constraints](../../nvim/AGENTS.md), and
[TODO lifecycle](README.md#lifecycle) as the maintenance owners.
