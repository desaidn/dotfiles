# Homebrew and Mise upgrades

Use the repository root as the working directory. Read the current root
`README.md` dependency inventory, `Brewfile`, and the dependency sections of
`install.sh`; they own the inventory. The
[shared development workflow](../../../../docs/agents/development-workflow.md)
owns checkout, review, and landing.

## Homebrew: select and account for every package

Array examples below use Bash or Zsh. Other shells or harnesses can pass the same
explicit argument lists directly; preserve formula/cask separation and skip
empty selections.

1. Enumerate the active platform's Brewfile entries with successful commands:

   ```bash
   HOMEBREW_NO_AUTO_UPDATE=1 brew bundle list --file=Brewfile --formula
   HOMEBREW_NO_AUTO_UPDATE=1 brew bundle list --file=Brewfile --cask
   ```

   Evaluate the Brewfile through Homebrew so conditions such as `OS.linux?`
   apply. Inspect errors even when stdout contains package names. These read
   commands may need permission to refresh Homebrew's API cache.

2. Reconcile declarations outside the Brewfile. Currently `install_macos_casks`
   in `install.sh` owns Ghostty and JetBrains Mono on macOS. Check installed cask
   receipts before updating them: an existing application or font may have
   been installed outside Homebrew. Report unmanaged or absent items instead
   of adopting, reinstalling, or replacing them as an upgrade side effect.
   Retain the user's selected subset; Neovim-only does not include every shell
   application or desktop cask.

3. Record installed versions and pins, then refresh package metadata with
   `brew update`. Build typed lists of selected formulae and casks. Use
   `brew info --json=v2 --installed` plus current selected-package metadata to
   follow the union of their dependency edges recursively. Match canonical
   names/full names; inspect formula `dependencies` and installed
   `runtime_dependencies`, plus cask `depends_on.formula`/`depends_on.cask`.
   Classify missing entries explicitly. This catches outdated libraries even when the
   directly requested application is current. Do not use plain `brew deps A B`
   as a union: multiple arguments default to an intersection. Its `--union`
   option is an alternative when its output provides enough detail.

4. Query outdated state for explicit, nonempty typed lists:

   ```bash
   brew outdated --formula --json=v2 "${selected_formulae[@]}"
   brew outdated --cask --json=v2 "${selected_casks[@]}"
   ```

   Populate these arrays from the reconciled inventory and skip an empty list;
   an empty argument list broadens the command to all installed packages.
   Named `brew outdated` can exit 1 because a requested package is outdated.
   Accept that case only with valid expected JSON and no actual command error;
   distinguish it from network, permission, parsing, or unknown-package errors.
   Pinned packages and auto-updating/`:latest` casks need explicit accounting.
   Preserve their policy; use `--greedy` only when that additional cask scope
   has been selected, and do not call a skipped cask verified current.

5. Inspect `brew upgrade --dry-run` for the same typed lists. Homebrew can also
   upgrade outdated dependents or repair broken linkage. Explain additional
   necessary changes; unrelated package upgrades are outside the selection.
   Apply the selected updates with automatic cleanup disabled:

   ```bash
   HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 \
     brew upgrade --formula "${selected_formulae[@]}"
   HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 \
     brew upgrade --cask "${selected_casks[@]}"
   ```

   Again, skip empty lists. Use the installed CLI's supported noninteractive
   confirmation flag when needed and already authorized. Keep package pins,
   tap trust, cleanup, and unrelated applications unchanged. A blocked tap or
   failed installation is a reported partial result, not permission to change
   trust or force overwrites. `install.sh` deliberately uses `--no-upgrade` and
   is not an upgrade command.

6. Re-query the selected dependency closure and executable versions. Classify
   each selected item as updated, already current, intentionally retained, or
   failed/unverified; report transitive changes too. Keep compatibility
   minimums unchanged unless a required capability actually demands a raise.

Upgrading an active terminal, workspace manager, or Hunk binary needs special
care: do not terminate the host carrying this task or silently close another
review. Existing processes may keep the old binary loaded. Capture live
sessions beforehand, retain the host-supplied compatible Herdr executable when
available, and verify client/server access after an upgrade. If that executable
path is stale, explain it and verify an installed alternative against the
existing server before using it. Defer a restart that would sever the task;
report it as a remaining activation step. Cask updates can quit applications;
inspect the installed CLI's `--no-quit` behavior or coordinate a safe restart.

## Mise: resolve exact versions and isolate installation

Read `mise/conf.d/00-dotfiles.toml`; derive selectors from its current values.
Keep the chosen Node major, Python minor, and Java vendor/major unless the user
asks to change release lines. Rust can advance to the selected stable numeric
release while retaining its profile/components. Query `mise latest` using those
selectors; verify that results are exact stable versions rather than literal
channels such as `stable`, `latest`, or `lts`. Inspect backend help if its
selection semantics differ. Record old pins, resolved candidates, and the
queries used. Preserve the effective minimum-release-age policy; do not bypass
it just to produce a newer number. [Mise settings](https://mise.jdx.dev/configuration/settings.html#minimum_release_age)

For example, after deriving these selector variables from the manifest:

```sh
mise latest "core:node@$node_major"
mise latest "core:python@$python_minor"
mise latest core:rust
mise latest "core:java@$java_vendor-$java_major"
```

Edit only the selected exact pins. Synchronize active version statements and
installer test fixtures that assert those pins; keep historical observations
and ADR records intact. Preserve user's higher-precedence runtime configuration.

Use the current `install_mise_runtimes` function in `install.sh` as the source
for isolation. Reproduce its environment setup in a temporary subprocess; do
not source or rerun the whole installer. Its present boundary is:

- Working directory: the canonical repository root.
- `MISE_CONFIG_DIR` and `MISE_SYSTEM_CONFIG_DIR`: that root's `mise` directory.
- `MISE_CEILING_PATHS`: that repository root.
- Unset `MISE_CONFIG_FILE`, `MISE_GLOBAL_CONFIG_FILE`,
  `MISE_GLOBAL_CONFIG_ROOT`, `MISE_IGNORED_CONFIG_PATHS`, `MISE_NO_CONFIG`,
  `MISE_DISABLE_TOOLS`, `MISE_ENV`, `MISE_ENV_FILE`, `MISE_NODE_VERSION`,
  `MISE_PYTHON_VERSION`, `MISE_RUST_VERSION`, and `MISE_JAVA_VERSION`.

Within that same environment, run `mise config ls --json` and parse it. Require
exactly one effective source, whose canonical path is the tracked
`mise/conf.d/00-dotfiles.toml`, before installation. A different source set is a
blocking isolation failure; report its paths and fix discovery before retrying.
Review effective release-age settings before and after isolation so selecting
the fragment does not silently discard an existing user constraint. Carry that
setting into the isolated query/install commands explicitly when needed, without
editing the user's global configuration.

Run `mise install --yes` for the full runtime scope, or pass only selected
configured tool names for a subset. This installs the requested versions without
rewriting configuration. `mise use` and broad `mise upgrade` are not substitutes
for this exact-pin operation. Keep existing runtime versions installed. See
[Mise installation behavior](https://mise.jdx.dev/cli/install.html) for the command contract.

Use `MISE_AUTO_INSTALL=false mise exec -- COMMAND` under the same isolated
environment for validation and later Neovim maintenance. Disabling automatic
installs for these checks prevents a scoped operation from silently provisioning
other configured runtimes; install selected missing prerequisites explicitly.
See [Mise automatic installation](https://mise.jdx.dev/configuration/settings.html#auto_install).
Verify `mise current`, actual executable versions,
and `mise which` paths for selected runtimes. Include npm with Node; Python
startup and SSL imports; Java plus javac; Rust plus Cargo, Clippy, rustfmt, and
the `rust-src` directory beneath `rustc --print sysroot`. Compare versions with
the manifest rather than trusting installation exit status alone.

Finally inspect normal `mise current` and configuration discovery outside the
isolated subprocess. If a user's higher-precedence configuration selects a
different runtime, explain the override rather than rewriting it. Runtime
installation does not refresh existing shells or editor processes; report any
necessary fresh-shell/editor restart. A manifest change requires the full
`tests/install_test.sh` suite under the repository's existing instructions.
