# Runtime environment

Use during the effective-environment assessment. Read the current
[runtime manifest](../../../../mise/conf.d/00-dotfiles.toml) and
[dependency ownership](../../../../README.md#dependency-ownership); do not copy
today's pins into this guide.

## Verify actual selection

Check from a fresh configured shell in a neutral directory outside dotfiles
and other projects. Inside dotfiles, Mise can load the repository manifest as
project configuration and hide a conflicting global default. Inspect
`mise config ls` to establish the configuration sources.

For a full install, compare `mise current` with the exact tracked selectors.
Check `mise which` and the shell's executable resolution, then run
`node --version`, `python --version`, `rustc --version`, `java -version`, and
`javac -version`. Account for the manifest's Java vendor/build selector.

Distinguish installed versions, selected versions, and executables actually
used. A successful `mise exec` probe does not prove an existing interactive
shell has refreshed its PATH. A working Mise shim is valid; follow its
resolution and verify the runtime instead of requiring its path to equal
`mise which`.

For `--skip-mise-runtimes`, report runtime provisioning and validation as
skipped. Do not change runtime settings to make that mode look complete.

## Diagnose competing installations

Verify the active Mise executable and shell function. Homebrew owns Mise;
an older standalone binary or cached function can reject a valid manifest.
Compare the same manifest with Homebrew's binary, located through
`brew --prefix mise`, before changing runtime declarations.

Use the tracked activation templates and
[shell settings guidance](shell-settings.md) to correct selection while
preserving active runtime paths. Verify both fresh shell startup and any
remaining refresh needed in the user's running session.

## Reconcile runtime overrides

A user's `~/.config/mise/config.toml` takes precedence over the installed
defaults fragment. On a mismatch, show the affected tool's expected version,
effective version, and source file. Establish whether the cause is a global
setting, project setting, environment override, or stale activation.

If the user has not already decided, ask whether to keep personal defaults or
inherit the dotfiles versions. For authorized inheritance, back up the config
and remove only approved overrides. Prefer Mise's native commands; check the
installed help and use `--no-prune` when removing requests so runtimes remain
installed. Preserve unrelated settings.

Removing an override lets future dotfiles pins apply; copying today's pins into
the user config does not. Recheck selection and actual executables outside the
checkout afterward. Record retained overrides as accepted differences.
