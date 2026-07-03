# zsh

Part of [dotfiles](../README.md). Custom λ prompt, editor environment, and reset alias. No Oh My Zsh dependency.

## Environment

- `EDITOR`, `VISUAL`, and `GIT_EDITOR` are set to `nvim`.

## Aliases

- `nvim-reset` — wipe all nvim state, cache, and data

## Scope

Per-machine activations (`mise`, `atuin`, etc.) live in `~/.local/share/dotfiles/local.zsh`.
Interactive zsh sessions hand off to Fish with `exec fish` after local activation has loaded.
