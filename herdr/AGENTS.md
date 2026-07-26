# AGENTS.md

Guidance for coding agents working on the Herdr configuration. See
[`../AGENTS.md`](../AGENTS.md) for monorepo-level conventions.

## Configuration boundary

Homebrew owns the Herdr binary; do not treat Herdr as a Mise-managed language
runtime.

`config.toml` is the only repository-owned Herdr file. Install it with a
file-level symlink at `~/.config/herdr/config.toml`; never symlink the entire
`herdr/` directory.

Herdr keeps mutable runtime state beside its configuration. Keep all of the
following machine-local and out of this repository:

- `~/.config/herdr/session.json`
- `~/.config/herdr/*.log`
- `~/.config/herdr/*.sock`
- `~/.config/herdr/.plugins.lock`
- `~/.local/state/herdr/`

Do not commit the installed Herdr binary or generated agent-detection data.
Keep generated shell completions version-coupled to the installed binary and
out of the repository.

Agent integration installers mutate harness-specific state such as `~/.codex`.
Keep those commands explicit and per-machine; never add them to the generic
dotfiles installer.

## Testing configuration changes

Validate the configuration before reloading the running server:

```bash
herdr config check
herdr server reload-config
```

Preserve upstream defaults unless a setting directly supports the shared
terminal workflow. Keep tmux as a separate top-level fallback; generally do
not nest it inside Herdr for agent panes because nesting hides the foreground
agent process from Herdr. Do not auto-start Herdr from Ghostty or shell rc
files; plain `herdr` from the normal shell is the daily entry point and keeps
the tmux fallback independently reachable.
