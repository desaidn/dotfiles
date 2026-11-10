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

Link only `settings.json` and `themes/terminal.json`. The app home and its
`themes/` container must remain real directories. Herdr owns its keymap,
generated guides, type definitions, shipped layouts/mods, and runtime state.
Do not seed or overwrite `shared.json`.

Preserve custom files, foreign links, and redirected mod directories.

## Validation

Run `./tests/install_test.sh` for installer or link changes. Read
`herdr-app --skill` before validating changes in the running window, then
inspect `herdr-app status` and a screenshot. Preserve its focus and sessions;
do not launch, stop, or restart the app or core during installation.
