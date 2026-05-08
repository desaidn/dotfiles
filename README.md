# dotfiles

Personal config monorepo. Clone anywhere, run `./install.sh`, and your system is wired up via symlinks into `~/.config/` and `~/`.

## Layout

| Directory     | Target                | Notes                                              |
| ------------- | --------------------- | -------------------------------------------------- |
| `fish/`       | `~/.config/fish/`     | Prompt + nvim-reset aliases. Platform-agnostic.    |
| `ghostty/`    | `~/.config/ghostty/`  | macOS Ghostty terminal config.                     |
| `lazygit/`    | `~/.config/lazygit/`  | Uses `nvim-remote` editor + `difft` external diff. |
| `nvim/`       | `~/.config/nvim/`     | kickstart-based config; lazy.nvim auto-bootstraps. |
| `tmux/`       | `~/.config/tmux/`     | 1-indexed, vi copy mode, AI/build pane bindings.   |
| `zsh/.zshrc`  | `~/.zshrc`            | λ prompt + nvim-reset aliases. No OMZ dependency.  |
| `macos/`      | `~/Applications/`     | macOS-only. AppleScript droplet → nvim in Ghostty. |

Each subdirectory has its own `README.md` (and `CLAUDE.md` where relevant).

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
| `difft`         | lazygit external diff viewer |

**Not checked** (no portable `command -v` equivalent): JetBrains Mono font (used by Ghostty) — install from <https://www.jetbrains.com/lp/mono/>.

## Per-machine activation

The `fish` and `zsh` rc files source an optional per-machine file if it exists:

- `~/.local/share/dotfiles/local.fish`
- `~/.local/share/dotfiles/local.zsh`

`install.sh` writes these for you. They contain `mise activate`, `mise completion`, `atuin init`, and `[ -d ]`/`[ -f ]`-gated PATH additions for optional tools (`bun`, `ghcup`, `lmstudio`, `claude/local`) — every line is a no-op on a machine that lacks the tool. Edit freely — these files live outside the repo.

## Finder integration (macOS)

On macOS, `install.sh` compiles `macos/NvimOpener.applescript` into `~/Applications/NvimOpener.app`. The bundle's `Info.plist` is patched to declare `LSItemContentTypes = public.item` so it appears in Finder's **Open With** menu for any file. Double-clicking (or **Get Info → Open With → Change All…**) opens the file in `nvim` inside a fresh Ghostty window. Multi-file selections coalesce into one nvim window with each file as a buffer.

The droplet shells out via `/bin/zsh -lc "exec nvim …"` so `/etc/zprofile` runs `path_helper` and `nvim` resolves on both Apple Silicon and Intel without hardcoded paths.

## Rollback

After `install.sh` runs, anything it moved aside is at `~/<original>.bak.<timestamp>` (or `~/.config/<name>.bak.<timestamp>`). To restore:

```bash
./uninstall.sh                    # removes symlinks
mv ~/.zshrc.bak.<ts> ~/.zshrc     # restore by hand if you want the originals back
```
