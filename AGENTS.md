# AGENTS.md

This file provides guidance to coding agents working in this repository. Codex reads it directly; Claude Code reaches it through the `CLAUDE.md` adapter. Keep guidance here harness-agnostic unless a detail genuinely belongs to one runtime.

## Repository Overview

This is a personal dotfiles monorepo. It contains configurations for the tools below; an `install.sh` symlinks tracked configurations into `~/.config/<tool>/` and `zsh/.zshrc` to `~/.zshrc`. Herdr is linked as a single durable config file so its mutable runtime state remains local. Editing a file under this repo and editing the corresponding linked file under `~/.config/<tool>/` are the same write.

## Core Applications

### Terminal & Shell

- **Ghostty** (`ghostty/config`) - macOS terminal emulator config
- **Fish** (`fish/`) - Primary shell, with custom λ prompt
- **Zsh** (`zsh/.zshrc`) - Secondary shell, mirrored prompt and aliases
- **Herdr** (`herdr/config.toml`) - Primary daily workspace manager; only durable configuration is tracked
- **Tmux** (`tmux/tmux.conf`) - Retained fallback and compatibility multiplexer with directory preservation and 1-based indexing

### Development Tools

- **Neovim** (`nvim/`) - Primary editor for most languages (see `nvim/AGENTS.md` for details)
- **LazyGit** (`lazygit/config.yml`) - Git TUI with nvim integration, native staging UI, and custom theme
- **Hunk** (`hunk/config.toml`) - Full stacked working-tree review surface from Neovim; only durable preferences are tracked

### Per-machine prerequisites (not in this repo)

`install.sh` requires these on PATH and refuses to run otherwise:

- **Mise** - Runtime version manager (Node.js, Python, Rust, Go, etc.)
- **Atuin** - Shell history sync

Per-machine activation lines (`mise activate`, `atuin init`) are written to `~/.local/share/dotfiles/local.{fish,zsh}` by `install.sh`.

Ghostty is macOS-only for install: `install.sh` skips the Ghostty config symlink on non-macOS hosts, but requires Ghostty on macOS.

## Configuration Philosophy

All configurations follow these principles:

- Only one way to do anything — no overlapping functionality between tools
- Minimal, focused setups without unnecessary complexity
- Consistent directory structure following XDG standards
- Integration between tools (e.g., lazygit ↔ nvim, terminal tools ↔ editor handoff)
- Prefer native platform and Neovim capabilities before adding third-party abstractions
- Keep external dependencies few, purposeful, and replaceable; every dependency should justify its maintenance and portability cost
- Prefer small self-made or locally-owned performant development tools when native capabilities are not enough and the workflow should stay inspectable
- Agent harnesses are adapters, not workflow owners; Codex, Claude Code, and future tools should use the same Neovim, Git, and review surfaces
- Prefer upstream defaults unless a deviation directly supports the uniform code interface; avoid custom maintenance burden for taste-only changes
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
# Start or reattach the normal daily workspace
herdr

# Start a deliberate fallback/compatibility session directly
tmux new-session -A -s dev

# Inside fallback tmux: C-b c (new window), C-b " (vsplit), C-b % (hsplit)
# All operations preserve current working directory
```

Herdr and tmux are top-level alternatives. Do not nest the tmux fallback inside Herdr for normal agent work.

### Git Operations

- Use `lazygit` for TUI operations (integrated with nvim via `<leader>gg`)
- Configured with custom theme matching development environment
- Use direct Hunk from Neovim only for full stacked working-tree review (`<leader>gd` → `hunk diff --watch --mode stack`).
- Keep gitsigns keymaps hunk-local; buffer-wide stage/reset operations belong in lazygit.

### Agent Harnesses

- Treat the user-facing code interface as Neovim plus terminal tools, regardless of which agent harness is active.
- Keep harness-specific instructions as thin adapters into shared repo guidance.
- Do not add Codex-only or Claude-only workflows when a shared command, file, or review surface can express the same behavior.
- Hunk is the direct full working-tree review surface from Neovim; lazygit remains the Git transaction surface and uses its native diff/staging UI.

## Architecture Notes

### File Organization

- Each tool maintains its own subdirectory under the repo root, mirroring the XDG layout under `~/.config/`; Herdr and Hunk link only `config.toml` so mutable state stays untracked
- Individual tools may have their own AGENTS.md files (e.g., `herdr/AGENTS.md`, `nvim/AGENTS.md`, `tmux/AGENTS.md`)
- Long-lived architecture review reports that the user chooses to retain live under `docs/`; generated reports should not remain at the repository root
- Configurations are environment-specific and not intended for multi-user scenarios

### Tool Integration Points

- **Editor ↔ Git**: Neovim integrates with both gitsigns and lazygit
- **Shell ↔ Editor**: Fish and zsh own the global editor contract (`EDITOR`, `VISUAL`, and `GIT_EDITOR` all point to `nvim`)
- **Terminal tool ↔ Editor**: flatten.nvim handles editor handoff from nested `nvim` calls back into the host Neovim; the shared terminal-tool module owns the opaque source marker and post-handoff policy while preserving the shell-owned `EDITOR` contract
- **Neovim ↔ Terminal tools**: Neovim-owned terminal tools use `nvim/lua/custom/lib/terminal_tool.lua`: one persistent Tool Tab per tool, restarted when the Host Window's effective working directory changes, with flatten.nvim for Editor Handoff and host tmux prefix and pane navigation kept upstream when using the fallback
- **Shell ↔ Workspace manager**: Ghostty launches the system shell; interactive zsh hands off to Fish with `exec fish`; invoke Herdr for the daily workspace or tmux directly for fallback/compatibility
- **Runtime Management**: Mise handles all language version requirements
- **Keybinding Constraints**: Option/Alt is reserved for FlashSpace workspace management; terminal shortcuts use Cmd or Ctrl modifiers instead (e.g., Cmd+Arrow for word navigation in Ghostty)

### Dependencies

- macOS-first setup; configs aim to remain Linux-compatible where practical
- Primary languages: TypeScript (Bun, Node.js, Browser), Kotlin/Java, Python, Rust
- Terminal tooling: Ghostty, Herdr, tmux, fish, zsh

## Agent skills

### Working TODOs

`TODO.md` and the index in `docs/todos/README.md` list active work only; briefs under `docs/todos/` exist only for active items. Follow the lifecycle in that README. When retiring an item, remove both index entries and delete its brief in the same change after preserving any durable knowledge in its proper home.

### Issue tracker

Issues, specs, and PRDs are tracked in GitHub Issues for `desaidn/dotfiles`; external PRs are not a triage request surface. See `docs/agents/issue-tracker.md`.

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
4. Prefer native APIs and existing local helpers before adding external dependencies
5. Respect XDG directory structure
6. Document significant changes in relevant AGENTS.md files
7. Do not add platform-specific paths (e.g., `/opt/homebrew/...`) into rc files. They go in the per-machine `local.{fish,zsh}`.
