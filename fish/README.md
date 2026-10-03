# fish

Part of [dotfiles](../README.md). Custom λ prompt, editor environment, and reset alias.

Requires Fish 3.2 or newer because the shared and per-machine configuration use
`fish_add_path`.

## Environment

- `EDITOR`, `VISUAL`, and `GIT_EDITOR` are set to `nvim`.

## Aliases

- `nvim-reset` — wipe all nvim state, cache, and data

## Scope

Per-machine activations (`mise`, `atuin`, etc.) live in `~/.local/share/dotfiles/local.fish`.
The template preserves inherited runtime ordering and adds optional tools as
fallback paths. Existing activation files stay user-owned; see the
[template update guidance](../README.md#per-machine-activation).

Interactive Fish loads Ghostty's available shell integration after a Zsh
handoff, preserving the configured SSH environment and terminfo features.
