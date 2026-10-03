# AGENTS.md

This file provides guidance to coding agents working in this repository. Codex reads it directly; Claude Code reaches it through the `CLAUDE.md` adapter. Keep guidance here harness-agnostic unless a detail genuinely belongs to one runtime.

## Repository Overview

This is a personal dotfiles monorepo. See [README.md](README.md) for the
application layout, installation, dependency inventory, and tool usage guides.
Editing a file under this repo and editing its linked counterpart under
`~/.config/` are the same write.

## Dependency ownership

Keep provisioning ownership explicit:

- **Platform bootstrap** owns Homebrew plus C/C++ compilers, SDKs, and the download
  and archive utilities required to install Homebrew and populate Neovim.
- **Homebrew** owns applications and standalone CLIs. Preserve the package
  inventory and version requirements in [README.md](README.md#dependency-ownership).
- **Mise** owns language runtimes. Keep the tracked manifest's exact pins and
  update them deliberately; do not install these runtimes through Homebrew.
- **Neovim** owns its plugins, Treesitter parsers, and Mason packages. Do not
  duplicate Mason-managed LSPs, formatters, linters, or debuggers in the
  machine package list.

The user reviewed the dependency-reduction proposals in the
[October 2026 audit](docs/defect-audit-2026-10-03.md#dependency-proposals-considered-and-retained)
and chose to retain every existing dependency. Preserve those choices; the
native-first philosophy does not independently authorize removing or replacing
the retained tools.

Keep compatibility minimums separate from exact provisioning pins. Raise a
minimum only for a required capability or documented incompatibility; recommend
latest stable releases without adding network checks or update warnings to
startup. Neovim installer, startup, and health checks must share
[`nvim/lua/custom/lib/neovim.lua`](nvim/lua/custom/lib/neovim.lua).

Ghostty and JetBrains Mono are macOS-only Homebrew casks. Linux needs a
session-appropriate clipboard provider when a display is present; remote
sessions fall back to OSC 52 copy inside Neovim. Native development tools provide
`make`, although Neovim uses it only for optional plugin enhancements. Expect
is test-only. Do not turn gated per-machine paths for Bun, LM Studio, Claude,
or JetBrains Toolbox into required dependencies.

`install.sh` implements this policy through the root `Brewfile` and
`mise/conf.d/00-dotfiles.toml`. The Mise file is linked as a low-precedence
global defaults fragment; never replace a user's main
`~/.config/mise/config.toml`. See [the dependency research](docs/dependency-research.md) for source evidence.

## Configuration Philosophy

All configurations follow these principles:

- Only one way to do anything — no overlapping functionality between tools
- Minimal, focused setups without unnecessary complexity
- Consistent directory structure following XDG standards
- Integration between tools (e.g., lazygit ↔ nvim, terminal tools ↔ editor handoff)
- Prefer native platform and Neovim capabilities before adding third-party abstractions
- Keep external dependencies few, purposeful, and replaceable; every dependency should justify its maintenance and portability cost
- Prefer small self-made or locally-owned performant development tools when native capabilities are not enough and the workflow should stay inspectable
- Agent harnesses are adapters, not workflow owners; Codex, Claude Code, and future tools should use the same Neovim, Git, and review surfaces
- Prefer upstream defaults unless a deviation directly supports the uniform code interface; avoid custom maintenance burden for taste-only changes
- Development-focused workflows for TypeScript (Bun, Node.js, Browser), Kotlin/Java, Python, Rust, and C/C++
- Prefer standard, idiomatic shortcuts and conventions over custom bindings to ensure compatibility across systems (e.g., use Ctrl+W for delete-word rather than custom Cmd+Backspace)
- Platform-agnostic rc files: no hardcoded `/opt/homebrew/...` paths in `fish/config.fish` or `zsh/.zshrc`. Per-machine state lives in `~/.local/share/dotfiles/local.{fish,zsh}`.

## Workflow constraints

Herdr and tmux are top-level alternatives. Do not nest the tmux fallback inside
Herdr for normal agent work. Usage is documented in the
[Herdr](herdr/README.md) and [tmux](tmux/README.md) guides.

### Git Operations

- Use `lazygit` for TUI operations (integrated with nvim via `<leader>gg`),
  with Hunk as its Diffing Solution and native LazyGit staging controls
- Write commit subjects as short, imperative plain-language summaries (for
  example, `Add shell LSP support`); do not use Conventional Commit prefixes
  such as `feat:` or `fix:`.
- Use Hunk from Neovim for full stacked working-tree, staged, or exact-revision
  review. These inputs must share one Tool Tab and process per checkout so
  the `--repo .` selector on `hunk session` subcommands remains unambiguous. See the
  [Neovim Git guide](nvim/README.md#git) for mappings.
- Keep gitsigns keymaps hunk-local; buffer-wide stage/reset operations belong in lazygit.

### Agent Development Workflow

Read and follow [the development workflow](docs/agents/development-workflow.md)
before branch, review, or landing operations. Carry out its checks directly with
Git, Herdr, Neovim, and Hunk; no workflow executable or skill is required. This
same complete document is installed as global guidance for all three harnesses.

- These rules govern coding agents only. Never block, intercept, or reinterpret
  human Git and LazyGit operations as Workflow Exceptions.
- Follow user and project instructions to select the checkout; ask before an
  otherwise unauthorized branch or worktree action.
- Keep agent-authored WIP append-only: ordinary commits and merges are allowed;
  never amend, rebase, reset, delete, or force-update it.
- Review the exact clean WIP head. Keep the commit, staged state, and files
  unchanged while review is open; verify and inspect the exact Hunk session and add
  every actionable finding there before asking for a decision.
- A review is not approval. Land only after explicit approval of the exact
  current local review and after asking which existing local branch receives
  it. Any WIP or Review Branch change invalidates that approval.
- Coordinate shared-checkout activity and rerun validation after a concurrent
  human Git operation. No ref or checkout is reserved against human use.
- Record exact snapshot identity and explicit approval in the conversation. If
  that evidence is unavailable or uncertain, perform fresh review and obtain
  fresh approval. Do not create a replacement persistent review-record format.

### Agent Harnesses

- Treat the user-facing code interface as Neovim plus terminal tools, regardless of which agent harness is active.
- Keep harness-specific instructions as thin adapters into shared repo guidance.
- Do not add Codex-only or Claude-only workflows when a shared command, file, or review surface can express the same behavior.
- Hunk is the direct full Review Surface from Neovim for both the working tree and the index and the Diffing Solution inside lazygit; lazygit remains the Git Transaction Surface and keeps its native staging UI.

## Architecture Notes

### File Organization

- Each configured application maintains its own subdirectory under the repo root, mirroring the XDG layout under `~/.config/`; Herdr and Hunk link only `config.toml` so mutable state stays untracked
- The complete portable agent workflow lives in `docs/agents/development-workflow.md`; harness-global instruction paths link directly to it. Keep dotfiles-specific constraints here.
- Follow tool-specific guidance where present: [Herdr](herdr/AGENTS.md),
  [Neovim](nvim/AGENTS.md), and [tmux](tmux/AGENTS.md).
- Long-lived architecture review reports that the user chooses to retain live under `docs/`; generated reports should not remain at the repository root
- Configurations are environment-specific and not intended for multi-user scenarios
- Keep documentation ownership explicit: the root README owns installation and
  dependency inventory; tool READMEs own usage, commands, keybindings, and
  troubleshooting; AGENTS files own constraints, ownership, and validation.
  Keep workflow details in [the development workflow](docs/agents/development-workflow.md),
  decisions in ADRs, and domain definitions in `CONTEXT.md`. Link to each owner
  instead of duplicating its explanations.

### Tool Integration Points

- **Editor ↔ Git**: Neovim integrates with both gitsigns and lazygit
- **Shell ↔ Editor**: Fish and zsh own the global editor contract (`EDITOR`, `VISUAL`, and `GIT_EDITOR` all point to `nvim`)
- **Terminal tool ↔ Editor**: flatten.nvim handles editor handoff from nested `nvim` calls back into the host Neovim; the shared terminal-tool module owns the opaque source marker and post-handoff policy while preserving the shell-owned `EDITOR` contract
- **Neovim ↔ Terminal tools**: Neovim-owned terminal tools use `nvim/lua/custom/lib/terminal_tool.lua`: one persistent Tool Tab per selected tool instance, singleton by default and keyed by canonical Git checkout root for Hunk, with flatten.nvim for Editor Handoff and host tmux prefix and pane navigation kept upstream when using the fallback
- **Shell ↔ Workspace manager**: Ghostty launches the system shell; interactive zsh hands off to Fish with `exec fish`; invoke Herdr for the daily workspace or tmux directly for fallback/compatibility
- **Runtime Management**: Mise owns language runtimes; Mason owns editor tooling
- **Keybinding Constraints**: Option/Alt is reserved for FlashSpace workspace management; terminal shortcuts use Cmd or Ctrl modifiers instead (e.g., Cmd+Arrow for word navigation in Ghostty)

Keep the macOS-first setup Linux-compatible where practical. Update the
[root dependency inventory](README.md#dependency-ownership) when ownership or
version requirements change.

## Agent skills

### Working TODOs

`TODO.md` and the index in `docs/todos/README.md` list active work only; briefs under `docs/todos/` exist only for active items. Follow the lifecycle in that README. When retiring an item, remove both index entries and delete its brief in the same change after preserving any durable knowledge in its proper home.

### Issue tracker

Issues, specs, and PRDs are tracked in GitHub Issues for `desaidn/dotfiles`; external PRs are not a triage request surface. See `docs/agents/issue-tracker.md`.

### Triage labels

Use the default five-label triage vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, and `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

This repo uses a single-context domain docs layout. See `docs/agents/domain.md`.

## Install Contract

`install.sh` MUST stay non-destructive:

- Never `rm` or `rm -rf` any user path.
- For ordinary configuration links, if a target exists, rename it to
  `<target>.bak.$(date +%s)` and create the symlink. Shared workflow instruction
  destinations are protected: reject unmanaged content for explicit migration
  rather than silently removing it from the agent's active context.
- If the target is already a path-equivalent symlink to its expected source in
  this repo, skip silently.
- Re-running the script after a successful install is a no-op.
- Reject an empty, relative, or root `HOME`, and reject root execution, before
  constructing or changing user paths.
- Keep `install.sh` and `uninstall.sh` self-contained at the user-path safety
  boundary; duplicate their small guards and ownership predicate rather than
  introducing a sourced bootstrap helper.
- Preflight the Brewfile, every tracked link/template source, and blocking
  parent paths before installing dependencies or changing link targets.
- Perform all dependency installation and validation before changing link
  targets, so a partial bootstrap can be resumed safely.
- Validate both native C and C++ compilation and standard-library linking before
  provisioning Homebrew; executable presence alone does not establish a working SDK.
- Use the official Homebrew installer only when Brew cannot be discovered;
  use `brew bundle check --no-upgrade` before `install --no-upgrade`. Do not
  promise that Homebrew will never update a dependency needed by a new formula.
- Keep native Linux bootstrap support explicit to `apt-get`, `dnf`, `yum`, and
  `pacman`; fail with an actionable message for an unknown manager. Detect
  `dnf` before `yum` so dnf-based systems with a yum compatibility symlink use
  the dnf path.
- Keep Mise runtime selectors exact; floating channels break strict second-run
  idempotence as their resolution changes.
- `--skip-mise-runtimes` is the only supported degraded install mode. It skips
  runtime installation and validation and does not create or update the
  tracked Mise fragment link. Never remove an existing managed or user-owned
  Mise fragment in this mode.
- Link the complete shared workflow into Codex and pi global `AGENTS.md` files
  and Claude's global `rules/development-workflow.md`, including in degraded
  mode. Honor validated `CODEX_HOME` and `PI_CODING_AGENT_DIR` overrides.
- Preserve unrelated global instructions and skills. Reject conflicting global
  overrides, unmanaged destinations, legacy devflow guidance, and blocked parent
  paths during preflight; migration is explicit, not a hidden installer rewrite.
- Do not provision a workflow executable, private Python environment, harness
  plugin, hooks, or new review-state storage. The shared document is the only
  maintained workflow policy; native harness loaders supply its full contents.
- Run `tests/install_test.sh` after installer, Brewfile, Mise manifest, or
  per-machine activation-template changes. It needs Neovim to execute the shared
  compatibility helper against simulated versions.

## Uninstall Contract

`uninstall.sh` is conservative and does not reverse package installation:

- With no arguments, remove only path-equivalent symlinks owned by this
  repository. Do not follow a symlink restored at a managed parent directory.
- With `--restore`, restore only the newest numeric backup when its scope is
  unambiguous and the destination has no unmanaged state.
- If nested file and directory backups compete, or a directory backup cannot
  replace a directory containing user-owned entries, preserve the active group
  and every backup and exit nonzero.
- Restoration must use an atomic, exact-path, no-replace rename. Build its
  temporary native helper with the already-required platform C compiler before
  any `--restore` mutation; failure must preserve all managed links and backups.
  Keep the helper embedded in `uninstall.sh` and remove it on exit. Ordinary
  uninstall must remain independent of compilation.
- Leave older backups, foreign links, installed packages and runtimes,
  per-machine activation files, and unrelated state under
  `~/.local/share/dotfiles/` untouched. A successful second run is a no-op.
- Remove only owned global instruction links, preserving personal guidance,
  other rules/skills, custom profile contents, and historical review records.
  Do not follow redirected harness containers to remove another profile's files.
- Retired executable installations require an explicit ownership-checked migration;
  generic uninstall leaves installed packages and legacy records untouched.

## Modification Guidelines

When modifying configurations:

1. Test changes in isolation before committing
2. Maintain integration between related tools
3. Keep configurations minimal and purpose-driven
4. Prefer native APIs and existing local helpers before adding external dependencies
5. Respect XDG directory structure
6. Document significant changes in relevant AGENTS.md files
7. Do not add platform-specific paths (e.g., `/opt/homebrew/...`) into rc files. They go in the per-machine `local.{fish,zsh}`.
