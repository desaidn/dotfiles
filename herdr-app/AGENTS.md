# Herdr app

Follow the [repository guidance](../AGENTS.md). Herdr app is the daily
workspace. Homebrew owns the macOS app; the app installs and updates Herdr
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

The `keyboard` layout and numbered tab/agent panels are personal clones of
Herdr 0.1.16. Keep changes to the cloned panels limited to shortcut badges
and routing the status bar's Commands button to the guide;
reconcile upstream changes deliberately. Badges must match the guide's
targets: non-settled tabs, and agents in model order with pins first, limited
to nine. Sidebar priority sorting and nested children must not renumber those
targets. Reuse shipped icons; do not edit the shipped mods or layout.

The guide owns search, help, and prefix dispatch. Search entries derive the
prefix actions from their existing rows and supplement them with available
native actions and named targets. Never reopen `app.palette` or `app.help`
from the guide. Native settings and argument dialogs remain action destinations.

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

Run `./tests/install_test.sh` for installer or link changes. Read
`herdr-app --skill` before validating changes in the running window, then
inspect `herdr-app status` and a screenshot. Preserve its focus and sessions;
do not launch, stop, or restart the app or core during installation.

Run `bash tests/herdr_keyboard_test.sh` for the guide's keyboard behavior and
agreement between visible badges and shortcut destinations.
The shell runner uses Node (owned by Mise) for a focused JavaScript fixture
with app API doubles; it does not send keys to a running terminal. Run
`herdr-app check` on each of the four managed mod folders for native
API/render checks.
Neither replaces the live keyboard and visual checks in the guide's recipe.
For keyboard focus, dismissal, or copy lifecycle changes, also run the native
regression with `tests/herdr_keyboard_native_test.sh` against its pinned,
prepared Herdr source; see [validation](README.md#validation). It uses real
key events and terminal views on an isolated test platform with an offline
core. API doubles alone cannot establish that Escape reaches the guide.
After changing a linked source, refresh the link as described in
[the validation guide](README.md#validation); the native check alone does not
reload an already-running copy.

`package-keyboard-guide.sh` assembles the guide and optional numbered layout
under a new destination, including a minimal key fragment, recipe and preview. It does not publish,
install, overwrite a destination, or copy the full personal keymap.
