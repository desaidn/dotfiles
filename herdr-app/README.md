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

On macOS, the installer links `keys.json`, `settings.json`,
`themes/terminal.json`, and the two `mods/legacy-prefix/` files individually.
The default home is `~/.config/herdr-app`; `HERDR_APP_HOME` can select another
absolute directory. Existing personal files are backed up before linking.
Linux installation skips both the app and its configuration.

Generated guides, type definitions, shipped mods/layouts, and runtime state
remain local. A fresh `shared.json` starts with agents grouped by space and
the welcome screen completed, matching the old Herdr preferences. An existing
`shared.json` is preserved. Uninstall removes only owned links; `--restore`
can restore their original files and leaves app state and installed packages.

## Appearance

The original migrated `terminal` palette uses a `#0e0e0e` background, white
foreground and cursor, and a teal accent. Settings retain the migrated dark
appearance, zoom, sound, and minimum-contrast values. Fonts and other appearance
options use the app defaults.

## Keys

Native macOS app bindings remain available. Press `Ctrl+B`, then a prefix key:

| Key | Action |
| --- | --- |
| `1`–`9` | Select a tab |
| `Shift+1`–`9` | Focus an agent; pinned agents first, then space order |
| `h`, `j`, `k`, `l` | Focus a pane |
| `v`, `-` | Split right, down |
| `x`, `z` | Close, zoom a pane |
| `c`, `p`, `n` | New, previous, next tab |
| `Shift+T`, `Shift+X` | Rename, close a tab |
| `Shift+N`, `w` | New space, space picker |
| `Shift+W`, `Shift+D` | Rename, close a space |
| `b`, `s`, `?`, `q` | Sidebar, settings, app keys, hide app |
| `Escape`, `Ctrl+B` | Cancel the prefix |

The prefix panel explains unavailable TUI actions. The TUI's `ui.toast.delivery`
setting has no equivalent in this app release; app alert sounds retain their
default enabled setting.

## Validation

```sh
./tests/install_test.sh
nvim --clean --headless -l tests/herdr_app_test.lua
```

The second command checks JSON and prefix behavior with Herdr's native mod
checker against temporary copies and an isolated app home. It requires a
working Herdr app installation and desktop/GPU environment. The native checker
loads and renders once; it does not prove every later UI state works.

For a running-window check, read `herdr-app --skill`, inspect
`herdr-app status`, and use `herdr-app shot /tmp/herdr-app.png`.
