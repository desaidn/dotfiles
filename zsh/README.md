# zsh

Part of [dotfiles](../README.md). Custom λ prompt + aliases. No Oh My Zsh dependency.

## Aliases

- `nvim-reset` — wipe lazy + Mason install dirs
- `nvim-reset-all` — wipe all nvim state, cache, and data

## Scope

Per-machine activations (`mise`, `atuin`, etc.) live in `~/.local/share/dotfiles/local.zsh`.
Interactive zsh sessions hand off to Fish with `exec fish` after local activation has loaded.
