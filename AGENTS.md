# AGENTS.md

This file provides guidance to coding agents working in this repository. Codex reads it directly; Claude Code reaches it through the `CLAUDE.md` adapter. Keep guidance here harness-agnostic unless a detail genuinely belongs to one runtime.

## Repository Overview

This is a personal dotfiles monorepo. [README.md](README.md) is the human
front page: what the repo is, quick start, layout, daily entry points, and
rollback. This file is canonical for everything else — the dependency
inventory, configuration philosophy, shared agent instructions, and the
install/uninstall contracts. Editing a file under this repo and editing its
linked counterpart under `~/.config/` are the same write.

## Dependency ownership

`install.sh` provisions dependencies according to one ownership rule per
layer:

- **Platform bootstrap** owns Homebrew plus C/C++ compilers, SDKs, and the download
  and archive utilities required to install Homebrew and populate Neovim. On
  macOS that means Xcode Command Line Tools; a missing install may require
  completing Apple's system dialog and rerunning the installer. On Linux it
  means the distribution's development-tools packages.
- **Homebrew** owns applications and standalone CLIs. Preserve the package
  inventory and version requirements [below](#homebrew-applications).
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

Do not turn the gated per-machine fallback paths (Atuin self-install, Bun,
GHCup, Cabal, LM Studio, Claude, or JetBrains Toolbox) into required
dependencies.

`install.sh` implements this policy through the root `Brewfile` and
`mise/conf.d/00-dotfiles.toml`. The Mise file is linked as a low-precedence
global defaults fragment; never replace a user's main
`~/.config/mise/config.toml`. See [the dependency research](docs/dependency-research.md) for package mapping
and primary-source evidence.

### Homebrew applications

| Package                 | Requirement in this repo                                                                                                                                                 |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `git`                   | Plugin retrieval and all Git-facing tools                                                                                                                                |
| `fish`                  | Primary shell; version 3.2 or newer                                                                                                                                      |
| `zsh`                   | Secondary/login-shell handoff                                                                                                                                            |
| `neovim`                | `nvim`; version 0.12.5 or newer                                                                                                                                          |
| `herdr`                 | Herdr TUI, the shelved alternative workspace manager                                                                                                                     |
| `tmux`                  | Fallback multiplexer; version 3.5 or newer for `extended-keys-format`                                                                                                    |
| `lazygit`               | Git Transaction Surface; version 0.64.0 or newer for `git.diffRenderers`                                                                                                 |
| `hunk`                  | Diffing Solution and stacked working-tree and staged Review Surface; version 0.18.1 or newer for efficient concurrent watch sessions (0.12 introduced LazyGit rendering) |
| `mise`                  | Language runtime manager                                                                                                                                                 |
| `atuin`                 | Shell history integration                                                                                                                                                |
| `btop`                  | Interactive system resource monitor                                                                                                                                      |
| `gh`                    | GitHub issue workflows described under `docs/agents/`                                                                                                                    |
| `ripgrep`               | `rg`; Neovim Telescope grep                                                                                                                                              |
| `tree-sitter-cli`       | `tree-sitter` 0.26.1 or newer; parser management                                                                                                                         |
| `cmake`                 | C/C++ project configuration, compilation databases, and CTest                                                                                                            |
| `ninja`                 | Build runner for CMake projects that select the Ninja generator                                                                                                          |
| `uv`                    | Python project and dependency management CLI; Mise continues to own Python runtimes                                                                                      |
| `xclip`, `wl-clipboard` | Linux X11 and Wayland clipboard providers                                                                                                                                |

On macOS, the setup also uses the `ghostty`, `font-jetbrains-mono`,
`herdr-app`, `raycast`, and `flashspace` casks. They are macOS-only; the
installer provisions casks separately from the Brewfile to preserve compatible
manual installations. Ghostty 1.3.0 and Herdr app 0.1.12 are the validated
configuration baselines the installer enforces; newer versions are accepted.
Herdr app's cask requires Apple Silicon; the app owns installation and updates
of its Herdr core dependency, and the existing `herdr` Homebrew formula
remains the independent TUI. Ghostty and Herdr app configuration is skipped on
Linux.

Raycast provides the application launcher, and FlashSpace manages virtual
workspaces. Only their installation is managed; their settings remain local.
[Homebrew documents Raycast](https://formulae.brew.sh/cask/raycast) as
`brew install --cask raycast`.
[FlashSpace documents](https://github.com/wojciech-kulik/FlashSpace#%EF%B8%8F-installation)
`brew install flashspace`; it is also a
[Homebrew cask](https://formulae.brew.sh/cask/flashspace), so the installer uses
the explicit `brew install --cask flashspace` equivalent. FlashSpace requires
macOS 14 or newer and "Displays have separate Spaces" enabled in Desktop & Dock
settings. Both apps are skipped on Linux.

### Mise runtimes

The enabled Neovim language capabilities require Node.js/npm, Python, Rust
with Cargo, Clippy, rustfmt, and rust-src, and a Java runtime and compiler at
version 21 or newer. These runtimes belong to Mise; Mason installs the declared
editor tooling. TypeScript is a
project-owned semantic exception: each recognized workspace supplies
its root-local compiler, and Mason owns only the compatibility transport.
See [Neovim's project requirements](nvim/README.md#language-project-requirements)
for version routing and debugging setup.

The installer uses the tracked global defaults fragment
[`mise/conf.d/00-dotfiles.toml`](mise/conf.d/00-dotfiles.toml). It pins exact
Node.js, Python, and Rust versions plus Amazon Corretto JDK 25 at
`corretto-25.0.5.0.10`, so a successful second run does not silently resolve a
newer runtime. Runtime updates are deliberate manifest edits. Bootstrap
evaluates only the tracked fragment, with global, system, and ancestor discovery
bounded and the effective source list checked before installation. A user's normal
`~/.config/mise/config.toml` remains untouched and has higher precedence in
interactive shells.

To apply committed runtime pins on another host, including after pulling this
repository, run `./install.sh` from the repository root. It installs missing
pinned runtimes, validates them, and reuses existing matching configuration links
and installed versions. Open a fresh shell afterward and use `mise current` to
inspect the effective versions.

Java compatibility is independent of vendor; Corretto is the deliberate
provisioning choice in the manifest.

`--skip-mise-runtimes` is an explicit degraded setup for hosts that cannot run
the pinned versions. Other dependencies and configurations are installed, but
runtime-dependent language tooling may remain unavailable. On a fresh setup,
the tracked defaults fragment is not linked; an existing managed or user-owned
fragment is left untouched. Mise and `uv` remain Homebrew-managed applications
and are still installed. Shared agent instructions do not require a runtime
and are linked in this mode too.

### Platform and development-only dependencies

Neovim also needs `curl`, `tar`, `gzip`, `unzip`, `diff`, and a C compiler to
populate plugins, parsers, and Undotree's diff view. C/C++ development uses the
platform's C and C++ compilers and standard libraries; the installer checks both
by compiling and linking a small program before changing configuration links.
clangd, clang-format, and CodeLLDB remain Mason-owned editor tools. macOS supplies
its clipboard provider; Linux needs a session-appropriate clipboard provider
when a display is present, and the Linux Brewfile installs the Wayland and X11
providers. Remote sessions without a display fall back to OSC 52 copy inside
Neovim. `make` arrives with the native development tools and enables optional
plugin enhancements, which is Neovim's only use of it. Expect is a test-only
dependency, needed just for the real-PTY Hunk regression test. `fd` is not a
base dependency: fff.nvim owns normal file finding and `rg` is already
available to Telescope.

### Implementation language exceptions

Repository-owned automation and test runners use Lua or shell, following the
[language policy](#implementation-languages). Lua runners use Neovim's
existing runtime. The following exceptions serve specific tools or tests:

- Native tool and document formats remain native, including Homebrew's Ruby-based
  `Brewfile`, JSON/TOML/YAML configuration, and browser-rendered HTML/JavaScript
  reports. Homebrew owns its Ruby runtime; the repository does not add a separate
  Ruby installation.
- The installer embeds C/C++ probes to check real compilation and standard-library
  linking. The uninstaller's embedded C helper calls the platform's exclusive
  rename operation for safe restoration. Both use the platform toolchain.
- The Hunk terminal regression uses Expect/Tcl to drive a real terminal. Expect
  is a test-only prerequisite; see [Neovim validation](nvim/AGENTS.md#headless-specs).
- Language integration fixtures contain small programs in the language under
  test. In particular, Python environment checks need a real Python interpreter
  and its standard-library `venv` module. Mise owns Python, which is also needed
  by the configured Python development tools; it is not the general test runner.

### Version policy and updates

Use the latest stable applications. Compatibility checks enforce minimums tied
to required capabilities or a validated baseline; newer versions are accepted
without requiring a matching version in this repository. Untested releases are
not automatically incompatible. Prereleases that meet the Neovim minimum are
allowed, with an advisory in `:checkhealth`.

Check available Homebrew updates deliberately with `brew update` followed by
`brew outdated`; install chosen updates with `brew upgrade <package>`.
These checks do not run during shell or editor startup. The installer retains
its `--no-upgrade` policy. ([Homebrew commands](https://docs.brew.sh/Manpage))

Keep runtime updates as exact Mise manifest edits and retain the plugin lockfile.
Use [Neovim's maintenance commands](nvim/README.md#configuration) for plugin and
editor-tool updates. Validate relevant workflows after updates.

For an agent-led full or scoped upgrade, use the shared
[upgrade-dependencies skill](.agents/skills/upgrade-dependencies/SKILL.md).
Ask an agent to read that file and upgrade the managed stack, or name a subset
such as Neovim. It follows the same ownership, validation, and review workflow.

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

### Implementation languages

Use Lua or shell for repository-owned automation and test orchestration. Use
shell for bootstrap and command-oriented work, and Lua for Neovim configuration
or structured logic. Lua test runners use the existing Neovim runtime; do not
add a standalone Lua runtime or a general-purpose Python harness.

Use a tool's native configuration format where required. Other languages are
appropriate for focused fixtures that exercise that language, or for a tool or
platform interface that Lua and shell cannot adequately provide. Document each
exception's purpose and dependency ownership in the
[implementation language exceptions](#implementation-language-exceptions).
Keep these exceptions narrow; supporting Python development does not make
Python the repository's automation language.

## Workflow constraints

Herdr app is the daily setup, on macOS and in spaces on SSH-connected Linux
machines. Ghostty with Herdr TUI and Rex stay installed and configured on the
shelf: keep their configuration working, but do not describe or design for them
as the default.

Herdr app, Herdr TUI, and tmux are top-level alternatives. Use the task's
running environment for editor and review tabs; do not nest tmux inside either
Herdr environment. Usage is documented in the [Herdr app](herdr-app/README.md),
[Herdr](herdr/README.md), and [tmux](tmux/README.md) guides. Agents operating
Herdr app or `hc` use the shared
[`herdr-app` skill](docs/agents/skills/herdr-app/SKILL.md).

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
before branch, review, or landing operations. It owns the always-loaded rules —
checkout, WIP, review, approval, and landing (`CONTEXT.md` defines the terms,
including Workflow Exception) — and points to the
[`development-review` skill](docs/agents/skills/development-review/SKILL.md)
for the review, landing, and delivery procedure, to the
[`herdr-app` skill](docs/agents/skills/herdr-app/SKILL.md) for Herdr app, and
to the [`parallel-worktrees` skill](docs/agents/skills/parallel-worktrees/SKILL.md)
for coordinated work across worktrees. Carry
out their checks directly with Git, Neovim, Hunk, and the task's terminal
environment; no workflow executable is required. All three skills are installed
as global guidance for all three harnesses; see
[ADR 0016](docs/adr/0016-split-the-agent-workflow-into-rules-and-skills.md) and
[ADR 0017](docs/adr/0017-run-parallel-work-from-a-clean-root-checkout.md).
Keep the shared workflow and global skills free of employer-internal tool,
service, and host names: machine-installed instructions supply those. Do not
restate the workflow's rules here or in other repo docs; link to it.

### Agent Harnesses

- Treat the user-facing code interface as Neovim plus terminal tools, regardless of which agent harness is active.
- Keep harness-specific instructions as thin adapters into shared repo guidance.
- Do not add Codex-only or Claude-only workflows when a shared command, file, or review surface can express the same behavior.
- Hunk is the direct full Review Surface from Neovim for both the working tree and the index and the Diffing Solution inside lazygit; lazygit remains the Git Transaction Surface and keeps its native staging UI.

## Architecture Notes

### File Organization

- Each configured application maintains its own subdirectory under the repo root, mirroring the XDG layout under `~/.config/`; Herdr and Hunk link only `config.toml` so mutable state stays untracked. Herdr app links only its personal files, keeping generated files and runtime state local.
- The always-loaded portable agent rules live in `docs/agents/development-workflow.md`; harness-global instruction paths link directly to it. Procedures that are needed only at certain steps belong in global skills. Keep dotfiles-specific constraints here.
- Global skills live in `docs/agents/skills/<name>/SKILL.md` using the Agent Skills format and are linked into `~/.agents/skills/` (Codex and pi) and `~/.claude/skills/` (Claude Code). Keep each skill harness-neutral, with harness differences as short notes inside it. Point to installed upstream guides such as `hc --skill` instead of copying them. Repository-scoped skills stay in `.agents/skills/`; do not put a global skill there, because Codex would list it twice inside this checkout.
- Follow tool-specific guidance where present: [Herdr](herdr/AGENTS.md),
  [Herdr app](herdr-app/AGENTS.md),
  [Neovim](nvim/AGENTS.md), and [tmux](tmux/AGENTS.md).
- Long-lived architecture review reports that the user chooses to retain live under `docs/`; generated reports should not remain at the repository root
- Configurations are environment-specific and not intended for multi-user scenarios
- Keep documentation ownership explicit: the root README is the minimal human
  front page (quick start, layout, daily entry points, rollback); this file
  owns the dependency inventory, shared agent instructions, and the
  install/uninstall contracts; tool READMEs own usage, commands, keybindings,
  and troubleshooting; AGENTS files own constraints, ownership, and validation.
  Keep workflow rules in [the development workflow](docs/agents/development-workflow.md)
  and its procedures in [the global skills](docs/agents/skills/),
  decisions in ADRs, and domain definitions in `CONTEXT.md`. Link to each owner
  instead of duplicating its explanations.

### Tool Integration Points

- **Editor ↔ Git**: Neovim integrates with both gitsigns and lazygit
- **Shell ↔ Editor**: Fish and zsh own the global editor contract (`EDITOR`, `VISUAL`, and `GIT_EDITOR` all point to `nvim`)
- **Terminal tool ↔ Editor**: flatten.nvim handles editor handoff from nested `nvim` calls back into the host Neovim; the shared terminal-tool module owns the opaque source marker and post-handoff policy while preserving the shell-owned `EDITOR` contract
- **Neovim ↔ Terminal tools**: Neovim-owned terminal tools use `nvim/lua/custom/lib/terminal_tool.lua`: one persistent Tool Tab per selected tool instance, singleton by default and keyed by canonical Git checkout root for Hunk, with flatten.nvim for Editor Handoff and host tmux prefix and pane navigation kept upstream when using the fallback
- **Shell ↔ Workspace manager**: Herdr app (and shelved Ghostty) launch the system shell; interactive zsh hands off to Fish with `exec fish`; Herdr app is the daily workspace, with Herdr TUI or tmux started directly when chosen
- **Runtime Management**: Mise owns language runtimes; Mason owns editor tooling
- **Keybinding Constraints**: Option/Alt is reserved for FlashSpace workspace management; terminal shortcuts use Cmd or Ctrl modifiers instead, and Ghostty keeps its native word-navigation shortcuts. Herdr app keeps its native macOS keymap, including Option combinations.

Keep the macOS-first setup Linux-compatible where practical. Update the
[dependency inventory](#dependency-ownership) when ownership or
version requirements change.

## Shared agent instructions

`install.sh` links the complete
[agent development workflow](docs/agents/development-workflow.md) into these
global instruction locations:

| Harness     | Default managed path                      | Configured location                                                |
| ----------- | ----------------------------------------- | ------------------------------------------------------------------ |
| Codex       | `~/.codex/AGENTS.md`                      | `$CODEX_HOME/AGENTS.md` when `CODEX_HOME` is set                   |
| Pi          | `~/.pi/agent/AGENTS.md`                   | `$PI_CODING_AGENT_DIR/AGENTS.md` when `PI_CODING_AGENT_DIR` is set |
| Claude Code | `~/.claude/rules/development-workflow.md` | Fixed global rules location                                        |

The harnesses load these instructions automatically. All links share one
source, so editing the workflow updates the installed instructions. No Herdr
plugin or separate workflow executable is required. Harness
binaries remain optional and are installed separately; the links are created
even when a harness is not installed yet.

`install.sh` also links each shared skill under `docs/agents/skills/` into the
global skill directories. Skills follow the open
[Agent Skills](https://agentskills.io) format, so one directory serves every
harness, and agents load a skill only when its description matches the task:

| Harness      | Global skill directory    |
| ------------ | ------------------------- |
| Codex and Pi | `~/.agents/skills/<name>` |
| Claude Code  | `~/.claude/skills/<name>` |

| Skill                                                                  | Purpose                                                                                                                                                                                                         |
| ---------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`development-review`](docs/agents/skills/development-review/SKILL.md) | Review, findings, adversarial review on request, approval, landing, and optional delivery as a code review submission or GitHub pull request, with one procedure on every machine                               |
| [`herdr-app`](docs/agents/skills/herdr-app/SKILL.md)                   | Driving Herdr app and `hc`: finding the agent's machine and tab, showing a tab when asked, starting and messaging agents, and harness-specific pitfalls                                                         |
| [`parallel-worktrees`](docs/agents/skills/parallel-worktrees/SKILL.md) | Running parallel worktrees from a clean root checkout: independent ideas, or a manager and workers on a coordinated feature with a canonical WIP branch, review pieces, testing, recovery, handoff, and cleanup |

An existing skill with the same name, or a redirected skill directory, stops
installation so that personal skills stay active. Repository-scoped skills
under `.agents/skills/` remain local to this checkout.

Existing unmanaged instruction files and legacy devflow guidance blocks stop
installation with an actionable migration message. Preserve unrelated personal
instructions when preparing those paths; the installer does not silently move
active guidance out of the harness's search path. Claude's existing
`~/.claude/CLAUDE.md` remains user-owned.
Codex's `AGENTS.override.md` also needs reconciliation because it shadows the
managed `AGENTS.md`; symlinked harness root directories require explicit
reconciliation before installation.

For an older devflow installation, follow the
[agent removal guide](docs/agents/remove-legacy-devflow.md) to remove the owned
tool environment, legacy hooks, and guidance before completing migration. Keep historical
`.git/devflow/` records and WIP/review refs. They are separate from the retired
application; historical records alone do not establish current review approval.

## Agent skills

For installation or reapplying the current setup, read
[install](.agents/skills/install/SKILL.md). It runs the existing installer and
assesses the setup before and after, handling verification and machine-specific
decisions beyond the script.

For dependency upgrades or upgrade inspection, read
[upgrade-dependencies](.agents/skills/upgrade-dependencies/SKILL.md). It covers the
managed stack or a requested subset and can be followed directly by any harness.

### Working TODOs

`TODO.md` and the index in `docs/todos/README.md` list active work only; briefs under `docs/todos/` exist only for active items. Follow the lifecycle in that README. When retiring an item, remove both index entries and delete its brief in the same change after preserving any durable knowledge in its proper home.

### Issue tracker

Issues, specs, and PRDs are tracked in GitHub Issues for `desaidn/dotfiles`; external PRs are not a triage request surface. See `docs/agents/issue-tracker.md`.

### Triage labels

Use the default five-label triage vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, and `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

This repo uses a single-context domain docs layout. See `docs/agents/domain.md`.

## Per-machine activation

The `fish` and `zsh` rc files source an optional per-machine file if it exists:

- `~/.local/share/dotfiles/local.fish`
- `~/.local/share/dotfiles/local.zsh`

On first run, `install.sh` publishes complete templates atomically for files
that do not already exist. Interrupted creation cannot expose a partial file,
and existing user content is preserved. They contain `mise activate`,
`mise completion`, `atuin init`, and Homebrew activation for all three standard
prefixes, plus optional fallback paths for per-machine tools (Atuin
self-install, `bun`, `ghcup`, `cabal`, `lmstudio`, `claude/local`, and
JetBrains Toolbox scripts).
The templates preserve an inherited runtime's PATH priority while putting
Homebrew's dedicated Mise executable directory ahead of older standalone
installations. This keeps activation and later `mise` commands on the
Homebrew-managed version without displacing active virtual environments.
Zsh-only completion and history setup is skipped when handing off to Fish.
Edit freely; these files live outside the repo.

Template changes apply to new files only. For an existing installation, compare
your `local.fish` and `local.zsh` with the tracked templates and merge the relevant
changes while retaining machine-specific settings. Re-running the installer
intentionally preserves these user-owned files.

The shared shell rc files set `EDITOR`, `VISUAL`, and `GIT_EDITOR` to `nvim`;
per-machine files should only override that when a machine genuinely needs a
different editor contract.

## Repository tests

```bash
./tests/install_test.sh
```

The test runs the real installer and uninstaller against isolated macOS and
Linux fixtures with fake Homebrew, Mise, `apt-get`, DNF, YUM, and Pacman
commands.
It requires a working Neovim executable to exercise the shared compatibility
helper against simulated versions in an isolated process, plus the platform
C compiler and SDK to build and exercise the real exclusive-rename helper.
It verifies fresh provisioning, manifest ownership, preflight failures,
shared instruction ownership and migration conflicts, backup/link behavior,
explicit runtime-skip setup, safe restoration,
and a mutation-free second run without touching the network, sudo, package
managers, or the caller's home directory.

The same suite covers Herdr app provisioning, configuration linking, and the
global skill links.
See the [Herdr app guide](herdr-app/README.md#validation) for running-window checks.

`nvim --clean --headless -l tests/shell_test.lua` exercises real Fish, Zsh,
Homebrew shellenv, and available Ghostty integration scripts with isolated HOME
and XDG directories. It requires Neovim, Fish, Zsh, Homebrew, and Git. The real
virtual-environment regression additionally uses `python3` and its `venv` module;
when Python is absent, that check reports a skip while the other shell checks
still run. Ghostty integration also reports a skip when its resources are absent.
`bash tests/nvim_performance_test.sh` checks benchmark configuration selection
using a tiny fixture init and real Neovim.

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
  constructing or changing user paths. The installer runs as a normal user
  with sudo access; Homebrew and this dotfiles setup intentionally refuse a
  root-owned installation.
- Keep `install.sh` and `uninstall.sh` self-contained at the user-path safety
  boundary; duplicate their small guards and ownership predicate rather than
  introducing a sourced bootstrap helper.
- Preflight the Brewfile, every tracked link/template source, and blocking
  parent paths before installing dependencies or changing link targets, and
  reject a checkout or configuration source that overlaps an installation
  target.
- Perform all dependency installation and validation before changing link
  targets, so a partial bootstrap can be resumed safely.
- Serialize configuration linking and backup creation across installer processes;
  recheck destination preflight while holding the link-phase lock. A competing
  run stops with the lock path. If an abruptly killed process leaves
  `~/.local/share/dotfiles/.install-lock`, confirm no installer is running,
  then remove that empty directory with `rmdir` and retry.
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
- Link Herdr app personal files individually under `HERDR_APP_HOME` (default
  `~/.config/herdr-app`; the override must name another absolute home),
  keeping generated files and runtime state local. Herdr manages its keymap,
  welcome flow, and shared preferences; custom files and existing app state
  are preserved. Linux skips the app and its configuration.
- Link the complete shared workflow into Codex and pi global `AGENTS.md` files
  and Claude's global `rules/development-workflow.md`, including in degraded
  mode and when a harness is not installed. Honor validated `CODEX_HOME` and
  `PI_CODING_AGENT_DIR` overrides.
- Link each shared skill directory under `docs/agents/skills/` into
  `~/.agents/skills/` and `~/.claude/skills/`, including in degraded mode. These
  user skill locations do not follow `CODEX_HOME` or `PI_CODING_AGENT_DIR`.
  Treat them like instruction files: reject an existing skill of the same name
  or a redirected skill container instead of backing it up.
- Preserve unrelated global instructions and skills. Reject conflicting global
  overrides, unmanaged destinations, legacy devflow guidance, and blocked parent
  paths during preflight; migration is explicit, not a hidden installer rewrite.
- Do not provision a workflow executable, private Python environment, harness
  plugin, hooks, or new review-state storage. The shared document and the global
  skills under `docs/agents/skills/` are the only maintained workflow policy;
  native harness loaders supply their contents.
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
  uninstall must remain independent of compilation. The destination filesystem
  must support exclusive rename: an unsupported operation fails with the backup
  preserved, and restoration never falls back to copy-and-remove.
- Leave older backups, foreign links, installed packages and runtimes,
  per-machine activation files, and unrelated state under
  `~/.local/share/dotfiles/` untouched. A successful second run is a no-op.
- Remove only owned global instruction and skill links, preserving personal
  guidance, other rules/skills, custom profile contents, and historical review records.
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
