# tmux

The retained fallback and compatibility multiplexer in [dotfiles](../README.md). Herdr is the normal daily workspace manager; start tmux directly when a tmux-specific workflow is needed rather than nesting it inside Herdr.

## Usage

```bash
tmux new-session -A -s dev
```

Reload the tracked configuration in an existing tmux session:

```bash
tmux source-file ~/.config/tmux/tmux.conf
```
