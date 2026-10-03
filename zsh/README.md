# zsh

Part of [dotfiles](../README.md). Custom λ prompt, editor environment, and reset alias. No Oh My Zsh dependency.

## Environment

- `EDITOR`, `VISUAL`, and `GIT_EDITOR` are set to `nvim`.

## Aliases

- `nvim-reset` — wipe all nvim state, cache, and data

## Scope

Per-machine activations (`mise`, `atuin`, etc.) live in `~/.local/share/dotfiles/local.zsh`.
It loads after the editor environment and prompt, function, and alias defaults,
so existing machine overrides remain effective. The template adds Homebrew's
completion directory before `compinit`, including when an inherited Homebrew-first
`PATH` makes `brew shellenv` emit nothing.
Interactive sessions hand off to Fish with `exec fish` after local activation
has loaded. Explicit `zsh -ic` commands, including an empty command, stay
in Zsh. The template initializes Zsh completion, Mise, and Atuin only when
remaining in Zsh; machine-specific exports still run before the handoff.
See the [template update guidance](../README.md#per-machine-activation) for
existing installations.
