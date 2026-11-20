# Herdr app

Follow the [repository guidance](../AGENTS.md). Herdr app is the daily
workspace. [README.md](README.md) is the front page; the
[keyboard recipe](mods/keyboard-guide/RECIPE.md) owns detailed usage and
standalone installation. This file owns development constraints, file
ownership, and validation.

Homebrew owns the macOS app; the app installs and updates Herdr
core, including the `hc` copy it places on SSH-connected machines. Do not
provision herdr-core from the dotfiles installer. Keep the shelved Herdr TUI
independent.

To operate the running window or its terminals, use the shared
[`herdr-app` skill](../docs/agents/skills/herdr-app/SKILL.md). Keep that skill
a thin layer over the installed `hc --skill` and `herdr-app --skill` guides:
record this setup's facts and observed pitfalls, not copies of upstream
command references.

Link only `settings.json`, `themes/terminal.json`, `keys.json`,
`layouts/keyboard.{json,svg}`, and `main.js` / `mod.json` in each of
`mods/keyboard-guide/`, `mods/keyboard-tabs/`, `mods/keyboard-agents/`, and
`mods/keyboard-status/`.
The app home, `themes/`, `layouts/`, `mods/`, and those mod folders must remain
real directories. Herdr owns generated
guides, type definitions, shipped layouts/mods, and runtime state. Do not seed
or overwrite `shared.json`.

The personal keymap gives Herdr commands one entry point: `Ctrl-b`.
Keep terminal clipboard and text-editing bindings; do not reintroduce competing
global app shortcuts. `Cmd-f` is replaced by `Ctrl-b /`. An edited keymap no
longer receives upstream updates automatically; reconcile those deliberately.
The keyboard guide's JavaScript is Herdr's
native mod format. Keep it self-contained: relative imports through managed
file symlinks are not supported by Herdr. Use the installed app's generated
types and command inventory, and theme colors rather than a separate palette.
Keep rendering event-driven rather than polling, and use `cx` only within
its callback.

The `keyboard` layout and numbered tab/agent panels are personal clones of
Herdr 0.1.16. Keep changes to the cloned panels limited to shortcut badges
and routing the status bar's Commands button to the guide;
reconcile upstream changes deliberately. Badges must match the guide's
targets: non-settled tabs from left to right, and selectable agent rows from
top to bottom, limited to nine. Agent numbers follow sorting, pins, nesting
and folding; hidden rows and repeated child rows consume no number. The
sidebar publishes its displayed order for the guide and shortcuts to share.
Reuse shipped icons; do not edit the shipped mods or layout.

The guide owns search, help, and prefix dispatch. Search entries derive the
prefix actions from their existing rows and supplement them with available
native actions and named targets. Never reopen `app.palette` or `app.help`
from the guide. Native settings and argument dialogs remain action destinations.
Before offering worktree removal, run `git rev-parse --absolute-git-dir`
and `git rev-parse --path-format=absolute --git-common-dir` in the target
folder on its machine. Refuse the main checkout (equal normalized paths) or
failed checks; only a linked worktree may proceed to the native dialog.

Herdr's `run()` queues mutations; getters read published snapshots. Copy mode
serializes key intents and sends a private command back through the same FIFO
queue before reading selection endpoints. Keep this acknowledgement boundary:
immediate read-after-run tests hid the original broken movement. Capture the
terminal before opening the copy strip; cancellation discards queued input.
Keep the copy strip a popup so native Escape and outside-click dismissal own
its lifetime, centered like the main guide. A floating window can lose keyboard
focus without closing.

Preserve custom files, foreign links, and redirected mod directories.

## Validation

Run `bash tests/herdr_keyboard_test.sh` for the guide's keyboard behavior and
agreement between visible badges and shortcut destinations.
The shell runner uses Node (owned by Mise) for a focused JavaScript fixture
with app API doubles; it does not send keys to a running terminal. Also run
native API/render checks on all four managed mods:

```sh
herdr-app check herdr-app/mods/keyboard-guide
herdr-app check herdr-app/mods/keyboard-tabs
herdr-app check herdr-app/mods/keyboard-agents
herdr-app check herdr-app/mods/keyboard-status
```

Run `./tests/install_test.sh` for installer or link changes. That suite covers
provisioning, personal links, state preservation, and uninstall without the
app or a desktop/GPU environment.

For keyboard focus, dismissal, or copy lifecycle changes, also run:

```sh
HERDR_NATIVE_SOURCE=/path/to/prepared/herdr-app \
ZIG=/path/to/zig-0.16.0 \
HERDR_NATIVE_WORKSPACE=/tmp/herdr-keyboard-native \
bash tests/herdr_keyboard_native_test.sh
```

This requires the pinned official Herdr app v0.1.16 checkout with its Ghostty
submodule, an active installed Rust toolchain, Zig 0.16.0, and prepared Cargo
dependencies. Run the script with `--help` for details. It copies the source
into an owned scratch workspace and runs Cargo offline without installing
tools or changing the prepared checkout. Reuse the workspace after the
substantial first build.

The native suite sends real keyboard and click events through Herdr's mod
runtime and terminal view on GPUI's isolated test platform with an offline
core. It checks Escape, focus restoration, copied text, rapid input, and
repeated open/close cycles without touching the running app. API doubles
alone cannot establish that Escape reaches the guide.

Neither automated suite replaces the
[manual keyboard and visual checks](mods/keyboard-guide/RECIPE.md#done-when).
Before validating changes in the running window, read `herdr-app --skill`,
then inspect `herdr-app status` and take a screenshot with
`herdr-app shot /tmp/herdr-app.png`. Preserve its focus and sessions; do not
launch, stop, or restart the app or core during installation.

After changing a linked mod or layout, refresh that watched link so the app
loads the new source, then check status again. For the guide:

```sh
touch -h "${HERDR_APP_HOME:-$HOME/.config/herdr-app}/mods/keyboard-guide/main.js"
herdr-app status
```

The native check alone does not reload an already-running copy.

`package-keyboard-guide.sh` assembles the guide and optional numbered layout
under a new destination, including a minimal key fragment, recipe and preview. It does not publish,
install, overwrite a destination, or copy the full personal keymap.
