# Neovim plugins, editor tools, and parsers

Read `nvim/AGENTS.md` and the maintenance section of `nvim/README.md`. Check the
installed APIs before using these examples: they were verified against native
`vim.pack`, Mason 2, Mason Tool Installer, and nvim-treesitter's `main` API. Adapt
to a changed API from its installed help/source or upstream documentation.

## Prepare a maintenance process

Finish the checkout/review preflight in `SKILL.md` before normal startup. Resolve
Neovim's actual data/config paths and linked checkout; do not assume a hardcoded
home directory or write a lockfile belonging to another checkout.

Use the selected Mise environment from `package-managers.md`. Run normal
configured headless Neovim with `-i NONE` and an explicit `-c` command that executes
a temporary Lua file. The examples below belong in that file after configuration
has loaded but before `VimEnter`. Disable concurrent Mason startup work first:

```lua
require('mason-tool-installer').setup { run_on_start = false }
```

Wrap the temporary operation in `xpcall(..., debug.traceback)` and exit with
`cquit 1` on failure, `qa!` on success. Capture stdout/stderr and error-level
notifications. Early startup errors also need inspection; a later successful
command does not erase them. Do not use normal startup to perform read-only
discovery or isolated unit tests.

## Requested reset and reinstall

Use this path when the user requests `nvim-reset` followed by a full reinstall.
It clears Neovim's installed data, state, and cache. A subset upgrade alone does
not authorize clearing shared Neovim state.

1. Inspect active Neovim and Hunk sessions using real host access. Coordinate
   their shutdown before resetting shared directories. Perform the plugin
   local-edit checks below for every plugin directory the reset would remove,
   and account for any additional installed packages or user-owned data.
2. Preserve the upgraded tracked lockfile and selected plugin revisions. Verify
   the existing `nvim-reset` definition in the configured shell against the
   actual data/state/cache paths; resolve any mismatch before executing it.
3. From the selected checkout, use that shell and the selected Mise environment:

   ```sh
   nvim-reset
   nvim
   ```

   Normal configured Neovim installs the locked plugins and starts their build
   hooks and editor-tool installation. For an agent-operated headless reinstall,
   handle native `vim.pack.add` installation confirmations before configuration
   loads (`--cmd`), using its `confirm = false` option only for the authorized
   declarations. Use the maintenance process above and explicitly await the
   selected Mason and Treesitter operations below.
4. Verify the tracked lockfile is preserved, every selected plugin HEAD matches
   its locked revision, and native builds work. Reconcile every declared Mason
   package and parser with its expected version/revision, wait for installation
   to finish, and verify parser loading. Finish with the
   [fresh configured startup and health checks](validation.md); a started editor
   is not proof that installation completed.

## Plugins

1. Reconcile `vim.pack.get(nil, { info = false })` with the lockfile and declared
   plugin scope. `nil` includes inactive managed plugins; it can pick up retired
   copies still on disk. Select explicit package names if the intended inventory
   is narrower. Keep exclusions visible and avoid restoring retired lock entries.
2. Inspect Git status in each selected plugin directory **before updating**.
   Native `vim.pack` can stash tracked edits during checkout. Preserve unfamiliar
   tracked or untracked work and resolve it with the user. Generated `doc/tags`
   may be left in place after confirming their origin and no overwrite conflict.
3. Capture the plugin log offset and before revisions. Update the selected names:

   ```lua
   vim.pack.update(names, { force = true })
   ```

   In the installed API, `force` skips confirmation; `confirmation = false` is
   not its equivalent. Use it only for an authorized upgrade after the local-edit
   check. Interactive execution can instead use `:lua vim.pack.update()` and
   `:write` in its confirmation buffer.
4. Inspect the new portion of `vim.fn.stdpath('log') .. '/nvim-pack.log'`, handling
   a new/rotated log explicitly. Per-plugin failures are caught internally and
   appear under `# Error`; exit zero alone does not establish success. Inspect
   build-hook errors as well. Preserve the generated lockfile and verify every
   selected installed HEAD agrees with its recorded revision.

`custom.lib.pack` owns Telescope's native build and FFF's binary download/build.
The language Treesitter module owns parser update hooks. Let those hooks run;
verify their results instead of duplicating their setup. FFF's downloader may
wait internally and emit an error without throwing. After updates, start a
**fresh** configured Neovim process so loaded Lua/native modules and parser
metadata correspond to the new revisions. Check:

```lua
local result = require('fff.health').run()
assert(result.binary.available, result.binary.error or 'FFF binary unavailable')
```

Inspect `result.ok` and `result.messages` too. Optional image preview support is
separate from the required FFF binary. Check Telescope's fzf extension through
its health check. Preserve configured plugin version ranges and branches.

## Mason

Use a fresh configured process after plugin changes and disable startup work as
above. Refresh the registry explicitly and require its callback to report success:

```lua
local registry = require('mason-registry')
local done, success, result = false, false, nil
registry.update(function(ok, value)
  success, result, done = ok, value, true
end)
assert(vim.wait(120000, function() return done end, 100), 'Registry update timed out')
assert(success, vim.inspect(result))
```

`MasonUpdate` updates registries, not tools. Mason Tool Installer's ordinary
`refresh` may use cached data, and an update-completed event can include failed
installs. Inspect actual results.

Build the selected tool list from
`require('custom.languages.config').mason_tools`. Include already installed
extras from `registry.get_installed_package_names()` only if the agreed scope
includes them. Preserve table entries' conditions, explicit versions and target
options; do not flatten future pinned entries to bare names. The current adapters
use unpinned strings.

For each selected package, confirm no other installation is running and register
an `install:failed` listener before starting work. Configure the temporary
installer with this selected list and `run_on_start = false`. For a bounded
headless run, register a `User MasonToolsUpdateCompleted` autocmd, execute
`:MasonToolsUpdate`, and wait for its flag with an explicit deadline. Skip the
installer call for an empty list. `:MasonToolsUpdateSync` is also available, but
has no built-in deadline and can hang if startup installation overlaps it.

When the operation completes, check each applicable package with Mason 2's
synchronous methods:

```lua
assert(package:is_installed() and not package:is_installing())
local installed = package:get_installed_version()
local expected = explicit_pin or package:get_latest_version()
assert(installed == expected, package.name .. ': version mismatch')
```

Treat unsupported targets, unresolved registry names, condition-skipped tools,
failed listeners, and version mismatches as explicit outcomes. A deadline is
not success: inspect active install handles before retrying or terminating the
maintenance process so an overlapping attempt cannot corrupt package state.
Keep before/after receipts and errors in temporary logs for the final accounting.
Do not use `MasonToolsClean` or remove user-installed extras as part of upgrading.

## Treesitter

Use a fresh process with the updated plugin metadata. Start from the authoritative
parser list and include additional installed parsers only when selected. The
configuration's package hook already updates declared parsers, but it does not
establish that every operation succeeded. Startup installation may still be in
flight. The installed `install` API skips existing parsers and waits for a
concurrent in-process installation of the same parser; verify presence afterward
because waiting for another task to finish does not prove that task succeeded.
For a narrower request, supply its selected subset as `parsers` in this example:

```lua
local treesitter = require('nvim-treesitter')
local parsers = require('custom.languages.config').treesitter_parsers
if #parsers > 0 then
  assert(treesitter.install(parsers, { summary = true }):wait(600000),
    'Parser installation failed')
  local installed = treesitter.get_installed('parsers')
  for _, name in ipairs(parsers) do
    assert(vim.tbl_contains(installed, name), 'Parser missing: ' .. name)
  end
  assert(treesitter.update(parsers, { summary = true }):wait(600000),
    'Parser update failed')
  for _, name in ipairs(parsers) do
    assert(vim.treesitter.language.add(name), 'Parser cannot load: ' .. name)
  end
end
```

An empty selection must skip both calls: the plugin can expand `{}` to `all`.
The task's `wait` throws on timeout and returns false when an installation fails.
Use the plugin's supported revisions, not grammar repository HEADs. `:TSUpdate`
updates installed parsers; it is not proof that every declared parser is present.
Compare the selected and installed sets and inspect query errors in a fresh
configured health check.

API references: [native packages](https://neovim.io/doc/user/pack/),
[Mason](https://github.com/mason-org/mason.nvim),
[Mason Tool Installer commands](https://github.com/WhoIsSethDaniel/mason-tool-installer.nvim#commands),
[Treesitter](https://github.com/nvim-treesitter/nvim-treesitter#installation).
