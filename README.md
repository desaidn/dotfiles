# dotfiles

Personal config monorepo. Clone anywhere, run `./install.sh`, and your system is wired up via symlinks into `~/.config/` and `~/`.

The setup is designed around one uniform code interface: Neovim is the development surface, terminal tools provide supporting workflows, and agent harnesses such as Codex or Claude Code are interchangeable drivers rather than separate ways of working.

## Layout

| Directory     | Target                | Notes                                              |
| ------------- | --------------------- | -------------------------------------------------- |
| `fish/`       | `~/.config/fish/`     | Prompt + nvim-reset aliases. Platform-agnostic.    |
| `ghostty/`    | `~/.config/ghostty/`  | macOS Ghostty terminal config.                     |
| `lazygit/`    | `~/.config/lazygit/`  | Git TUI with Neovim editor handoff and native staging UI. |
| `nvim/`       | `~/.config/nvim/`     | kickstart-based config; lazy.nvim auto-bootstraps. |
| `tmux/`       | `~/.config/tmux/`     | 1-indexed, vi copy mode, agent/build pane bindings. |
| `zsh/.zshrc`  | `~/.zshrc`            | λ prompt + nvim-reset aliases. No OMZ dependency.  |

Each subdirectory has its own `README.md` (and `AGENTS.md` where relevant).

## Code interface contract

This repo keeps the interface to code agent-harness agnostic:

- Start and return to Neovim for editing.
- Use gitsigns for local in-buffer hunk operations.
- Use Hunk directly from Neovim for full stacked working-tree review.
- Use lazygit for Git state, staging, stashes, history, branches, and commits.
- Let shell configuration declare Neovim as the global editor through `EDITOR`, `VISUAL`, and `GIT_EDITOR`.
- Use flatten.nvim for editor handoff from terminal tools back into the host Neovim instance.
- Keep Neovim gitsigns actions hunk-local; buffer-wide Git transactions belong in lazygit.
- Prefer upstream defaults unless a deviation directly supports the uniform code interface.
- Keep Codex, Claude Code, and future harnesses as adapters over the same files, commands, and review surfaces.

Harness-specific files should only bridge into the shared workflow. They should not introduce a second review model, separate Git transaction surface, or different way to open code. Global Git behavior stays outside this contract unless the repo explicitly starts managing Git config.

## Quick start

```bash
git clone https://github.com/desaidn/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh
```

`install.sh` is **idempotent and non-destructive**:

- Existing files/dirs at link targets are renamed to `<path>.bak.<unix-timestamp>`, never deleted.
- Re-running it after a successful install is a no-op.
- Use `./uninstall.sh` to remove the symlinks (and optionally restore the most recent backup).

## Prerequisites

`install.sh` checks for the binaries below on PATH and prints the install URL of anything missing.

**Required tools this repo configures**: `git`, `fish`, `zsh`, `nvim`, `tmux`, `lazygit`

**macOS-only tool config**: `ghostty` is required on macOS and skipped on non-macOS hosts. `install.sh` accepts either the `ghostty` CLI or `Ghostty.app` in `/Applications` or `~/Applications`.

**Auxiliary deps**:

| Binary          | Required by                  |
| --------------- | ---------------------------- |
| `mise`          | shell rc (per-machine init)  |
| `atuin`         | shell rc (per-machine init)  |
| `rg`            | nvim Telescope / fff.nvim    |
| `tree-sitter`   | nvim treesitter parser mgmt  |
| `hunk`          | nvim stacked working-tree review |

**Not checked** (no portable `command -v` equivalent): JetBrains Mono font (used by Ghostty) — install from <https://www.jetbrains.com/lp/mono/>.

## Per-machine activation

The `fish` and `zsh` rc files source an optional per-machine file if it exists:

- `~/.local/share/dotfiles/local.fish`
- `~/.local/share/dotfiles/local.zsh`

`install.sh` writes these for you. They contain `mise activate`, `mise completion`, `atuin init`, and `[ -d ]`/`[ -f ]`-gated PATH additions for optional tools (`bun`, `ghcup`, `lmstudio`, `claude/local`) — every line is a no-op on a machine that lacks the tool. Edit freely — these files live outside the repo.

The shared shell rc files set `EDITOR`, `VISUAL`, and `GIT_EDITOR` to `nvim`; per-machine files should only override that when a machine genuinely needs a different editor contract.

## Rollback

After `install.sh` runs, anything it moved aside is at `~/<original>.bak.<timestamp>` (or `~/.config/<name>.bak.<timestamp>`). To restore:

```bash
./uninstall.sh                    # removes symlinks
mv ~/.zshrc.bak.<ts> ~/.zshrc     # restore by hand if you want the originals back
```
