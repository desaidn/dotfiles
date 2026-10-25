# Rex

Part of [dotfiles](../README.md).

Rex is a personal experiment as a terminal and multiplexer. It could eventually
replace both Ghostty and Herdr for personal use; this is an early impression
while testing. Work continues to use Ghostty as the terminal and Herdr as the
multiplexer.

See the [Rex documentation](https://www.superlogical.com/rex/docs) for upstream
setup and usage.

## Setup

Install Rex Beta manually when trying it. The root installer does not install
Rex or apply these preferences. JetBrains Mono is supplied by the existing
[macOS dependency setup](../README.md#homebrew-applications).

From the repository root, manually apply the tracked appearance preferences:

```sh
sh rex/macos.sh
```

| Preference | Value |
| --- | --- |
| Terminal font | JetBrains Mono, 14 pt; smoothing off |
| Dark theme | Static Noir |
| Light theme | Merino Light |
| Interface style | `blendTheme` |
| Pane glass | On |
| Pane density | Comfortable |
| Tabs fill available space | Off |

The script writes these values to the `com.superlogical.rex` macOS preferences
domain and leaves other preferences local. Quit and reopen Rex if the running
app does not pick up the change. The script does not restart it.

## Configuration boundary

`macos.sh` is a temporary `defaults` workaround using preference keys, not a
documented stable Rex configuration API. It is run manually and was checked
with Rex Beta 0.1.0 build 1381 on 2026-10-23. GUI preferences such as the font
live in macOS user defaults. Rex's
[`~/.config/rex/init.lua`](https://www.superlogical.com/rex/docs/customize/config)
handles keybindings, actions, and other Lua configuration. Support for putting
GUI settings in a configuration file is an
[accepted feature request](https://discord.com/channels/1546797889009881158/1556737365475598464).

Track only intentional preference overrides here, rather than the whole
`~/Library/Preferences/com.superlogical.rex.plist`, which also contains mutable
app state. Do not symlink that plist into this repository. Add an `init.lua`
when there are actual Lua settings to track.
