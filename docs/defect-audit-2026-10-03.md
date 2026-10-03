# Dotfiles defect audit and implementation direction

This document records the October 3, 2026 codebase audit, the user's direction,
and the progress of the resulting fixes. It is maintained as implementation
and validation proceed. Usage remains in tool READMEs, dependency ownership in
the root README, and agent constraints in AGENTS files.

The audit examined `/Users/desaidn/dotfiles` on `main` at
`ca21dc14b23bd18d109cf17763b6df86e2c74ef9`. Implementation uses the same checkout
on `wip/audit-defect-fixes`, starting at that commit. This is a research and work
record, not a review-approval record; exact review identity and approval remain
in the conversation under the [development workflow](agents/development-workflow.md).

## Agreed direction

The user requested bugs, defects, simplification opportunities, and documentation
corrections, then directed: "Fix all defects and update the documentation.
Don't remove any of the dependencies, I need them." The user subsequently
required this document to be written first and continually updated.

- Fix the four concrete code defects below and the identified documentation
  errors. Preserve existing intentional behavior and explicit user settings.
- Retain every existing dependency, provisioning requirement, plugin, and
  runtime pin. None of the dependency-removal proposals below is authorized.
- Add focused regressions for the actual failure paths, run the required
  validation, and present the committed changes through the existing Hunk
  review workflow. Landing requires approval of the exact snapshot and an
  explicitly selected existing local target branch.
- Keep this document current with evidence, implementation decisions, validation
  results, and remaining work. Do not create a parallel issue queue or replace
  the existing TODO briefs.

## Code defects and evidence

### Backup restoration can move a backup into a new directory

At the audited revision, [uninstall.sh](../uninstall.sh)'s `move_backup` checks
that the destination is absent and then runs `mv -n`. If a directory appears at
the destination between those operations, `mv` moves the backup inside it. The
function checks only that the original backup path disappeared, so callers
report a successful restoration at the wrong location.

An isolated temporary-directory probe using the extracted production function
injected directory creation immediately before native `mv`. It returned zero,
left the backup inside the new directory, and consumed the original backup
pathname. No production installation was exercised.

Required outcome: restoration must target one exact pathname, preserve competing
user state, and never report success for a backup nested inside a directory.
Portability must remain compatible with the supported macOS and Linux systems.

Status: implemented; the full installer integration suite passed. Native command
research found that GNU `mv -T` prevents directory nesting, but macOS `mv` has
no equivalent; its `-n` implementation also checks before renaming. See the
[GNU target-directory documentation](https://www.gnu.org/software/coreutils/manual/html_node/Target-directory.html)
and [Apple mv source](https://github.com/apple-oss-distributions/file_cmds/blob/main/mv/mv.c).
The selected direction is a small temporary native helper, embedded in the
self-contained uninstaller, using the already-required platform C compiler and
exclusive-rename operation: `renamex_np(..., RENAME_EXCL)` on macOS and
`renameat2(..., RENAME_NOREPLACE)` on Linux. See the
[Apple exclusive-renaming capability](https://developer.apple.com/documentation/foundation/urlresourcevalues/volumesupportsexclusiverenaming)
and [Linux rename manual](https://man7.org/linux/man-pages/man2/renameat2.2.html).
Compilation succeeds before any `--restore` configuration mutation; ordinary
uninstall does not compile anything. No new package or installed executable is
introduced. Twelve race cases now pass: direct directory, nested file, and
parent symlink backups, each racing against a new directory, file, live symlink,
or dangling symlink. Missing/broken compiler checks preserve all managed links
and backups, and temporary-helper cleanup passes.

The native helper has executed on macOS. Linux installer fixtures still execute
on the macOS host, so they do not validate the Linux syscall branch. No running
Linux environment was available (the installed Docker daemon was stopped).
This limitation remains explicit rather than treating simulated Linux bootstrap
coverage as a real Linux run.
The destination filesystem must support the native exclusive-rename operation;
an unsupported operation preserves the backup and reports failure. There is no
copy-and-remove fallback. The existing recovery path attempts to restore an
owned link only if its destination remains unoccupied.

### Python debugging can load another project's environment file

[python.lua](../nvim/lua/custom/languages/adapters/python.lua) prepares a project
interpreter but does not resolve omitted or relative `envFile` paths. The locked
[nvim-dap-python implementation](https://github.com/mfussenegger/nvim-dap-python/blob/1808458eba2b18f178f990e01376941a42c7f93b/lua/dap-python.lua#L153-L162)
resolves `config.envFile or './.env'` against Neovim's working directory,
independently of the launch configuration's `cwd`.

A read-only probe loaded the installed plugin at the exact locked revision,
intercepted `io.open`, and enriched a launch with `cwd=/project-A`. The attempted
default environment file was `/Users/desaidn/dotfiles/.env`, the editor's current
directory. It read no project/environment file and launched no debugger.

Required outcome: resolve environment-file paths from the selected project before
asynchronous debugger enrichment, preserving explicit absolute paths and
workspace-variable expansion. Cover project launches, generated defaults, and
test launches without temporarily changing the user's editor directory.

Status: implemented and focused regressions pass. The debugger configuration provider receives
the initiating buffer before asynchronous selection, so that is where project
context must be captured. The Python adapter reuses the shared provider's
existing variable-freezing behavior through a small helper rather than duplicate
it. Python's native runtime checks cover omitted, relative, absolute,
`${workspaceFolder}`, `${env:...}`, and deferred `${input:...}` environment-file
paths, explicit interpreter/cwd/env values, and class/method launches including
nested test roots. Deferred input and callable environment paths are evaluated
once even when selection changes the current buffer. Relative paths intentionally
use the source project root independently of an explicit launch `cwd`; test
actions use the selected test root. Other languages' global configurations are
left unchanged.

The implementation invokes nvim-dap's existing `dap.expand_variable` listener
for deferred environment-file values. This is an upstream implementation key,
verified in the locked plugin and current source, and guarded by the native
runtime regression. Recheck that integration when updating nvim-dap.

### Generated Python file launches omit the project working directory

The same adapter adds `pythonPath` to nvim-dap-python's generated `file`,
`file:args`, and `file:doctest` configurations but leaves `cwd` unset. The
[locked defaults](https://github.com/mfussenegger/nvim-dap-python/blob/1808458eba2b18f178f990e01376941a42c7f93b/lua/dap-python.lua#L314-L357)
also omit it. The shared project's `launch.json` provider does not transform
those generated configurations. Opening a file in project A from an editor
started in B can therefore combine A's interpreter with B's working directory.

Required outcome: generated launches must capture the source project's context,
while preserving explicit configuration values. Test launches already choose a
source-derived working directory; retain their nested-test-root behavior.

Status: implemented with the Python environment-file fix. All three generated
file-launch defaults now pass the source-directory and interpreter assertions
after switching to an unrelated buffer before enrichment. Defaults are copied
per launch so later projects resolve their own context. All 23 Lua harnesses
and Lua diagnostics passed that implementation. Final review then reproduced
one additional instance of the same context defect: a callable `envFile` that
returns `${workspaceFolder}/config/debug.env` was expanded against the later
editor context. The shared source-variable replacement now freezes function
results lazily before native expansion. Focused regressions pass for this case,
native coroutine paths, and the unchanged identity of `dap.ABORT`; callbacks
remain deferred and run once.

The committed-change review identified a related asynchronous case: a callback
can return a coroutine whose resumed value contains `${workspaceFolder}`. The
initial coroutine test covered relative paths only; native expansion could still
resolve a workspace placeholder against the later editor context. This finding
was recorded in the visible review before closing it for correction. The new
regression fails against that snapshot. Direct coroutine-valued settings, also
supported by native DAP, additionally fail in the preparation helper's redundant
`vim.deepcopy` call. The selected correction keeps copying in the existing
recursive variable-replacement helper and uses nvim-dap's scheduled resume/yield
protocol to substitute source variables in completed coroutine values before
native expansion. Focused regressions now pass for direct and function-returned
coroutines completing synchronously, through the event loop, and through a
libuv fast event. They verify once-only execution, cancellation through
`dap.ABORT`, prompt errors for dead or failed threads, and preservation of the
original configuration tables and metatables. All 23 harnesses and Lua
diagnostics pass after this correction.

### Neo-tree path copying only handles the filesystem source

[neo-tree.lua](../nvim/lua/kickstart/plugins/neo-tree.lua) installs selected-node
path-copy mappings under `filesystem.window.mappings`. The enabled buffers and
Git-status sources instead inherit global mappings that expand the synthetic
Neo-tree buffer name. The README advertises selected-file copying without this
restriction.

Source inspection of the production mappings and the pinned Neo-tree renderer
established the failure path; interactive reproduction was not performed during
the read-only audit.

Required outcome: absolute and root-relative copying must consistently use the
selected file or directory in all enabled sources, and handle virtual grouping
nodes without copying synthetic buffer names.

Status: implemented and focused regressions pass. The four existing Neo-tree
checks passed before the fix; the three new buffers, Git-status, and grouping-node
checks failed because the copy mappings were missing from those sources. Shared
source-window mappings now handle real file, directory, and link nodes without
requiring those paths to exist (Git status can include deleted files). Relative
copying uses the displayed source root and copies `.` for the root itself.
Virtual nodes and paths outside the relative-copy root notify and preserve the
clipboard. All seven checks pass against the locked real plugin, including
the existing deliberately injected watcher-failure case. The full suite and
Lua diagnostics also pass this implementation.

## Documentation corrections

| Owner | Correction | Status |
| --- | --- | --- |
| [tmux guidance](../tmux/AGENTS.md) | Replace the shared-server syntax check, which may skip reading `-f`, with isolated validation. Remove unscoped `kill-server` from routine testing guidance. The [tmux manual](https://github.com/tmux/tmux/blob/master/tmux.1) documents startup-only config loading and destruction of all sessions by `kill-server`. | Updated; documented command passed on an isolated server |
| [Neovim usage](../nvim/README.md) | Document Neo-tree's actual `<` and `>` source-switching keys rather than `<Tab>`, and clarify path-copy behavior after the fix. [Pinned defaults](https://github.com/nvim-neo-tree/neo-tree.nvim/blob/83e7a2982fd12b9c3d35bc39dd5877cd91a02a61/lua/neo-tree/defaults.lua). | Updated |
| [Neovim usage and constraints](../nvim/AGENTS.md) | Identify Java's FileType DAP initialization alongside Rust's attachment-time exception, and describe the corrected Python launch context. | Updated |
| [Dependency research](dependency-research.md) | Correct the claim that a Brew receipt alone satisfies font validation. The installer requires a matching font file. | Updated |
| [Dependency research](dependency-research.md) | Reconcile the omitted CMake/Ninja entries and narrow the native-toolchain ownership wording. Link the root inventory rather than maintaining another supposedly complete package list. | Updated |
| [Neovim bootstrap comment](../nvim/init.lua) | Attribute parser update hooks to `custom/languages/treesitter.lua`, not `custom/lib/pack.lua`. | Updated |
| [Language research](lsp-dap-research.md) | Distinguish historical observations from current behavior and link maintained usage. This documentation drift is already tracked in [primary language support](todos/09-complete-primary-language-support.md); preserve its remaining work. | Historical scope clarified; broader acceptance work remains tracked |

## Dependency proposals considered and retained

These were discussion options, not defects. The user needs the dependencies and
has directed that all remain. This audit does not authorize their removal or a
replacement implementation.

| Proposal considered | Evidence and tradeoff | Direction |
| --- | --- | --- |
| Choose one Prettier runner | Adapters provision `prettierd` and `prettier` and prefer the first available. [Prettierd](https://github.com/fsouza/prettierd) provides daemon-based speed; the separate executable is an availability fallback. | Retain both. |
| Replace nvim-autopairs with mini.pairs | The complete mini.nvim library is already installed; [mini.pairs](https://github.com/nvim-mini/mini.pairs) provides basic pairing but differs in typing behavior. | Retain nvim-autopairs and mini.nvim. |
| Consolidate FFF and Telescope | [Telescope](https://github.com/nvim-telescope/telescope.nvim) can perform ordinary file/grep search; [FFF](https://github.com/dmtrKovalenko/fff) adds indexing, frequency/recency ranking, and fuzzy content search, with native binary installation. | Retain both and their current responsibilities. |
| Remove telescope-fzf-native | It is an active optional accelerator, with additional [query operators](https://github.com/nvim-telescope/telescope-fzf-native.nvim/blob/b25b749b9db64d375d782094e2b9dce53ad53a40/README.md), not unused code. | Retain the plugin and build hook. |
| Omit desktop clipboard packages on headless Linux | OSC 52 supplies remote copying, while X11 and Wayland providers cover desktop sessions. Selective installation would change the explicit package policy. | Retain both providers and existing installation requirements. |

The installer/uninstaller safety guards remain self-contained as required by
project policy. Repeated link-inventory design is already an open question in
[installer upgrade tolerance](todos/07-installer-upgrade-tolerance.md). The
[runtime test harness](todos/01-neovim-runtime-test-harness.md) and
[HunkReview arguments](todos/11-hunkreview-arguments.md) also have existing briefs;
they are not new defects or part of this fix request.

## Validation and progress

The initial read-only audit performed source inspection, pinned-plugin checks,
the two probes described above, and a relative Markdown file-link check. The
link check found no missing local file targets. It did not validate anchors or
external link availability. No full suites or live debugger sessions ran then.

Implementation validation included the installer integration suite,
focused Python and Neo-tree regressions, every Lua `*_spec.lua` harness, Lua
language-server diagnostics, shell syntax checks, isolated tmux validation,
documentation-link checks, and `git diff --check`. Test environments must keep
temporary state separate from the user's running tools. Additional checks will
follow only when changed behavior or failures justify them.

| Step | Result |
| --- | --- |
| Create the research and direction document before code edits | Complete |
| Reproduce and fix the four code defects | Implemented, including the coroutine/workspace-variable combination found during review; focused regressions pass |
| Correct documentation in its existing owners | Complete |
| Run required validation and record outcomes here | Installer suite, all 23 Neovim harnesses, Lua diagnostics, tmux positive/negative checks, syntax and formatting checks pass; affected validation repeated after the asynchronous correction |

The committed snapshot, Hunk presentation, review findings, and any subsequent
approval or landing decision are recorded in the conversation under the shared
workflow. Linux native execution remains the validation gap described above.

Focused validation completed so far:

- `XDG_STATE_HOME=<temporary>/state XDG_CACHE_HOME=<temporary>/cache nvim --clean --headless -l nvim/tests/neo_tree_spec.lua`: all seven checks passed after the fix. Three new checks failed before it. The `EMFILE` message belongs to the intentional watcher-failure regression.
- The exact POSIX-shell block in `tmux/AGENTS.md`: passed against an isolated server. The sandbox initially blocked Unix-socket creation; rerunning with local execution permission succeeded without touching the user's tmux server.
- The same tmux block rejects an invalid option and an unclosed command block with exit status 1. An initial negative fixture using an unterminated quoted string was accepted by tmux's parser; it was replaced with an actual malformed command block rather than counted as a validation failure.
- With temporary `XDG_STATE_HOME`, `python_spec.lua`, `python_runtime_spec.lua`, `dap_launch_spec.lua`, and `dap_spec.lua` pass. Before the fixes, the native Python regression reported the wrong environment file and a missing source-project working directory.
- Targeted StyLua checks passed for the changed Python/DAP and Neo-tree files.
- `git diff --check`: passed.

Combined validation:

- With temporary `XDG_STATE_HOME` and `XDG_CACHE_HOME`, the documented loop
  `for spec in nvim/tests/**/*_spec.lua; do nvim --clean --headless -l "$spec" || exit 1; done`
  passed all 23 harnesses. Local run logs are in
  `/private/tmp/dotfiles-audit-nvim.mwkVfh`; this temporary path is diagnostic
  evidence, not required project state.
- `nvim --clean --headless -l nvim/tests/diagnostics.lua` initially failed with
  one nullable-path warning in Neo-tree and three test-definition diagnostics
  in `python_runtime_spec.lua` (two duplicate function assignments and a
  shadowed local). Separate variables and named callbacks corrected all four
  without diagnostic suppressions. The rerun passes through Hint severity.
- After those corrections, the complete 23-harness loop passed again. After
  the final callable workspace-variable fix, all 23 harnesses and diagnostics
  passed once more; logs are in `/private/tmp/dotfiles-audit-callback-nvim.61QUR5`.
- After correcting the coroutine cases found in review, the four focused
  Python/DAP harnesses, full Lua diagnostics, and targeted formatting checks
  passed. The final complete 23-harness rerun passed; logs are in
  `/private/tmp/dotfiles-audit-coroutine-nvim.yEDcUB`.
- `tests/install_test.sh`: full suite passed, exit 0, including all new restore
  race and compiler-failure checks plus existing macOS and simulated Linux
  provisioning, ownership, idempotence, and restoration cases.
- `bash -n install.sh uninstall.sh tests/install_test.sh`: passed.
- The Brewfile, Mise manifest, plugin lockfile, and retained search/pairing
  dependency declarations remain unchanged. Python and Neo-tree behavior fixes
  do not alter their plugin or Mason package inventories.

## Mutation testing follow-up

At the user's request, mutation tests exercised the added regressions against
independent faults in temporary exports of the committed code. The user directed
that mutations must not be committed and asked to inspect the experiment in
Herdr/Neovim. The temporary report, exact patches, logs, and reproduction runners
were opened in a separate `mutation-tests` tab; the reviewed checkout stayed
unchanged during those experiments.

All three baseline harnesses passed. The unchanged tests caught 15 of 16 valid
production faults: four of four restoration faults, seven of seven Python/DAP
faults, and four of five Neo-tree faults. Syntax errors and unrelated harness
failures were excluded from the count. Restore testing selected the two newly
added functions without changing their setup or assertions; Neovim used the
unchanged real-plugin harnesses and isolated state/cache directories.

The surviving Neo-tree fault replaced outside-root clipboard preservation with
absolute-path copying. A separate native-plugin probe established a reachable
case: `:tcd` changes the explorer root while an asynchronous directory scan leaves
the old file node visible and selectable. Delaying delivery of the real directory
read result makes this transition deterministic without inventing nodes or
assigning source state. Production behavior preserved the clipboard; the same
fault overwrote it.

The user then requested that this gap be fixed and verified against the same
fault. The maintained Neo-tree harness now includes an eighth check for that
transition. It restores the directory-read hook, releases delayed results, waits
for refresh completion, and restores the tab directory even when an assertion
fails. Production code did not need another change.

Verification used the byte-identical original mutation patch, replacing the
outside-root guard with `if not relative then relative = path end`, in a temporary
export. The baseline and mutant received byte-identical copies of the updated
maintained test. The baseline passed all eight checks with exit status 0. The
mutant passed the seven original checks but failed the new clipboard-preservation
assertion with exit status 1. Both production copies passed Lua syntax checks;
the failure is behavioral, not a parsing or fixture failure.

The updated test also passes full Lua diagnostics through Hint severity,
targeted StyLua validation, and `git diff --check`. The previous whole-suite
results above remain historical; this test-only follow-up reran the affected
Neo-tree harness and diagnostics. The original 15-of-16 mutation result remains
unchanged; the focused replay demonstrates that the previously surviving fault
is now caught. Mutations remain outside the repository and are not committed.

Exact commands, patch identities, and baseline/mutant logs are retained locally
under `/private/tmp/dotfiles-mutation-neotree-regression.e70Rj0`; the temporary
`mutation-tests` report links this follow-up. These artifacts are supporting
evidence rather than required project state.
