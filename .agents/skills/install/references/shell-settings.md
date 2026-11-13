# Shell settings

Use when installation replaces a shell startup file or preserves per-machine
settings that need reconciliation. Read the
[per-machine activation guidance](../../../../README.md#per-machine-activation)
and [templates](../../../../templates/).

## Recover selected settings from backups

When the installer replaces `~/.zshrc`, review the original file in its
`.bak.<timestamp>` backup alongside the new managed rc file and the current
per-machine files. On a resumed setup, establish which backup belongs to the
replaced configuration; do not assume the newest backup is the right source.
Read the whole file to identify useful settings rather than restoring it
wholesale.

Identify still-needed environment variables, aliases, functions, tool paths,
and custom integrations. Compare them with the managed configuration and
templates: old prompts, hardcoded runtime activation, and initialization already
provided by dotfiles generally should not be carried over. Explain the proposed
selection and omissions, resolve uncertain choices, and reuse authorization
already given for the migration.

Merge selected settings into `~/.local/share/dotfiles/local.zsh`, then port
their behavior to `local.fish` for consistency. Keep the managed rc link and
original backup intact. Check for settings already migrated so reruns do not
append duplicates.

## Reconcile preserved activation

Existing `~/.local/share/dotfiles/local.fish` and `local.zsh` are not updated by
an installer rerun. Compare relevant activation and PATH sections with the
tracked templates while preserving machine-specific additions.

If a difference prevents the environment from working, prepare the specific
merge. Reuse explicit authorization for that migration; otherwise ask before
changing user-owned files. For stale Mise selection, also use
[runtime environment](runtime-environment.md).

## Verify both shells

Preserve direct Zsh use as well as Fish. Translate behavior rather than copying
shell-specific initialization such as `compinit`. Validate syntax, argument
forwarding and quoting, relevant aliases/functions, PATH ordering, and wrapped
commands' exit status in both shells.

Recheck source and destination files before applying a prepared migration.
Back up changed local files and verify the intended additions, preserved
settings, and equivalent behavior afterward.

On Linux, relay the exact Fish launch command printed by the installer.
Running it in an agent subprocess does not refresh the user's terminal or
change the account's login shell.
