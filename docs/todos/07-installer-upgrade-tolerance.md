# Improve installer upgrade tolerance

## Outcome

Keep `install.sh` safe and repeatable when a machine configured by an earlier
repository revision is upgraded to a later one. Supported additions and
packaging changes should converge to the new declared state, a second unchanged
run should be a no-op, and ambiguous or partially owned state should remain
untouched with an actionable error.

## Current state

The installer already handles unchanged reruns, missing Brewfile declarations,
exact Mise runtime installation, additive managed links, timestamped backups,
and exact ownership of the current single-entry-point devflow installation.
Integration tests cover fresh and second runs on macOS and each supported Linux
package manager, along with interrupted, partial, and tampered devflow install
states.

The current upgrade audit found three gaps:

- A changed tracked Python pin installs through Mise, but the existing devflow
  receipt remains bound to the old interpreter and the installer stops instead
  of migrating the exact owned environment.
- Changes to devflow runtime dependencies or other installed package metadata
  are not detected. Editable source changes appear immediately, while the tool
  environment can retain a stale dependency set unless a new explicit receipt
  migration is added.
- Initial per-machine template files are copied directly to their final paths;
  interruption during a first copy could leave a partial file that later runs
  correctly preserve as user-owned.

Additive Brew and link behavior is evident in the implementation, but the test
suite does not yet model an older successful installation followed by a changed
manifest and another unchanged run.

## Scope

- Define how a receipted devflow installation detects changes to the interpreter
  and installed package inputs without confusing editable source-only changes
  with environment changes.
- Provide a recoverable upgrade transaction for an exact owned older devflow
  environment while continuing to preserve foreign, partial, or tampered state.
- Make first-time per-machine template initialization atomic without overwriting
  an existing user file.
- Add upgrade-path fixtures that begin from an older successful installation,
  apply representative manifest or inventory changes, and then run the updated
  installer twice.
- Document which repository changes converge automatically and which require a
  deliberate versioned migration.

## Boundaries / non-goals

- Do not use `--force`, overwrite unreceipted state, or weaken the exact semantic
  ownership checks around the private uv environment and public entry points.
- Do not remove old Homebrew packages or Mise runtimes merely because a later
  manifest no longer declares them.
- Do not turn installation into a general rollback or package-upgrade manager.
- Do not make generic installation modify harness-global Codex or Claude
  guidance.
- Preserve the self-contained installer and uninstaller safety boundaries.

## Open decisions

- Should installed package inputs be represented by a canonical fingerprint, an
  explicit install generation, or a deliberately versioned receipt migration?
- Should a tracked Python change migrate automatically when the prior tool state
  is exact, or require an explicit generation transition bundled with the pin?
- Which pyproject and lockfile fields actually affect the isolated runtime
  environment, and which source-only or development settings should not trigger
  a reinstall?
- Should the direct and nested link inventories remain explicit in each
  lifecycle function or gain one shared declarative inventory without weakening
  preflight clarity?

## Acceptance criteria

- A machine with an exact owned installation from the prior supported state can
  run the updated installer successfully after a tracked Python or devflow
  package-environment change.
- An interruption before removal, after removal, after installation, or before
  receipt finalization is either resumable or preserved for explicit recovery.
- A second unchanged run performs no package, runtime, uv-tool, link, template,
  or backup mutation.
- Foreign, unreceipted, partial, malformed, or tampered tool state is preserved
  and rejected before unrelated configuration links change.
- First-time template initialization is atomic, and existing per-machine files
  remain user-owned and untouched.
- Tests cover at least one added Brew declaration, changed exact Mise pin, new
  managed link, changed devflow package environment, and the no-op run following
  each supported upgrade.

## Verification

Run the full installer integration suite:

```sh
bash tests/install_test.sh
```

Exercise each new upgrade fixture through old install, upgraded install, and
unchanged second run. Run `bash -n install.sh uninstall.sh tests/install_test.sh`
and `git diff --check`. If the devflow package or receipt format changes, also
run its Python tests, Ruff, basedpyright, and offline lock verification.

## Starting points

- [`install.sh`](../../install.sh)
- [`uninstall.sh`](../../uninstall.sh)
- [`tests/install_test.sh`](../../tests/install_test.sh)
- [`devflow/pyproject.toml`](../../devflow/pyproject.toml)
- [`devflow/uv.lock`](../../devflow/uv.lock)
- [`AGENTS.md`](../../AGENTS.md) — Install and Uninstall Contracts
