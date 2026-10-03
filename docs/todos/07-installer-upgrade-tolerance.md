# Improve installer upgrade tolerance

## Outcome

Keep `install.sh` safe and repeatable when a machine configured by an earlier
repository revision is upgraded to a later one. Supported additions and
configuration changes should converge to the new declared state, a second
unchanged run should be a no-op, and ambiguous or partially owned state should remain
untouched with an actionable error.

## Current state

The installer already handles unchanged reruns, missing Brewfile declarations,
exact Mise runtime installation, additive managed links, timestamped backups,
and ownership of shared agent instruction links.
Integration tests cover fresh and second runs on macOS and each supported Linux
package manager, with separate checks for unmanaged or conflicting instruction
files. The standalone devflow package and its private Python environment have
been retired, so migrating their runtime dependencies is no longer part of this
work.

Initial per-machine templates are staged privately and published atomically
without replacing existing user content. The installer tests cover interrupted
copying and a user file appearing before publication. Source/destination overlap
and unexpected Mise configuration sources are rejected before provisioning.

Additive Brew and link behavior is evident in the implementation, but the test
suite does not yet model an older successful installation followed by a changed
manifest and another unchanged run.

## Scope

- Preserve atomic first-time template initialization and its interruption tests.
- Add upgrade-path fixtures that begin from an older successful installation,
  apply representative manifest or inventory changes, and then run the updated
  installer twice.
- Document which repository changes converge automatically and which require a
  deliberate versioned migration.

## Boundaries / non-goals

- Do not overwrite unmanaged paths or weaken path-equivalent ownership checks
  for managed configuration and instruction links.
- Do not remove old Homebrew packages or Mise runtimes merely because a later
  manifest no longer declares them.
- Do not turn installation into a general rollback or package-upgrade manager.
- Preserve the supported shared instruction links without replacing unrelated
  personal or project guidance. Conflicting legacy guidance requires explicit
  migration.
- Preserve the self-contained installer and uninstaller safety boundaries.

## Open decisions

- Which link-layout changes can be handled as ordinary additions, and which
  need a deliberately documented ownership migration?
- Should the direct and nested link inventories remain explicit in each
  lifecycle function or gain one shared declarative inventory without weakening
  preflight clarity?

## Acceptance criteria

- A machine configured by the prior supported state can run the updated
  installer successfully after an added Brew declaration, changed exact Mise
  pin, or new managed link.
- An interruption during first-time template initialization is either resumable
  or preserved for explicit recovery.
- A second unchanged run performs no package, runtime, link, template,
  or backup mutation.
- Foreign links, conflicting instruction files, and ambiguous prior state are
  preserved and rejected before unrelated configuration links change.
- First-time template initialization is atomic, and existing per-machine files
  remain user-owned and untouched.
- Tests cover at least one added Brew declaration, changed exact Mise pin, new
  managed configuration or instruction link, and the no-op run following each
  supported upgrade.

## Verification

Run the full installer integration suite:

```sh
bash tests/install_test.sh
```

Exercise each new upgrade fixture through old install, upgraded install, and
unchanged second run. Run `bash -n install.sh uninstall.sh tests/install_test.sh`
and `git diff --check`.

## Starting points

- [`install.sh`](../../install.sh)
- [`uninstall.sh`](../../uninstall.sh)
- [`tests/install_test.sh`](../../tests/install_test.sh)
- [`AGENTS.md`](../../AGENTS.md) — Install and Uninstall Contracts
