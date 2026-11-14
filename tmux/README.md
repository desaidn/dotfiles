# tmux

The retained fallback and compatibility multiplexer in [dotfiles](../README.md). Herdr app is the normal daily workspace manager; start tmux directly when a tmux-specific workflow is needed rather than nesting it inside Herdr.

The version floor lives in the
[root dependency inventory](../AGENTS.md#homebrew-applications). The
configuration has no plugin manager or additional runtime dependencies; on
older versions, optional prompt-cursor settings keep their defaults.

## Usage

```bash
tmux new-session -A -s dev
```

The standard prefix is `Ctrl-b`. Use `Ctrl-b c` for a new window, `Ctrl-b "`
for panes above/below, and `Ctrl-b %` for panes side by side. New windows and
panes preserve the current directory; both are numbered from 1.

Reload the tracked configuration in an existing tmux session:

```bash
tmux source-file ~/.config/tmux/tmux.conf
```
