# Add Hunk Preferences

## Outcome

Persist the small set of Hunk preferences that genuinely support the repository's Review Surface while retaining upstream defaults for everything else.

## Context / current state

Hunk is already a required auxiliary tool and is launched from Neovim by [`hunk.lua`](../../nvim/lua/custom/plugins/hunk.lua). That declaration intentionally forces `--watch --mode stack`, which is part of the established stacked working-tree review contract.

Hunk supports global configuration at `~/.config/hunk/config.toml` and repository-local configuration at `.hunk/config.toml`. No managed `config.toml` currently exists. Hunk also keeps mutable state in `~/.config/hunk/state.json`, so managing the entire directory would put mutable application state inside the dotfiles repository.

The actual desired values—theme, wrapping, line numbers, transparency, agent notes, and related options—are not recorded yet.

## Scope

- Review the current installed Hunk version and upstream configuration reference.
- Choose only preferences that represent durable workflow decisions rather than taste-only deviations.
- Add a repo-owned `config.toml` and manage it as an individual file, preserving sibling mutable state.
- Update install, uninstall, and root documentation if the file becomes part of the managed dotfiles.
- Preserve the Neovim launcher's explicit stacked/watch behavior unless the Review Surface contract itself is intentionally changed.
- Verify Hunk both directly and through its production Neovim launcher.

## Boundaries / non-goals

- Do not symlink the whole `~/.config/hunk` directory.
- Do not commit `state.json` or other mutable Hunk data.
- Do not duplicate `mode=stack` or `watch=true` in multiple places without deciding which layer owns those invariants.
- Do not make Hunk the global Git pager or alter Git configuration as part of this preference task.
- Do not introduce a custom theme with a large maintenance surface unless the existing built-in themes cannot satisfy a concrete requirement.
- Do not change lazygit or gitsigns responsibilities.

## Open decisions

- Which preferences are actually desired?
- Should preferences apply globally or only to Hunk launched for this repository/workflow?
- Should the Neovim launcher continue owning stack/watch while `config.toml` owns presentation preferences?
- Should the managed config use a built-in theme, automatic terminal-background selection, or transparent background?
- What file-level install helper best creates the parent directory without taking ownership of mutable siblings?

## Acceptance criteria

- The chosen preferences are documented and limited to deliberate deviations from upstream defaults.
- Hunk loads the managed configuration with no warnings on the supported installed version.
- `~/.config/hunk/state.json` and any other unmanaged sibling files remain outside the repo and survive install/uninstall.
- Neovim still opens the full working-tree Review Surface in stacked, watched mode.
- Hunk's first frame renders cleanly inside the Neovim terminal float.
- Installation is non-destructive and a second install is a no-op; uninstall removes only the managed file link.
- Root layout/prerequisite documentation accurately describes the new managed file.

## Verification

1. Parse/open Hunk against a small temporary Git fixture and inspect each chosen preference.
2. Confirm the effective Neovim command still supplies the intended stack/watch behavior.
3. Run:

   ```sh
   nvim --clean --headless -l nvim/tests/terminal_tool_spec.lua
   /usr/bin/expect nvim/tests/terminal_tool_hunk_render.exp
   ```

4. Run install and uninstall twice under a temporary `HOME`, pre-populating an unmanaged `~/.config/hunk/state.json`, and confirm it is preserved.

Verify the current Hunk configuration schema before editing because preference names and command-specific sections may change between releases.

## Starting points / references

- [`nvim/lua/custom/plugins/hunk.lua`](../../nvim/lua/custom/plugins/hunk.lua) — production Hunk declaration and stack/watch ownership.
- [`nvim/tests/terminal_tool_spec.lua`](../../nvim/tests/terminal_tool_spec.lua) — declaration and lifecycle checks.
- [`nvim/tests/terminal_tool_hunk_render.exp`](../../nvim/tests/terminal_tool_hunk_render.exp) — real render and tmux integration regression.
- [`install.sh`](../../install.sh), [`uninstall.sh`](../../uninstall.sh), and [`README.md`](../../README.md) — managed config contract.
- [Hunk configuration reference](https://github.com/modem-dev/hunk#config).
