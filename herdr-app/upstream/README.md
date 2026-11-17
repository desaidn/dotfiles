# Herdr source attribution

The keyboard package includes files derived from
[Herdr app v0.1.16](https://github.com/herdrdev/herdr-app/tree/v0.1.16),
licensed under Apache-2.0. [LICENSE-herdr-app-0.1.16](LICENSE-herdr-app-0.1.16)
is an unchanged copy of that release's `LICENSE`.

Changes by Dhairya Desai for this keyboard package:

| Package files | Upstream source | Changes |
| --- | --- | --- |
| `mods/keyboard-tabs/` | `defaults/mods/tabs/` | Add tab shortcut badges and refer to shipped icon paths. |
| `mods/keyboard-agents/` | `defaults/mods/agents/` | Add matching agent shortcut badges, including nested and narrow-sidebar rows. |
| `mods/keyboard-status/` | `defaults/mods/workspace-status/` | Replace the Commands entry with Ctrl-b commands, opening the keyboard guide. |
| `layouts/keyboard.json` | `defaults/layouts/main.json` | Wire the tab, agent and status blocks to these personal mods and add preview/source metadata. |

The cloned files retain their upstream Apache-2.0 license. The package's
root `LICENSE` is the dotfiles MIT license; it covers the original keyboard
guide and original supporting files, and does not relicense the Herdr code.

The upstream source has no separate `NOTICE` file or file-specific notices
in these cloned sources. Its `THIRD-PARTY-NOTICES` lists application
dependencies, fonts, icons and other bundled native assets. Those assets are
not copied into this package: the mods use the runtime and shipped icons
from the recipient's installed Herdr app. The original layout preview
`layouts/keyboard.svg` contains no copied upstream artwork.
