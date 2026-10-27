# Validation and completion

Select checks from the current root/tool `AGENTS.md` files. Version-only updates
still change executable behavior; compare receipts, active executables, and plugin
HEADs rather than relying solely on successful downloads.

| Changed surface | Required or relevant evidence |
| --- | --- |
| Brewfile, Mise manifest, installer, or activation templates | `tests/install_test.sh`, required by root AGENTS |
| Broad Neovim plugin/runtime/native-library updates | Full documented Lua `*_spec.lua` suite, Lua diagnostics, fresh configured startup and `:checkhealth` |
| A narrow editor-tool update | Installed-version verification and the matching language/integration checks from `nvim/AGENTS.md` |
| Hunk or terminal integration | The real-PTY Hunk regression documented in `nvim/AGENTS.md`; use only its isolated fixtures and sessions |
| Fish/zsh or shell integration | `python3 tests/shell_test.py`, plus applicable tool instructions |
| tmux | The isolated server/config check in `tmux/AGENTS.md` |
| Herdr | `herdr config check` and compatible client/server verification; restarting a live workspace is separate from checking the installed binary |
| Other selected applications/casks | Installed version/ownership and an appropriate non-disruptive capability/config check; report anything that requires a user restart |

For the full Neovim Lua suite, use the documented zsh glob from the repository
root in the selected runtime environment:

```zsh
for spec in nvim/tests/**/*_spec.lua; do
  nvim --clean --headless -l "$spec" || exit 1
done
nvim --clean --headless -l nvim/tests/diagnostics.lua
```

Use writable temporary `XDG_STATE_HOME` and `XDG_CACHE_HOME` for isolated tests,
while preserving installed `XDG_DATA_HOME` so the upgraded plugins are exercised.
Keep `--clean` for these harnesses; normal startup provisioning belongs only to
the authorized maintenance and fresh health-check runs. Capture the health buffer
and inspect it, not just the Neovim exit code. Separate optional providers or
upstream filetype notices from broken configured features. Do not install unused
providers to make every warning disappear.

Before formal review, account for every selected dependency and inspect the full
tracked diff. It should contain intended lockfile/pin changes, necessary active
documentation/fixture updates, and any justified compatibility repairs. Leave
historical evidence intact. The development workflow owns clean commit, exact
review, approval, and landing checks; do not substitute a validation log for
approval or create a new review-state file format.

After successful validation, repeat a check only when a later change or failure
invalidates its evidence. An unchanged landing tree does not require replaying
the upgrade or its whole test suite. If everything was already current, report
the verified no-op and leave Git history unchanged.
