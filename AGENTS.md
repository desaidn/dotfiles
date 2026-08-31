# AGENTS.md

This file provides guidance to coding agents working in this repository. Codex reads it directly; Claude Code reaches it through the `CLAUDE.md` adapter. Keep guidance here harness-agnostic unless a detail genuinely belongs to one runtime.

## Repository Overview

This is a personal dotfiles monorepo. It contains configurations for the tools below; an `install.sh` symlinks tracked configurations into `~/.config/<tool>/` and `zsh/.zshrc` to `~/.zshrc`. Herdr is linked as a single durable config file so its mutable runtime state remains local. Editing a file under this repo and editing the corresponding linked file under `~/.config/<tool>/` are the same write.

## Core Applications

### Terminal & Shell

- **Ghostty** (`ghostty/config`) - macOS terminal emulator config
- **Fish** (`fish/`) - Primary shell, with custom λ prompt
- **Zsh** (`zsh/.zshrc`) - Secondary shell, mirrored prompt and aliases
- **Herdr** (`herdr/config.toml`) - Primary daily workspace manager; only durable configuration is tracked
- **Tmux** (`tmux/tmux.conf`) - Retained fallback and compatibility multiplexer with directory preservation and 1-based indexing

### Development Tools

- **Neovim** (`nvim/`) - Primary editor for most languages (see `nvim/AGENTS.md` for details)
- **LazyGit** (`lazygit/config.yml`) - Git Transaction Surface with nvim
  integration, Hunk as its Diffing Solution, native staging, and a custom theme
- **Hunk** (`hunk/config.toml`) - Full stacked working-tree and staged review surface from Neovim; only durable preferences are tracked

### Dependency ownership

Keep provisioning ownership explicit:

- **Platform bootstrap** owns Homebrew plus the compiler, download, and archive
  utilities required to install Homebrew and populate Neovim.
- **Homebrew** owns applications and standalone CLIs: Git, Fish 3.2+, Zsh,
  Neovim 0.12.5 stable, Herdr, tmux 3.7+, LazyGit 0.56+, Hunk 0.18.1+,
  Mise, Atuin, `gh`, `uv`,
  ripgrep, tree-sitter CLI 0.26.1+, and capability-specific tools such as
  `ghcup`; on Linux it also owns `xclip` and `wl-clipboard`.
- **Mise** owns Node.js/npm, Python, Rust/Cargo/Clippy/rustfmt/rust-src, and Amazon
  Corretto JDK 21 (`corretto-21.0.12.8.1`). The tracked manifest uses exact
  versions so reruns do not silently advance runtimes; update those pins
  deliberately. Do not install these runtimes through Homebrew.
- **Neovim** owns its plugins, Treesitter parsers, and Mason packages. Do not
  duplicate Mason-managed LSPs, formatters, linters, or debuggers in the
  machine package list.

Ghostty and JetBrains Mono are macOS-only Homebrew casks. Linux needs a
session-appropriate clipboard provider when a display is present; remote
sessions fall back to OSC 52 copy inside Neovim. Native development tools provide
`make`, although Neovim uses it only for optional plugin enhancements. Expect
is test-only. Do not turn gated per-machine paths for Bun, LM Studio, Claude,
or JetBrains Toolbox into required dependencies.

`install.sh` implements this policy through the root `Brewfile` and
`mise/conf.d/00-dotfiles.toml`. The Mise file is linked as a low-precedence
global defaults fragment; never replace a user's main
`~/.config/mise/config.toml`. See `docs/dependency-research.md` for the
evidence behind this inventory.

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
- Development-focused workflows for TypeScript, Kotlin/Java, Python, and Rust
- Prefer standard, idiomatic shortcuts and conventions over custom bindings to ensure compatibility across systems (e.g., use Ctrl+W for delete-word rather than custom Cmd+Backspace)
- Platform-agnostic rc files: no hardcoded `/opt/homebrew/...` paths in `fish/config.fish` or `zsh/.zshrc`. Per-machine state lives in `~/.local/share/dotfiles/local.{fish,zsh}`.

## Common Development Workflows

### Environment Setup

```bash
git clone <this-repo> ~/dotfiles
~/dotfiles/install.sh           # Bootstrap dependencies, runtimes, and config links
# Or, on hosts that cannot install the pinned runtimes:
~/dotfiles/install.sh --skip-mise-runtimes
# Linux: run the exact `exec ".../fish" -l` command printed by install.sh
nvim                            # Start editor (see nvim/AGENTS.md for details)
```

### Terminal Usage

```bash
# Start or reattach the normal daily workspace
herdr

# Start a deliberate fallback/compatibility session directly
tmux new-session -A -s dev

# Inside fallback tmux: C-b c (new window), C-b " (vsplit), C-b % (hsplit)
# All operations preserve current working directory
```

Herdr and tmux are top-level alternatives. Do not nest the tmux fallback inside Herdr for normal agent work.

### Git Operations

- Use `lazygit` for TUI operations (integrated with nvim via `<leader>gg`),
  with Hunk as its Diffing Solution and native LazyGit staging controls
- Write commit subjects as short, imperative plain-language summaries (for
  example, `Add shell LSP support`); do not use Conventional Commit prefixes
  such as `feat:` or `fix:`.
- Configured with custom theme matching development environment
- Use direct Hunk from Neovim only for full stacked review: `<leader>gd` → `hunk diff --watch --mode stack` for the working tree, `<leader>gD` → the same review with `--staged`. Both inputs share one Tool Tab and one process, so exactly one session matches the repository and the `--repo .` selector on `hunk session` subcommands stays unambiguous.
- Keep gitsigns keymaps hunk-local; buffer-wide stage/reset operations belong in lazygit.

### Agent Development Workflow

- Run `devflow` from the checkout where the work should remain. This may be the primary checkout or a user-created worktree; the Workflow Engine never creates, adopts, moves, repairs, prunes, locks, unlocks, or removes a worktree.
- Start locally authored features with `devflow start <feature>` from a clean invoking checkout. It creates `wip/<feature>` exactly at current mainline or selects the existing branch without rewriting it. Development commits must only append history. Incorporate mainline changes with an ordinary merge, never by rebasing WIP. If the branch is checked out elsewhere, stop instead of moving or changing that checkout.
- Treat every Git worktree lifecycle action as a Workflow Exception requiring explicit user approval. Devflow does not perform one even after approval; the user owns worktree topology.
- Once repository guards are installed, symbolic checkout is restricted to `wip/*`; detached checkout remains available, while mainline, Review Branch, and unrelated symbolic checkout requires an explicit Workflow Exception.
- Start local review with `devflow --json review` from a clean checkout on the matching WIP head. For externally authored code, provide the complete source, base, and review-name triple; the explicit form is always external and requires the clean invoking checkout to be exactly at the resolved source. Do not create WIP history for review-only work.
- Keep the invoking checkout quiescent while its review is open: do not change `HEAD`, the index, or working-tree files. Hunk and Editor Handoff stay rooted there so `e` opens in the review tab's Neovim with normal project-root discovery and full language tooling, using that checkout's dependencies, generated artifacts, and build context. For local work, address feedback with append-only WIP commits; for external code, review a newly supplied source. Either way, any checkout change requires a fresh Review Snapshot.
- During review, inspect the same immutable Hunk session as the user and add actionable findings through Hunk's session comment commands.
- Treat approval as explicit and Review Snapshot-specific. Land only with `devflow land`, the exact review identifier, and a complete imperative feature title.
- Any action outside the documented flow in `docs/agents/development-workflow.md` is a Workflow Exception and requires explicit user approval.

### Agent Harnesses

- Treat the user-facing code interface as Neovim plus terminal tools, regardless of which agent harness is active.
- Keep harness-specific instructions as thin adapters into shared repo guidance.
- Do not add Codex-only or Claude-only workflows when a shared command, file, or review surface can express the same behavior.
- Hunk is the direct full Review Surface from Neovim for both the working tree and the index and the Diffing Solution inside lazygit; lazygit remains the Git Transaction Surface and keeps its native staging UI.

## Architecture Notes

### File Organization

- Each tool maintains its own subdirectory under the repo root, mirroring the XDG layout under `~/.config/`; Herdr and Hunk link only `config.toml` so mutable state stays untracked
- Individual tools may have their own AGENTS.md files (e.g., `herdr/AGENTS.md`, `nvim/AGENTS.md`, `tmux/AGENTS.md`)
- Long-lived architecture review reports that the user chooses to retain live under `docs/`; generated reports should not remain at the repository root
- Configurations are environment-specific and not intended for multi-user scenarios

### Tool Integration Points

- **Editor ↔ Git**: Neovim integrates with both gitsigns and lazygit
- **Shell ↔ Editor**: Fish and zsh own the global editor contract (`EDITOR`, `VISUAL`, and `GIT_EDITOR` all point to `nvim`)
- **Terminal tool ↔ Editor**: flatten.nvim handles editor handoff from nested `nvim` calls back into the host Neovim; the shared terminal-tool module owns the opaque source marker and post-handoff policy while preserving the shell-owned `EDITOR` contract
- **Neovim ↔ Terminal tools**: Neovim-owned terminal tools use `nvim/lua/custom/lib/terminal_tool.lua`: one persistent Tool Tab per selected tool instance, singleton by default and keyed by normalized Host Window working directory for Hunk, with flatten.nvim for Editor Handoff and host tmux prefix and pane navigation kept upstream when using the fallback
- **Shell ↔ Workspace manager**: Ghostty launches the system shell; interactive zsh hands off to Fish with `exec fish`; invoke Herdr for the daily workspace or tmux directly for fallback/compatibility
- **Runtime Management**: Mise owns language runtimes; Mason owns editor tooling
- **Keybinding Constraints**: Option/Alt is reserved for FlashSpace workspace management; terminal shortcuts use Cmd or Ctrl modifiers instead (e.g., Cmd+Arrow for word navigation in Ghostty)

### Dependencies

- macOS-first setup; configs aim to remain Linux-compatible where practical
- Primary languages: TypeScript (Bun, Node.js, Browser), Kotlin/Java, Python, Rust
- Terminal tooling: Ghostty, Herdr, tmux, fish, zsh
- Dependency package mappings and version floors are documented in `README.md`; keep this section and that inventory aligned

## Agent skills

### Working TODOs

`TODO.md` and the index in `docs/todos/README.md` list active work only; briefs under `docs/todos/` exist only for active items. Follow the lifecycle in that README. When retiring an item, remove both index entries and delete its brief in the same change after preserving any durable knowledge in its proper home.

### Issue tracker

Issues, specs, and PRDs are tracked in GitHub Issues for `desaidn/dotfiles`; external PRs are not a triage request surface. See `docs/agents/issue-tracker.md`.

### Triage labels

Use the default five-label triage vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, and `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

This repo uses a single-context domain docs layout. See `docs/agents/domain.md`.

### Development workflow

The harness-neutral branch, review, approval, and landing contract is documented
in `docs/agents/development-workflow.md`. The Workflow Engine is the executable
authority for its deterministic checks; agent instructions do not replace them.

## Install Contract

`install.sh` MUST stay non-destructive:

- Never `rm` or `rm -rf` any user path.
- If a target exists, rename it to `<target>.bak.$(date +%s)` and create the symlink.
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
- After full Mise provisioning, install `dotfiles-devflow` through `uv` with
  the exact isolated `mise which python`, the private
  `~/.local/share/dotfiles/uv-tools` tool directory, and `~/.local/bin` for
  entry points. A source-and-interpreter ownership receipt must make the
  unchanged second run a no-op; never overwrite unreceipted or ambiguous tool
  state and never use `--force`.
- Run every owned `uv tool` transaction with `--no-config` in a subshell that
  removes inherited `UV_*`, `PYTHON*`, `VIRTUAL_ENV*`, `CONDA_*`, and `PIP_*`
  variables before setting only the private tool and entry-point directories.
  Preserve general proxy and TLS/CA variables needed for network access.
- Validate the private environment's `uv-receipt.toml` semantically with the
  exact receipted Python 3.14 interpreter and `tomllib`. Accept irrelevant TOML
  formatting, ordering, and comments, but require the exact editable source,
  interpreter, distribution, and three owned entry points with no extra,
  duplicate, missing, malformed, or non-string inventory. The receipt and
  source marker must be regular files; public entry points must be the exact
  owned symlinks.
- Write an ownership-safe pending receipt before `uv` changes tool state. A
  rerun may retry an exact pending install only when no tool artifacts exist,
  or finalize it without reinstalling only when its environment and every
  entry point are fully valid; preserve and reject every partial mismatch.
- Generic installation must not create or edit harness-global Codex or Claude
  guidance. Those adapters require an explicit `devflow harness install`
  invocation.
- Run `tests/install_test.sh` after installer, Brewfile, Mise manifest, or
  per-machine activation-template changes.

## Uninstall Contract

`uninstall.sh` is conservative and does not reverse package installation:

- With no arguments, remove only path-equivalent symlinks owned by this
  repository. Do not follow a symlink restored at a managed parent directory.
- With `--restore`, restore only the newest numeric backup when its scope is
  unambiguous and the destination has no unmanaged state.
- If nested file and directory backups compete, or a directory backup cannot
  replace a directory containing user-owned entries, preserve the active group
  and every backup and exit nonzero.
- Leave older backups, foreign links, installed packages and runtimes,
  per-machine activation files, and unrelated state under
  `~/.local/share/dotfiles/` untouched. A successful second run is a no-op.
- Remove the Workflow Engine only when its receipt, editable source,
  interpreter record, private environment, and public entry points establish
  unambiguous ownership. Preserve foreign or partial state and never uninstall
  Homebrew's `uv` or Mise's Python.
- Reuse the installer's exact semantic `uv-receipt.toml` ownership predicate
  independently inside `uninstall.sh`, and run the owned `uv tool uninstall`
  with the same config and environment isolation.

## Modification Guidelines

When modifying configurations:

1. Test changes in isolation before committing
2. Maintain integration between related tools
3. Keep configurations minimal and purpose-driven
4. Prefer native APIs and existing local helpers before adding external dependencies
5. Respect XDG directory structure
6. Document significant changes in relevant AGENTS.md files
7. Do not add platform-specific paths (e.g., `/opt/homebrew/...`) into rc files. They go in the per-machine `local.{fish,zsh}`.
