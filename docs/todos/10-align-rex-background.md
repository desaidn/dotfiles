# Align Rex's background with Ghostty and Herdr

## Outcome

Give Rex a flat, opaque dark background consistent with Ghostty + Herdr TUI
and Herdr app.

## Current evidence

- Commit `8212349242619048df47253bf95d64c9c8d5184f` reverted Ghostty's glass
  background on 2026-11-07, restoring `#000000` at full opacity and removing blur.
- `rex/macos.sh` still enables `Workspace.usesPaneGlass`, and the Rex README
  lists pane glass as on.
- Herdr app's tracked terminal theme uses `#0e0e0e`. The intended alignment is
  an opaque appearance; the existing backgrounds are not identical colors.
- Rex preferences are applied manually through a temporary macOS `defaults`
  workaround, outside the root installer.

## Scope and boundaries

Update Rex's tracked appearance preferences and documentation as needed to
remove the glass effect. Preserve unrelated preferences and Rex's manual,
experimental setup. Changes to Ghostty and Herdr are outside this item.

## Open decisions

Check whether removing pane glass achieves the intended appearance with Rex's
current dark theme, or whether its background also needs adjustment.

## Acceptance criteria

- Rex's dark terminal panes have an opaque background without glass or blur.
- A visual comparison confirms consistency with Ghostty + Herdr TUI and
  Herdr app.
- The tracked Rex preferences and README agree.

## Verification

Check the current Rex version and upstream preference support, apply the
updated preferences manually on macOS, and inspect the result after reopening
Rex. Run `sh -n rex/macos.sh` and `git diff --check` for the implementation.

## Starting points

- [`rex/macos.sh`](../../rex/macos.sh)
- [`rex/README.md`](../../rex/README.md)
- [`ghostty/config`](../../ghostty/config)
- [`herdr-app/themes/terminal.json`](../../herdr-app/themes/terminal.json)
- [Rex documentation](https://www.superlogical.com/rex/docs)
