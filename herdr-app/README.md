# Herdr app

Part of [dotfiles](../README.md). Herdr app is the daily terminal window and
workspace manager on macOS. Its window shows spaces, tabs, and panes;
herdr-core, driven with `hc`, runs the terminals and keeps them alive when the
window closes. Ghostty with [Herdr TUI](../herdr/README.md) stays installed on
the shelf as an alternative.

## Quick start

Follow the repository's [installation guide](../README.md#quick-start).
On macOS, it installs Herdr app and links this configuration under
`~/.config/herdr-app` (or `HERDR_APP_HOME`). Open the app, complete its welcome
flow, then select the numbered layout once:

```sh
herdr-app do layout.switch --name keyboard
```

Herdr remembers that choice. See the repository's
[rollback guide](../README.md#rollback) to remove or restore managed links.

## Work on another machine

Add a Linux machine from Settings → Machines or the sidebar's Add machine
action. Any Host from `~/.ssh/config` works. Spaces on that machine run
their terminals there and keep running when the laptop sleeps or the window
closes.

Adding the machine offers to copy `hc` there when it is missing or too old.
From the Mac, remote terminals have addresses such as `box/t7`. If SSH needs
a password or code again, run `hc machine login <name>` in a terminal;
`hc machine ls` shows each connection's state.

Remote logins must not print to standard output. For terminal launches and
environment troubleshooting, see the
[`herdr-app` skill](../docs/agents/skills/herdr-app/SKILL.md).
If remote launches cannot find Homebrew tools, the core may be missing their
`PATH`: it reads `~/.zshenv`. After correcting that file, run
`hc server restart --fresh` from an SSH shell outside Herdr to reload the
environment; running terminals keep running.

## Appearance

The [terminal palette](themes/terminal.json) uses a near-black background,
white text, amber selection, and a teal accent. [Settings](settings.json) use
JetBrains Mono at 14 for terminals. The `keyboard` layout keeps Herdr's
standard arrangement and adds shortcut badges to tabs and agents.

## Keys

Press `Ctrl-b` (or click **Ctrl-b commands** in the status bar) to open the
[keyboard guide](mods/keyboard-guide/RECIPE.md), the single keyboard entry
point for Herdr commands. Escape cancels; Backspace returns to the command
list.

All keys below follow `Ctrl-b`; uppercase letters mean Shift.

| Keys | Action |
| --- | --- |
| `h j k l`, `Tab` / `Shift-Tab` | Focus left/down/up/right; cycle panes |
| `g` | Stay in navigation mode |
| `v`, `-` | Split side by side; split above/below |
| `c`, `p/n`, `1…9` | New, previous/next, or numbered tab |
| `a`, `Shift-1…9` | Show numbered agents; focus one directly |
| `[`, `/` | Scroll and copy; search the terminal |
| `w` | Search spaces and tabs |
| `:` | Search commands; search for `help` to show full help |
| `Ctrl-b` again | Send a literal Ctrl-b to the focused terminal |

Numbered tabs run left to right and agents top to bottom, updating as they
move. The [keyboard guide](mods/keyboard-guide/RECIPE.md#how-it-behaves)
has the complete key list, selection rules, copy controls, and limitations.
Terminal clipboard and text-editing shortcuts remain available.

## Share the keyboard guide

Build a standalone folder into a new destination:

```sh
./herdr-app/package-keyboard-guide.sh /tmp/herdr-keyboard-guide
```

The folder includes the guide, optional numbered layout, key fragment,
preview, licenses, and a self-contained installation recipe. The command
prepares files locally; it does not publish them.

## Validation

See [AGENTS.md](AGENTS.md) for development constraints and
[validation commands](AGENTS.md#validation).
