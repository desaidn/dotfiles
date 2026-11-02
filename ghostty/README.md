# ghostty

Part of [dotfiles](../README.md).

This configuration is installed only on macOS.

## Installation

The root installer provisions the `ghostty` and `font-jetbrains-mono`
Homebrew casks when they are missing. A manually installed `Ghostty.app` or
JetBrains Mono font is preserved. Ghostty must meet the
[root compatibility requirement](../README.md#homebrew-applications); upgrade
an incompatible installation before rerunning the installer.

The `font-jetbrains-mono` cask supplies the font selected in `ghostty/config`.

The configured native glass appearance requires macOS 26 or newer. On earlier
macOS versions, Ghostty accepts the setting and uses its regular background-blur
path. See [Ghostty's background-blur reference](https://ghostty.org/docs/config/reference#background-blur).

Scrollback uses Ghostty's default byte budget. The explicit Option-as-Alt setting
keeps terminal input consistent across keyboard layouts; FlashSpace owns global
Option shortcuts. Word navigation follows Ghostty's native shortcuts. The Fish
configuration loads Ghostty's shell integration after the Zsh handoff so the
enabled SSH environment and terminfo support remains available.
