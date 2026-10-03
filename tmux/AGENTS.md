# AGENTS.md

Guidance for coding agents working on the tmux config. See [`../AGENTS.md`](../AGENTS.md) for monorepo-level conventions.

## Configuration Purpose

Tmux is the retained top-level fallback and compatibility multiplexer; Herdr is
the normal daily workspace manager. Start tmux directly when its compatibility
surface is needed rather than nesting it inside Herdr for agent panes.

A single `tmux.conf` file provides:

- Window and pane indexing starting from 1 (instead of default 0)
- Directory preservation when creating new windows and panes
- Consistent working directory context across tmux operations

## Validation

Run this from the repository root in a POSIX-compatible shell. It executes the
tracked configuration on a fresh, isolated server so unsupported options and
command errors fail the check. Its temporary pane runs only `cat`; cleanup
targets only that test server.

```sh
(
  set -eu
  check_dir=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-tmux-check.XXXXXX")
  check_socket="$check_dir/server.sock"
  trap 'tmux -S "$check_socket" kill-server 2>/dev/null || :; rm -f "$check_socket"; rmdir "$check_dir"' EXIT
  tmux -S "$check_socket" -f /dev/null new-session -d -s config-check 'exec cat'
  tmux -S "$check_socket" source-file "$PWD/tmux/tmux.conf"
)
```

The `-f` option reads configuration only when a server starts, so creating a
session on an existing server does not validate the supplied file. Never use an
unscoped `tmux kill-server` as a validation or reload step; it destroys every
session on that server. See the [tmux manual](https://github.com/tmux/tmux/blob/master/tmux.1)
for server and configuration behavior. Daily startup and intentional live reload
commands belong in [README.md](README.md).

## Architecture

**File Structure**: Single configuration file approach
**Target Location**: `~/.config/tmux/tmux.conf` (XDG Base Directory specification)
**Scope**: Terminal multiplexer behavior customization
**Dependencies**: tmux 3.5 or newer for `extended-keys-format`; no plugins or additional runtime tools. Newer prompt-cursor styles are optional and ignored on older versions.

## Key Configuration Features

- **Index Customization**: Windows and panes start from 1
- **Directory Preservation**: New windows/panes inherit current directory
- **Key Bindings**: Enhanced `C-b c`, `C-b "`, and `C-b %` commands

## Modification Guidelines

- Maintain compatibility with standard tmux installations (no plugin-manager dependencies)
- Preserve the directory-context philosophy for new bindings (`-c "#{pane_current_path}"`)

See `../AGENTS.md` for repo-wide modification guidelines.
