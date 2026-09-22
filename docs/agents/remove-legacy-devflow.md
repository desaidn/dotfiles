# Remove legacy devflow from a machine

Give this document to an agent with the request: **Remove the legacy dotfiles
devflow installation from this machine, following this guide.** Discover the
actual user, installation, profiles, and repositories; do not copy paths from
another machine. The known installations target macOS and Linux. Treat a manual
installation on another platform according to its actual package owner.

Remove the application, its dedicated environment and entry points, old Git
enforcement, and active instructions that require it. Preserve personal guidance,
other tools, installed skills, Git history, review records, and worktrees.
Historical `.git/devflow/` records and `wip/*`/`review/*` refs are user evidence,
not a running installation. Their deletion is a separate request.

This is an explicit migration procedure, not another maintained CLI. Neither
the current nor a historical root `uninstall.sh` is a devflow-only removal
command: running it also removes unrelated dotfiles links. Do not run it for
this task. Do not run old `devflow init`; guard-era versions install Git hooks.

## 1. Discover and preserve the current state

- Work as the affected user, without `sudo`. Require an existing absolute,
  non-root `HOME`; validate custom profile paths before using them. Inspect
  symlinked containers and their resolved owners before following them. A path
  or filename containing `devflow` is not sufficient proof of ownership.
- Discover the dotfiles checkout and every relevant installation/profile. Read
  shell configuration and the user's known project locations to establish scope.
  Do not scan other users' homes or claim machine-wide completion after checking
  only the current repository. Report any repositories or profiles not inspected.
- In the user's interactive shell, inspect every resolution of `devflow`,
  `devflow-pre-push`, and `devflow-reference-transaction` (`type -a` in Bash/zsh).
  Also inspect `~/.local/bin` directly: a dangling link may not appear on `PATH`.
  Record aliases, functions, wrapper scripts, and custom tool directories.
- Before each mutation, save exclusive, collision-free backups of affected
  instruction/config files, hook links, and installation receipts, with original
  paths, modes, link targets, and hashes. Keep backups outside active harness
  instruction directories, for example in a newly created directory under
  `~/.local/share/dotfiles/`. Never overwrite earlier backups.
- Coordinate running agent/review activity. Record Git HEAD, status, relevant
  refs, and worktree lists before changing repository configuration. End only
  reviews belonging to this migration before modifying their checkouts; do not
  close unrelated Hunk, Herdr, or Neovim sessions.

The final installer used these paths regardless of the source checkout's name:

| Item | Known dotfiles-managed location |
| --- | --- |
| Ownership receipt | `$HOME/.local/share/dotfiles/devflow-tool.receipt` |
| Private uv tool root | `$HOME/.local/share/dotfiles/uv-tools` |
| Dedicated environment | `<private-root>/dotfiles-devflow` |
| Public executables | `$HOME/.local/bin/devflow`; older versions also installed `devflow-pre-push` and `devflow-reference-transaction` |
| Editable source | `<old-checkout>/tools/devflow`, or earlier `<old-checkout>/devflow` |

Read receipts as data; never source or evaluate them. Use `lstat`/`lexists` or
equivalent checks so dangling links remain visible. Save evidence before removal.

## 2. Establish ownership and identify the version

The dotfiles receipt contains exactly three lines: a marker, the absolute
editable-source path, and the absolute Python-interpreter path. Recognized
historical markers are:

| Marker | Expected completed installation |
| --- | --- |
| `dotfiles-devflow-v1` or `dotfiles-devflow-pending-v1` | `devflow`, `devflow-pre-push`, `devflow-reference-transaction` |
| `dotfiles-devflow-v2` or `dotfiles-devflow-pending-v2` | Only `devflow` |
| `dotfiles-devflow-migrating-v2` | Interrupted v1-to-v2 transition; inspect actual inventory |

A pending/migrating marker does not establish that installation completed.
For a complete owned installation, check all of the following:

- The dotfiles receipt and environment's `uv-receipt.toml` are regular files,
  and the dedicated environment is a regular directory rather than a redirect.
- Parse `uv-receipt.toml` semantically with a TOML parser. Its `[tool]` describes
  the receipted Python, exactly one editable requirement with `name` equal to
  `dotfiles-devflow` and `editable` equal to the receipted source, and the exact
  generation's entry-point inventory. Each entry has the expected `name`,
  `install-path`, and `from = "dotfiles-devflow"`. Reject extra, duplicate,
  missing, non-string, or contradictory inventory; comments and ordering do not
  affect ownership.
- The environment's `bin/python` points to the receipted interpreter, its single
  regular, non-symlink `lib/python*/site-packages/dotfiles_devflow.pth` contains
  the receipted source followed by `/src`, and each public executable is the corresponding owned
  symlink into that environment's `bin/` directory.
- Corroborate the source/distribution with installed metadata or this dotfiles
  repository's history. Do not infer ownership from the distribution name alone
  when a different source, environment, or package owner is recorded.

The original source checkout or interpreter may have moved or disappeared.
Compare recorded paths and symlink targets without executing the missing Python;
an available trusted TOML parser is sufficient. Do not rewrite the receipt to
match the current checkout or install Python merely to make old devflow run.

If state is partial, inventory each remaining artifact separately. A receipt
alone does not authorize deleting an unexpected directory or executable. An
already-absent environment is not a reason to skip old guidance or hooks. For
missing receipts, contradictory metadata, foreign links, or a manual install,
identify the actual owner and exact files before removal; continue independent
proven cleanup and report unresolved artifacts instead of inventing provenance.

## 3. Remove guard-era Git hooks and active configuration

Do this before uninstalling their executables. Enumerate known participating
repositories and inspect the effective configuration from every worktree:

```sh
git rev-parse --path-format=absolute --git-common-dir
git worktree list --porcelain
git config --show-origin --get-all core.hooksPath
git config --show-origin --get-regexp '^(devflow\.|alias\.)'
```

A missing optional config key is normal. Per-worktree settings and conditional
includes can select different hook locations. After inspecting every worktree,
deduplicate shared artifacts by resolved path and Git common directory so each
is changed once. Inspect the effective hooks directory and any known legacy
hook location. Guard-era devflow installed symlinks named
`reference-transaction` and `pre-push` to the matching
`devflow-reference-transaction` and `devflow-pre-push` entry points. Their targets
may be resolved paths inside the private environment or a manually selected
`DEVFLOW_HOOK_BIN_DIR`, not the public `~/.local/bin` links.

Back up and unlink only hooks whose targets/content are proven to belong to
this retired installation. Recheck unchanged ownership immediately before
unlinking; preserve foreign hooks and mixed-content wrappers. For a wrapper
containing personal logic, remove only its verified devflow invocation after
preserving the remainder. A broken hook link still needs inspection and removal
when its ownership is established.

Old devflow honored `core.hooksPath` but did not own that setting. Do not unset it
or remove a hooks directory just because it contains one devflow hook. Remove
obsolete `devflow.*` settings such as `devflow.worktree-mode` only from the exact
configuration file/scope that owns them, after verifying their legacy meaning.
Inspect includes and per-worktree config; do not indiscriminately unset global
keys or rewrite an entire Git config. Remove only proven devflow aliases and
shell startup hooks/functions/exports. Keep general `~/.local/bin` PATH setup.

Preserve `.git/devflow/` historical records and all refs/worktrees, including
older managed review worktrees under
`${XDG_STATE_HOME:-$HOME/.local/state}/devflow/`. Include that location in the
inventory; it can contain unpublished user work, not just disposable cache.

## 4. Remove legacy harness guidance

The old harness integration wrote to `$CODEX_HOME/AGENTS.md` (default
`$HOME/.codex/AGENTS.md`) and `$HOME/.claude/CLAUDE.md`. Inspect every configured
Codex profile, not just the profile active in this shell. That integration did
not generate pi instructions; inspect any manually copied guidance separately.

The owned block uses exactly these markers:

```text
<!-- dotfiles-devflow:begin v1 -->
...legacy guidance...
<!-- dotfiles-devflow:end v1 -->
```

Inspect and back up the full file first. Require one well-formed marker pair,
with the surrounding newlines matching the historical writer; compare the body
against a trusted historical version and reconcile any personal edits inside it.
If the verified owned executable is still runnable, its supported commands are:

```sh
devflow --json harness status codex
devflow --json harness remove codex
devflow --json harness status claude
devflow --json harness remove claude
```

Use the verified absolute executable path, and the intended `CODEX_HOME` for
each profile, rather than trusting an arbitrary `devflow` on `PATH`. Do not run
these commands against the new shared-workflow symlinks. Inspect ancestors as
well as the destination for redirects.

If the executable/source/interpreter is unavailable, perform a byte-preserving
edit instead. The historical owned span includes one leading newline before
BEGIN and one trailing newline after END. Preserve all prefix/suffix bytes and
file permissions; verify they are unchanged, recheck the original file against
its backup, then replace atomically. Duplicate, unknown, incomplete, or modified
markers require explicit reconciliation rather than a broad text substitution.
Do not delete the whole personal instruction file or restore an old backup over
newer guidance. An otherwise empty legacy-only file may be removed after backup
and verification; an empty file can otherwise block the new installer link.

Inspect active project instructions and shell/editor launch configuration for
copied devflow commands, `DEVFLOW_REVIEW_*`, and old hook entry points. Update
only actual obsolete invocation/policy, preserving unrelated content and human
work. Coordinate tracked edits through each project's workflow. Historical ADRs,
commit history, this removal guide, and archived backups may legitimately retain
the name. Preserve the current `HUNK_REVIEW_*` adapter and shared workflow links.

## 5. Uninstall the owned application

For the verified dotfiles-managed installation, remove the distribution through
uv with explicit private directories. Run this Bash example only after the
ownership checks above; it is not a discovery command or a substitute for them.

```bash
(
    set -euo pipefail
    [[ -n "${HOME:-}" && "$HOME" == /* && -d "$HOME" ]] || exit 1
    retirement_home=$(cd -P -- "$HOME" && pwd -P)
    [[ "$retirement_home" != / && "$EUID" != 0 ]] || exit 1
    while IFS= read -r retirement_variable; do
        case "$retirement_variable" in
            UV_*|PYTHON*|VIRTUAL_ENV*|CONDA_*|PIP_*)
                unset "$retirement_variable"
                ;;
        esac
    done < <(compgen -e)
    export UV_TOOL_DIR="$HOME/.local/share/dotfiles/uv-tools"
    export UV_TOOL_BIN_DIR="$HOME/.local/bin"
    uv --no-config --offline tool uninstall dotfiles-devflow
)
```

This preserves general proxy/TLS settings while isolating uv from inherited
package configuration. The tool and executable locations are selected by
[uv's environment variables](https://docs.astral.sh/uv/reference/environment/#uv_tool_dir);
[the uninstall command](https://docs.astral.sh/uv/reference/cli/#uv-tool-uninstall)
removes the selected distribution. Never use `--all`, reinstall/upgrade the
retired tool, or run a broad cache cleanup as part of this removal.

Check the actual result, not just the exit status. Verify the dedicated
environment and every generation's owned public entry point are absent,
including dangling links. Only then remove the unchanged, backed-up dotfiles
receipt if it still exists; an already-absent receipt is a successful no-op.
Remove a proven orphaned receipt when its environment/entry points were already
removed, after checking the other cleanup sections too.

If uv cannot complete, preserve the evidence and diagnose the remaining state.
Never fall back to recursive deletion merely because uninstall failed. Remove
individual stale owned links only after checking their targets again; a partial
or foreign environment requires an explicit ownership-based recovery plan.
Do not remove the shared `uv-tools` parent, `~/.local/bin`, or all of
`~/.local/share/dotfiles`. Keep Homebrew's uv and Mise/Python runtimes.

For a manual uv installation, discover its actual tool root and bin directory
(`uv tool dir`, `uv tool dir --bin`, and `uv tool list --show-paths` in its known
configuration), prove provenance, and target that installation explicitly. For
pipx or a dedicated virtualenv, inspect its owner/metadata and use that owner's
package-specific uninstall. Do not run system-wide `pip uninstall` or remove a
shared virtualenv. Repeat inventory if multiple copies shadow each other.

## 6. Verify completion and optionally install the replacement

- In fresh user shells, none of the retired entry points resolve to this
  installation, and no alias/function or startup configuration recreates it.
- No owned environment, public executable, dangling legacy hook, or obsolete
  installation receipt remains. No active harness/project instruction requires
  devflow. Verify every inventoried profile and repository, not just defaults.
- Personal instruction bytes outside the removed blocks, other tools/skills,
  unrelated hooks/configuration, Git HEAD/index/files/refs, historical review
  records, and worktree topology remain unchanged except for explicitly intended
  instruction/configuration edits. Recheck differences against the inventory.
- A second inspection requires no further mutation. Report what was removed,
  which locations were inspected, backup locations, preserved historical state,
  and any remaining ambiguous artifacts. Do not claim full removal if any active
  integration or installation remains unresolved.

If the user also requested the replacement workflow, reconcile any personal
instructions at its destinations, then follow the current
[installation instructions](../../README.md#shared-agent-instructions). Run
`./install.sh` only from the updated checkout, with its documented dependency
provisioning effects understood. It links the shared workflow for Codex, Claude,
and pi; it does not uninstall old devflow. Verify the links and start fresh
harness sessions so removed instructions are no longer retained as context.

## Historical evidence

Use repository history to resolve version-specific details without checking out
old code over current work. The last pre-retirement snapshot is
`28259208fb69560338dbc1054b4add449a48d287`; inspect its `install.sh`, `uninstall.sh`,
`tools/devflow/pyproject.toml`, and `tools/devflow/src/devflow/harness.py` with
`git show COMMIT:PATH`. Earlier versions lived under `devflow/`; the history of
`devflow/src/devflow/hooks.py`, `state.py`, and `checkouts.py` explains guard and
worktree artifacts. Read historical scripts as evidence, never execute an entire
old installer/uninstaller as a cleanup shortcut. Obtain missing history from the
trusted repository when working from a shallow clone.
