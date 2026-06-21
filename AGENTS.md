# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Repository Overview

This is a personal dotfiles monorepo. It contains configurations for the tools below; an `install.sh` symlinks each subdirectory into `~/.config/<tool>/` and `zsh/.zshrc` to `~/.zshrc`. Editing a file under this repo and editing the corresponding file under `~/.config/<tool>/` are the same write.

## Core Applications

### Terminal & Shell

- **Ghostty** (`ghostty/config`) - macOS terminal emulator config
- **Fish** (`fish/`) - Primary shell, with custom λ prompt
- **Zsh** (`zsh/.zshrc`) - Secondary shell, mirrored prompt and aliases
- **Tmux** (`tmux/tmux.conf`) - Terminal multiplexer with directory preservation and 1-based indexing

### Development Tools

- **Neovim** (`nvim/`) - Primary editor for most languages (see `nvim/AGENTS.md` for details)
- **LazyGit** (`lazygit/config.yml`) - Git TUI with nvim integration, difftastic diffs, and custom theme

### macOS Finder Integration

- **NvimOpener** (`macos/NvimOpener.applescript`) - AppleScript droplet compiled by `install.sh` into `~/Applications/NvimOpener.app` on macOS. Lets Finder "Open With" launch nvim inside a Ghostty window. The compiled bundle's `Info.plist` is patched post-`osacompile` to set `CFBundleDocumentTypes[0].LSItemContentTypes = ["public.item"]`, `CFBundleTypeRole = Editor`, `LSHandlerRank = Alternate` — without this, the droplet does not appear in modern macOS's "Open With" menu (legacy `CFBundleTypeExtensions = ["*"]` is ignored). Bundle is re-signed (`codesign -s -`) and re-registered with `lsregister -f` after the patch.

### Per-machine prerequisites (not in this repo)

`install.sh` requires these on PATH and refuses to run otherwise:

- **Mise** - Runtime version manager (Node.js, Python, Rust, Go, etc.)
- **Atuin** - Shell history sync

Per-machine activation lines (`mise activate`, `atuin init`) are written to `~/.local/share/dotfiles/local.{fish,zsh}` by `install.sh`.

Ghostty is macOS-only for install: `install.sh` skips the Ghostty config symlink and `NvimOpener.app` on non-macOS hosts, but requires Ghostty on macOS.

## Configuration Philosophy

All configurations follow these principles:

- Only one way to do anything — no overlapping functionality between tools
- Minimal, focused setups without unnecessary complexity
- Consistent directory structure following XDG standards
- Integration between tools (e.g., lazygit ↔ nvim, ghostty ↔ tmux)
- Development-focused workflows for TypeScript, Kotlin/Java, Python, and Rust
- Prefer standard, idiomatic shortcuts and conventions over custom bindings to ensure compatibility across systems (e.g., use Ctrl+W for delete-word rather than custom Cmd+Backspace)
- Platform-agnostic rc files: no hardcoded `/opt/homebrew/...` paths in `fish/config.fish` or `zsh/.zshrc`. Per-machine state lives in `~/.local/share/dotfiles/local.{fish,zsh}`.

## Common Development Workflows

### Environment Setup

```bash
git clone <this-repo> ~/dotfiles
~/dotfiles/install.sh           # Symlink configs, write per-machine activation files
mise install                    # Install language runtimes
nvim                            # Start editor (see nvim/AGENTS.md for details)
```

### Terminal Usage

```bash
# Start multiplexed session
tmux new-session -s dev

# Inside tmux: C-b c (new window), C-b " (vsplit), C-b % (hsplit)
# All operations preserve current working directory
```

### Git Operations

- Use `lazygit` for TUI operations (integrated with nvim via `<leader>gg`)
- Configured with custom theme matching development environment

## Architecture Notes

### File Organization

- Each tool maintains its own subdirectory under the repo root, mirroring the XDG layout under `~/.config/`
- Individual tools may have their own AGENTS.md files (e.g., `nvim/AGENTS.md`, `tmux/AGENTS.md`)
- Configurations are environment-specific and not intended for multi-user scenarios

### Tool Integration Points

- **Editor ↔ Git**: Neovim integrates with both gitsigns and lazygit
- **Shell ↔ Terminal**: Ghostty launches the system shell; interactive zsh hands off to Fish with `exec fish`; tmux handles multiplexing
- **Runtime Management**: Mise handles all language version requirements
- **Keybinding Constraints**: Option/Alt is reserved for FlashSpace workspace management; terminal shortcuts use Cmd or Ctrl modifiers instead (e.g., Cmd+Arrow for word navigation in Ghostty)

### Dependencies

- macOS-first setup; configs aim to remain Linux-compatible where practical
- Primary languages: TypeScript (Bun, Node.js, Browser), Kotlin/Java, Python, Rust
- Terminal tooling: Ghostty, tmux, fish, zsh

## Agent skills

### Issue tracker

Issues and PRDs are tracked in GitHub Issues for `desaidn/dotfiles`; external PRs are not a triage request surface. See `docs/agents/issue-tracker.md`.

### Triage labels

Use the default five-label triage vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, and `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

This repo uses a single-context domain docs layout. See `docs/agents/domain.md`.

## Install Contract

`install.sh` MUST stay non-destructive:

- Never `rm` or `rm -rf` any user path.
- If a target exists, rename it to `<target>.bak.$(date +%s)` and create the symlink.
- If the target is already a symlink into this repo, skip silently.
- Re-running the script after a successful install is a no-op.

## Modification Guidelines

When modifying configurations:

1. Test changes in isolation before committing
2. Maintain integration between related tools
3. Keep configurations minimal and purpose-driven
4. Respect XDG directory structure
5. Document significant changes in relevant AGENTS.md files
6. Do not add platform-specific paths (e.g., `/opt/homebrew/...`) into rc files. They go in the per-machine `local.{fish,zsh}`.
