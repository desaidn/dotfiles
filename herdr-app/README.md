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

On macOS, the installer links `settings.json` and `themes/terminal.json`.
The default home is `~/.config/herdr-app`; `HERDR_APP_HOME` can select another
absolute directory. Existing personal files are backed up before linking.
Linux installation skips both the app and its configuration.

Herdr manages its keymap, generated guides, type definitions, shipped
mods/layouts, and runtime state. Fresh installs use the app's normal welcome
flow and agent sorting; existing `shared.json` preferences are preserved.
Uninstall removes only the two owned links; `--restore` can restore their
original files and leaves app state and installed packages.

## Work on another machine

Add a Linux machine, such as a cloud desktop, from Settings → Machines or the
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
than the dotfiles shell setup, so Homebrew tools may be missing from `PATH`.
Run them through `zsh -ic 'exec …'`, as the agent skill below describes.

## Agents

Agents in Codex, Claude Code, and pi load the shared
[`herdr-app` skill](../docs/agents/skills/herdr-app/SKILL.md) when they work in
Herdr app or with `hc`. It starts from the installed upstream guides,
`hc --skill` and `herdr-app --skill`, and adds this setup's layout, how to show
a tab from a remote machine, and pitfalls seen in earlier sessions. The
[root README](../README.md#shared-agent-instructions) lists where it is
installed.

## Appearance

The `terminal` palette matches Ghostty's effective background (`#0e0e0e`),
white foreground and cursor, and 16 ANSI colors, with a teal app accent.
Settings use JetBrains Mono at 14 for terminals, matching the
[Ghostty configuration](../ghostty/config), and the same font family for app
text so tabs and panels carry the TUI's monospace appearance. Zoom, sounds,
and contrast use app defaults.

Herdr app 0.1.13 cannot reproduce Ghostty's 90% background opacity and macOS
glass blur. Its `terminal_opacity` controls blending within the app's window.
Layout spacing and selection rendering use Herdr's defaults.

## Keys

Use Herdr's native macOS shortcuts. Open its keybinding help with `Cmd+/`
or the command palette with `Cmd+Shift+P` to see the installed version's
commands. Dotfiles does not manage `keys.json`, so untouched defaults can
receive upstream shortcut updates.

## Validation

```sh
./tests/install_test.sh
```

The installer suite covers provisioning, personal links, state preservation,
and uninstall. It does not require the app or a desktop/GPU environment.

For a running-window check, read `herdr-app --skill`, inspect
`herdr-app status`, and use `herdr-app shot /tmp/herdr-app.png`.
