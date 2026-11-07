# Herdr app

Part of [dotfiles](../README.md). Herdr app is a promising personal experiment
that combines the terminal window and workspace manager on macOS. Ghostty with
Herdr TUI remains the daily setup.

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
