# Herdr app

Part of [dotfiles](../README.md). Herdr app is the daily terminal window and
workspace manager on macOS. Its window shows spaces, tabs, and panes;
herdr-core, driven with `hc`, runs the terminals and keeps them alive when the
window closes. Ghostty with [Herdr TUI](../herdr/README.md) stays installed on
the shelf as an alternative.

## Installation

The root installer installs a missing app with:

```sh
brew install --cask herdr-app
```

A compatible manual installation is preserved. The Homebrew cask requires
Apple Silicon; Intel Macs need a compatible source build installed beforehand.
The app handles Herdr core installation on first launch and its subsequent
updates. Dotfiles installation does not launch either program.

On macOS, the installer links `settings.json`, `themes/terminal.json`,
`keys.json`, the personal `keyboard` layout and preview, and `main.js` /
`mod.json` in the keyboard guide, numbered tabs, numbered agents, and
command status bar mods.
The default home is `~/.config/herdr-app`; `HERDR_APP_HOME` can select another
absolute directory. Existing personal files are backed up before linking.
Linux installation skips both the app and its configuration.

Fresh installs use the app's normal welcome flow and agent sorting; existing
`shared.json` preferences are preserved. Herdr owns the rest of its app home;
[AGENTS.md](AGENTS.md) records the ownership boundary.
Uninstall removes only the owned links; `--restore` can restore their
original files and leaves app state and installed packages.

Select the numbered layout once with `herdr-app do layout.switch --name keyboard`.
Herdr remembers that choice; the installer leaves your current layout selected.

## Work on another machine

Add a Linux machine, such as a remote development host, from Settings → Machines or the
sidebar's Add machine action. Any Host from `~/.ssh/config` works. Spaces on
that machine run their terminals there, and keep running when the laptop
sleeps or the window closes.

Adding the machine offers to copy `hc` there when it is missing or too old, so
dotfiles does not install herdr-core on Linux. `herdr-app` itself runs only on the Mac.
From the Mac, remote terminals have addresses such as `box/t7`. If SSH needs a
password or code again, run `hc machine login <name>` in a terminal;
`hc machine ls` shows each connection's state.

The connection carries a byte protocol, so the remote login must not print
anything to standard output. The zsh handoff to Fish happens only in
interactive shells and stays out of that path.

Programs that `hc run` starts by name inherit the core's environment rather
than the dotfiles shell setup. A core started over SSH reads only
`~/.zshenv`, so Homebrew tools may be missing from its `PATH`. Agents pass
their own with `env "PATH=$PATH" <program>`, as the agent skill below
describes. To fix it at the source, add Homebrew to `PATH` in `~/.zshenv` and
restart the core once with `hc server restart --fresh`, run from an SSH shell
outside Herdr so it picks up that environment; running terminals keep running.

## Agents

Agents in Codex, Claude Code, and pi load the shared
[`herdr-app` skill](../docs/agents/skills/herdr-app/SKILL.md) when they work in
Herdr app or with `hc`. It starts from the installed upstream guides,
`hc --skill` and `herdr-app --skill`, and adds this setup's layout, how to show
a tab from a remote machine, and pitfalls seen in earlier sessions. The
[shared agent instructions](../AGENTS.md#shared-agent-instructions) list where
it is installed.

## Appearance

The `terminal` palette uses a near-black background (`#0e0e0e`), white
foreground and cursor, and 16 ANSI colors, with a teal app accent.
Settings use JetBrains Mono at 14 for terminals, matching the
[Ghostty configuration](../ghostty/config), and the same font family for app
text so tabs and panels carry the TUI's monospace appearance. Zoom, sounds,
and contrast use app defaults. `terminal_opacity` controls blending within the
app's window. Selection uses Neovim's muted amber (`#6a4f1f`), preserving
colored text. The `keyboard` layout keeps Herdr's standard arrangement and
adds teal shortcut badges to tabs and agents.

## Keys

Press `Ctrl-b` (or click **Ctrl-b commands** in the status bar) to open the
[keyboard guide](mods/keyboard-guide/RECIPE.md), the single keyboard entry
point for Herdr commands.
It follows the Herdr TUI's prefix keys and updates its hints as you enter
navigation, agent selection, confirmation, or copy mode. Escape or Ctrl-[ cancels;
Backspace returns to the command list. The guide uses the terminal theme
and JetBrains Mono already configured here.

All keys below follow `Ctrl-b`; uppercase letters mean Shift.

| Keys | Action |
| --- | --- |
| `h j k l`, `Tab` / `Shift-Tab` | Focus left/down/up/right; cycle panes |
| `g` | Keep navigating: `h j k l` move panes, ↑/↓ move spaces, `p/n` move tabs, `[/]` move agents; Enter finishes |
| `v`, `-` or `"` | Split side by side; split above/below |
| `z`, `x` | Zoom pane; confirm closing pane |
| `c`, `p/n`, `1…9` | New, previous/next, or numbered tab |
| `T`, `X` | Rename tab; confirm closing tab |
| `N`, `W`, `D` | New space, rename space, confirm closing space |
| `w`, `G` | Search spaces/tabs inside the guide; new worktree dialog |
| `a`, `Shift-1…9` | Show numbered agents; focus one directly |
| `[` | Keyboard scroll and copy: move with `h j k l`, select with `v` or `V`, copy with `y` |
| `/` | Search the terminal |
| `b`, `s`, `:` | Sidebar, settings, search every available command inside the guide |
| `?` | Keyboard help inside the guide |
| `q` | Minimize the window while terminals keep running |
| `Ctrl-b` again | Send a literal Ctrl-b to the focused terminal |

In copy mode, `Ctrl-u/d` move a page, `g/G` go to the top/bottom, and
`0/$` move to line edges. Move to the selection's start, press `v`, extend it,
then press `y`. `V` starts with the current line selected. Escape clears the
selection and returns to the terminal. The compact copy popup keeps keyboard
focus; clicking outside also cancels it. Alternate-screen programs have no terminal scrollback, but
their visible screen can still be selected. Existing selections are preserved
on entry; `v` resets the anchor at the current moving endpoint. Fast sequences
are processed in order, after each native selection change is applied.

In command or place search, type to filter, use ↑/↓ or Ctrl-p/n to choose,
and Enter to run. Ctrl-b returns to the main hints; Escape closes. Search
includes actions beyond the short prefix list: swapping panes, moving tabs,
pinning agents, layouts, themes, zoom, updates, and window controls. Close,
reset, quit, and update actions show their consequence before confirmation.
Settings and name prompts use Herdr's native dialogs.

Tab badges `1…9` mean `Ctrl-b`, then that number. Agent badges `⇧1…⇧9`
mean `Ctrl-b`, then Shift plus that number (or `Ctrl-b a`, then the number).
They remain visible in the `keyboard` layout, including the narrow sidebar.
Agent numbers use pins first, then space/tab order, as listed by `Ctrl-b a`;
status changes can move a sidebar row without changing its shortcut number.
Kept child agents carry the same badge in their nested row. Only the first
nine targets have number shortcuts; navigation mode reaches the rest. Settled
tabs and background child agents have no digit shortcut badge. The TUI wins where its
keys conflict with tmux: `b` is the sidebar, and `%` is Shift-5 for agent 5.
Herdr app does not expose keyboard pane resizing, pane renaming, or editing
scrollback. Their TUI keys explain the available alternatives.

Herdr's former global shortcuts, including `Cmd+Shift+P`, `Cmd+/`, and
`Cmd+t`, are removed. Clipboard shortcuts, selection, and terminal text editing
remain available; `Cmd-f` is replaced by `Ctrl-b /`. Dotfiles owns `keys.json`,
so reconcile upstream changes deliberately when upgrading. The app-owned
macOS menu remains native; personal mods cannot replace its menu commands.

## Share the keyboard guide

Build a standalone folder into a new destination:

```sh
./herdr-app/package-keyboard-guide.sh /tmp/herdr-keyboard-guide
```

It contains the guide, the optional `keyboard` layout with its numbered tab
and agent mods, the command status bar, a one-binding `keys.json` fragment,
`RECIPE.md`, `preview.png`, the repository's MIT license, and the cloned panels'
upstream Apache-2.0 license and attribution. It uses the
recipient's theme and native Herdr mod runtime. The recipe explains installation, limitations, and
manual keyboard checks. The command prepares files locally; it does not
publish a repository or submit to the Herdr mod directory.

## Validation

```sh
./tests/install_test.sh
bash tests/herdr_keyboard_test.sh
herdr-app check herdr-app/mods/keyboard-guide
herdr-app check herdr-app/mods/keyboard-tabs
herdr-app check herdr-app/mods/keyboard-agents
herdr-app check herdr-app/mods/keyboard-status
```

The installer suite covers provisioning, personal links, state preservation,
and uninstall. It does not require the app or a desktop/GPU environment.

For native keyboard and copy lifecycle regression checks:

```sh
HERDR_NATIVE_SOURCE=/path/to/prepared/herdr-app \
ZIG=/path/to/zig-0.16.0 \
HERDR_NATIVE_WORKSPACE=/tmp/herdr-keyboard-native \
bash tests/herdr_keyboard_native_test.sh
```

This opt-in test requires the pinned official Herdr app v0.1.16 checkout with
its Ghostty submodule, an active installed Rust toolchain, Zig 0.16.0, and
prepared Cargo dependencies. Run the script with `--help` for details. It
copies the pinned source into an owned scratch workspace and runs Cargo
offline; it does not install tools or change the prepared checkout. The first
build is substantial; reuse the workspace to keep later runs quick.

The native suite sends real keyboard and click events through Herdr's mod
runtime and terminal view on GPUI's test platform, with an offline core and
isolated homes. It checks Escape, focus restoration, copied text, rapid input,
and repeated open/close cycles without touching the running app. Keep this
coverage for lifecycle changes: the API-double tests cannot catch keys going
to the wrong focus target.

For a running-window check, read `herdr-app --skill`, inspect
`herdr-app status`, and use `herdr-app shot /tmp/herdr-app.png`.

After editing a linked mod or layout in this checkout, refresh its watched link so
the running app loads the new source, then check status again:

```sh
touch -h "${HERDR_APP_HOME:-$HOME/.config/herdr-app}/mods/keyboard-guide/main.js"
herdr-app status
```
