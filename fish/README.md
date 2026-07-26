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
