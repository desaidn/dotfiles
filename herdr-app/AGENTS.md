# Herdr app

Follow the [repository guidance](../AGENTS.md). Homebrew owns the macOS app;
the app installs and updates Herdr core. Keep the existing Herdr TUI independent.

Link only the personal files listed in `install.sh`. The app home and its
`themes/` and `mods/` containers must remain real directories. Generated guides,
type definitions, shipped layouts/mods, and runtime state stay machine-local.
Initialize `shared.json` only when absent; never link or overwrite it.

Before changing a mod, read `herdr-app --skill` and the installed app home's
generated `AGENTS.md` and `.d.ts` files. Keep the prefix mod small and use native
app commands and theme colors. Its JavaScript runs inside Herdr's GPUI runtime,
not Node.js. Keep the mod in one source file: relative imports through file
symlinks resolve outside the app's mod directory and are rejected.

## Validation

Run `./tests/install_test.sh` for installer or link changes. Check a temporary
copy of the prefix mod with `herdr-app check`, using an isolated
`HERDR_APP_HOME`, so generated files and preference writes stay out of the
checkout and the user's app state. Inspect `herdr-app status` and a screenshot
when validating changes in the running window. Preserve its focus and sessions;
do not launch, stop, or restart the app or core during installation.
