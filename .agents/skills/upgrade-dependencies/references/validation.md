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
the authorized maintenance and fresh health-check runs.

After Mason and parser installation finishes, capture the health report from a
fresh configured process. The installed Neovim health command runs its checks
synchronously; capture the named `health://` buffer after the command returns.
Use the normal Lua command context rather than an installation's fast callback.
Set `DOTFILES_HEALTH_LOG` to a file in a writable temporary directory:

```lua
local output = assert(vim.env.DOTFILES_HEALTH_LOG, 'Set DOTFILES_HEALTH_LOG')
vim.cmd('checkhealth')
local report = vim.fn.bufnr('health://')
assert(report > 0 and vim.api.nvim_buf_is_valid(report), 'Health report missing')
local lines = vim.api.nvim_buf_get_lines(report, 0, -1, false)
assert(table.concat(lines, '\n'):find('%S'), 'Health report is empty')
assert(vim.fn.writefile(lines, output) == 0, 'Could not save health report')
```

Check command-completion behavior against the installed API if it changes.
Inspect the saved report's errors and warnings; successful capture and a zero
Neovim exit alone do not establish a healthy installation. Separate optional
providers or upstream filetype notices from broken configured features. Do not
install unused providers to make every warning disappear.

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
