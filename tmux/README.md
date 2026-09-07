# tmux

The retained fallback and compatibility multiplexer in [dotfiles](../README.md). Herdr is the normal daily workspace manager; start tmux directly when a tmux-specific workflow is needed rather than nesting it inside Herdr.

Requires tmux 3.5 or newer for `extended-keys-format`. The configuration has no
plugin manager or additional runtime dependencies. Prefer the latest stable
release; on older versions, optional prompt-cursor settings keep their defaults.

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
