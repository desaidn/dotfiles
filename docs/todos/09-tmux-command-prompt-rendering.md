# Fix tmux Command-Prompt Rendering

## Outcome

Opening tmux's command prompt should show a clean, fully painted prompt line rather than text that appears to overwrite or mix with the session name underneath.

## Reproduction / current state

With the current configuration, press `C-b :`. The command prompt uses the same blue styling as the rest of the tmux chrome, but the existing session-name/status content remains visible in unused cells and makes the prompt look like it is overwriting the status line.

The cause has been isolated to [`tmux.conf`](../../tmux/tmux.conf): the custom `message-style` sets background, foreground, and bold attributes but omits tmux's upstream full-line `fill` attribute. On the installed tmux 3.7b, upstream defaults include a fill color, and adding `fill=#a6dbff` to the current style parses successfully and produces the intended effective option.

tmux intentionally draws the command prompt on a status line; the issue is incomplete repainting after customizing the message style, not the prompt's location.

## Scope

- Confirm the behavior in an isolated tmux server using the current repo config.
- Verify the `fill` style syntax and minimum supported tmux version against current upstream documentation.
- Restore a full-width fill using the existing tmux chrome color, or choose an equally small compatible correction if upstream behavior has changed.
- Keep command prompts and ordinary status messages legible under the existing theme.
- Update scoped documentation only if a new compatibility requirement is introduced.

## Boundaries / non-goals

- Do not redesign the tmux status line, session-name format, or overall color palette.
- Do not add a second status line merely to host prompts.
- Do not move or rename the tmux prefix/command binding.
- Do not change Neovim mode colors or Ghostty configuration.
- Do not add a tmux plugin for a native style issue.
- Do not assume installed tmux 3.7b is the portability floor without checking the repo's current compatibility intent.

## Open decisions

- Is `fill=<colour>` supported by the oldest tmux version this repository intends to support?
- Should `message-command-style` remain at its upstream/default value, or should it deliberately match the corrected prompt style?
- Does the same incomplete fill affect ordinary `display-message` output or only interactive command prompts?

## Acceptance criteria

- `C-b :` displays a fully painted prompt line with no visible session-name/status remnants.
- Typing, backspacing, cancelling, and executing a command redraw the status line correctly.
- Ordinary tmux messages remain readable and restore the normal status line afterward.
- The configuration parses successfully in a clean isolated tmux server.
- The chosen syntax is compatible with the documented supported tmux version, or any raised minimum is explicitly justified and documented.
- No unrelated status-line or keybinding behavior changes.

## Verification

Run the syntax check documented by [`tmux/AGENTS.md`](../../tmux/AGENTS.md):

```sh
tmux -f ~/.config/tmux/tmux.conf new-session -d -s test \; kill-session -t test
```

Prefer a unique socket/session name during development so the test cannot affect a real server. Inspect the effective `message-style`, then manually exercise:

- `C-b :`, typing and backspacing.
- `Esc` cancellation.
- A harmless command such as `display-message`.
- Normal redraw of the session/window status afterward.

## Starting points / references

- [`tmux/tmux.conf`](../../tmux/tmux.conf) — current message/status styles.
- [`tmux/AGENTS.md`](../../tmux/AGENTS.md) — compatibility and verification guidance.
- [tmux manual](https://man.openbsd.org/tmux.1) — current style and message-line semantics.
