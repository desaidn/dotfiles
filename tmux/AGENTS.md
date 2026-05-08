# AGENTS.md

Guidance for Codex working on the tmux config. See [`../AGENTS.md`](../AGENTS.md) for monorepo-level conventions.

## Configuration Purpose

A single `tmux.conf` file. Provides:

- Window and pane indexing starting from 1 (instead of default 0)
- Directory preservation when creating new windows and panes
- Consistent working directory context across tmux operations

## Common Operations

### Testing Configuration Changes

```bash
# Reload tmux configuration in existing session
tmux source-file ~/.config/tmux/tmux.conf

# Or restart tmux completely
tmux kill-server
```

### Verifying Configuration

```bash
# Check tmux configuration syntax
tmux -f ~/.config/tmux/tmux.conf new-session -d -s test \; kill-session -t test
```

## Architecture

**File Structure**: Single configuration file approach
**Target Location**: `~/.config/tmux/tmux.conf` (XDG Base Directory specification)
**Scope**: Terminal multiplexer behavior customization
**Dependencies**: None - pure tmux configuration

## Key Configuration Features

- **Index Customization**: Windows and panes start from 1
- **Directory Preservation**: New windows/panes inherit current directory
- **Key Bindings**: Enhanced `C-b c`, `C-b "`, and `C-b %` commands

## Modification Guidelines

- Maintain compatibility with standard tmux installations (no plugin-manager dependencies)
- Preserve the directory-context philosophy for new bindings (`-c "#{pane_current_path}"`)

See `../AGENTS.md` for repo-wide modification guidelines.
