---
name: herdr-app
description: Use when running inside Herdr app or herdr-core terminals (HC_TERMINAL_ID is set), or when asked to open, show, place, or focus a tab, pane, space, review, or agent in Herdr app, or to start, message, wait on, or clean up terminals and agents with hc. Covers the macOS window and remote machines such as a Linux cloud desktop.
---

# Herdr app and hc

Herdr app is the daily workspace. Its window shows spaces, tabs, and panes.
herdr-core, driven with `hc`, runs the terminals and keeps them alive when the
window closes. Use `hc` to run, message, wait on, and clean up programs. Use
`herdr-app` only to change what the person sees.

Herdr TUI (`herdr`, with `herdr --skill`) is a separate, older program kept as
a fallback. Its workspace and pane IDs, `HERDR_*` variables, and commands do
not apply to Herdr app. Use it only when the task is actually running there.

## 1. Read the installed guides first

Run these and read the whole output. Do not pipe them through `head` or
`tail`; important rules sit at the end.

```sh
hc --skill                 # always
herdr-app --skill          # only where herdr-app is installed
```

They match the installed versions. For command syntax, they win over this
file. This file adds how this setup is arranged and what the user expects.
Use `hc <command> --help` and `herdr-app commands` for exact arguments rather
than guessing subcommands.

## 2. Work out where you are

```sh
echo "$HC_TERMINAL_ID"            # your terminal address, such as t27
hc get "$HC_TERMINAL_ID"          # labels: herdr.space and herdr.tab
command -v herdr-app              # present only where the window runs
```

- **The window's machine (the Mac).** `herdr-app` is on `PATH`. You can
  inspect the window with `herdr-app ls` and `herdr-app status` and change it
  with `herdr-app do`. Remote terminals appear as `machine/t7`; use that full
  address with `hc`.
- **A remote machine (the Linux cloud desktop).** `herdr-app` is not
  installed, and that is expected. The Mac's app reaches this machine over
  SSH, and its core runs the terminals here. Use `hc` only. Your own labels
  still name the space and tab the person sees you in.
- **Not in Herdr app.** If `HC_TERMINAL_ID` is unset, you are in Herdr TUI,
  tmux, or a plain terminal. Follow that environment's guidance instead.

The labels from `hc get "$HC_TERMINAL_ID"` are the source of truth for your
location. Inherited `HERDR_*` variables and `HERDR_BIN_PATH` belong to Herdr
TUI and can be stale; do not use them to find a destination.

## 3. Show something to the person

Create spaces, tabs, and splits only when the person asks; they appear at
once. Open exactly what was asked for, with a clear name. Do not add extra
tabs for documentation or context. If a request such as "side by side" could
mean a split of the current tab or a new tab, ask before creating anything.
Do not switch the visible tab or focus unless asked.

**On the window's machine**, read IDs from `herdr-app ls`, then act on them:

```sh
herdr-app do tab.new --space "$space" --name "review/feature" \
  --folder "$checkout" --argv '["zsh", "-ic", "exec nvim -c \"HunkReview BASE HEAD\""]'
herdr-app ls                      # confirm the new tab and its terminal
```

**On a remote machine**, start the program with `hc` and label it with your
own space. Without `herdr.tab`, the app gives it a new tab in that space:

```sh
space=$(hc get "$HC_TERMINAL_ID" --json | jq -r '.labels["herdr.space"]')
hc run --bg --name review-feature --outlive-parent --no-notify \
  --cwd "$checkout" --label "herdr.space=$space" \
  -- zsh -ic 'exec nvim -c "HunkReview BASE HEAD"'
```

`--outlive-parent` keeps the tab open after your session ends. Names allow
1–32 characters from `a-z`, `0-9`, `-`, and `_`. Leave
`herdr.space` off for background workers that nobody needs to see; unlabeled
terminals stay hidden. If labeling is unavailable, the person can still use
the app's "keep" action on the terminal (`terminal.keep` on the Mac).

A successful reply only means the terminal was created. Confirm the program
started with `hc get <t>` and `hc read <t> --lines 0` before reporting it.
For reviews, the [development workflow](../../development-workflow.md) still
owns Hunk verification, findings, and approval.

## 4. Start programs with the right environment

An explicit program started by `hc run` inherits the core's environment, not
your shell's startup files. Homebrew and Mise tools such as `nvim`, `hunk`, and
language runtimes may then be missing. Symptoms are `spawn_failed: cannot
start "nvim"` or Neovim reporting `'hunk' is not executable`.

Run such programs through an interactive zsh, which loads the dotfiles PATH
without handing off to Fish:

```sh
hc run --bg --name tests --cwd "$checkout" -- zsh -ic 'exec make test'
```

`hc run` with no program already starts the machine's own shell.

## 5. Drive agents and terminals

Follow `hc --skill` for delegation, waiting, and reports. In this setup:

- Start Codex as `codex --no-daemon`, including in templates. Otherwise its
  commands run outside hc.
- Run pi and other agents interactively, never in one-shot print mode.
- `hc send` wraps text as `<hc from="t27">…</hc>`. That suits a task for an
  agent but breaks slash commands such as `/quit` and shell input. Type those
  with `hc keys <t> …` instead; to leave Codex, press `ctrl+c` twice.
- Wait with `hc wait`; never sleep or poll. A timeout is a check-in.
- Terminals the person opened are not your children. Wait on them with
  `hc wait <t>` rather than `--children`, and never kill or remove them.
- Clean up only terminals you started, once their results are in.
- Never stop or restart the person's app or core, or `hc server`, unless
  asked. Tests need their own `HC_SESSION` and scratch XDG paths.
- `blocked` means a person must decide. Read the screen and ask; do not use
  `hc send --force` to get past a permission prompt.

## 6. Harness notes

- **Codex.** Its sandbox blocks the Unix sockets used by `hc`, `herdr`, and
  `hunk`, which fail with `Operation not permitted`. Request escalation for
  those commands with a short justification.
- **Claude Code.** Background or resumed sessions can inherit another pane's
  `HERDR_*` variables; locate yourself from `hc get "$HC_TERMINAL_ID"`.
- **pi.** Loads this skill from `~/.agents/skills`, the same location Codex
  uses.
