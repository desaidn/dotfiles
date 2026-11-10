# Herdr

Part of [dotfiles](../README.md).

Herdr TUI is on the shelf: it stays installed and configured as an
alternative to [Herdr app](../herdr-app/README.md), which is now the daily
workspace. Use it from Ghostty on macOS or from an SSH shell when chosen. The
TUI has its own server, state, and `herdr` CLI, separate from Herdr app's core
and `hc`.

Running the Herdr TUI with `herdr` starts or
attaches to the persistent workspace, and `Ctrl-b q` detaches without stopping
the processes in its panes.

## Installation

Herdr is an application rather than a language runtime, so Homebrew owns it:

```bash
brew install herdr
```

The dotfiles installer installs the formula when missing and validates that
`herdr` is on `PATH`; successful reruns do not upgrade it.

## Configuration

Only [`config.toml`](config.toml) is tracked and linked to
`~/.config/herdr/config.toml`. The rest of `~/.config/herdr/` and
`~/.local/state/herdr/` contains machine-local session data, logs, sockets,
locks, and downloaded agent-detection state. Do not symlink either directory
into this repository.

Validate and reload configuration changes with:

```bash
herdr config check
herdr server reload-config
```

## Agent integrations

Herdr detects Codex from terminal output without additional hooks. Native
session identity and restore are an explicit per-machine opt-in:

```bash
herdr integration install codex
```

That command mutates `~/.codex`, so the generic dotfiles installer does not run
it.

## tmux fallback

tmux remains available as a separate top-level fallback. Generally avoid
nesting tmux inside Herdr for agent panes because Herdr then sees tmux, rather
than the agent process, in the foreground.

```bash
tmux new-session -A -s dev
```
