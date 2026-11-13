# dotfiles

Personal config monorepo. Clone into a directory such as `~/dotfiles`, run `./install.sh`, and your system is wired up via symlinks into `~/.config/` and `~/`. Keep the checkout outside the configuration paths the installer replaces; overlapping paths are rejected before provisioning.

The setup is designed around one uniform code interface: Herdr app is the daily terminal and workspace, Neovim is the development surface, terminal tools provide supporting workflows, and agent harnesses such as Codex or Claude Code are interchangeable drivers rather than separate ways of working. Tmux remains available as a deliberate fallback and compatibility multiplexer. The dependency posture is native-first and locally-owned: use Neovim's built-in APIs and standard terminal capabilities before adding plugin frameworks, and prefer small purpose-built tools with clear CLI boundaries over broad external layers.

[Herdr app](herdr-app/README.md) is the daily terminal and workspace setup. It
uses its native shortcuts with a personal dark terminal theme, and reaches
remote Linux machines over SSH. Ghostty with
[Herdr TUI](herdr/README.md) and [Rex](rex/README.md) stay installed and
configured on the shelf: they keep working when chosen, but are not the
default.

## Layout

| Source              | Target                       | Notes                                                     |
| ------------------- | ---------------------------- | --------------------------------------------------------- |
| `fish/`             | `~/.config/fish/`            | Prompt + `nvim-reset` alias. Platform-agnostic.           |
| `ghostty/`          | `~/.config/ghostty/`         | macOS Ghostty terminal config.                            |
| `herdr/config.toml` | `~/.config/herdr/config.toml` | Shelved Herdr TUI config; mutable runtime state is local. |
| `herdr-app/` | Personal files under `~/.config/herdr-app/` | Daily macOS app appearance settings and theme; file-level links only. |
| `hunk/config.toml`  | `~/.config/hunk/config.toml`  | Review preferences; mutable runtime state remains local.  |
| `lazygit/`          | `~/.config/lazygit/`         | Git Transaction Surface with Hunk as its Diffing Solution. |
| `mise/conf.d/00-dotfiles.toml` | `~/.config/mise/conf.d/00-dotfiles.toml` | Global runtime defaults; user config can override them. |
| `docs/agents/development-workflow.md` | Harness-global instruction files | Shared workflow, automatically loaded by Codex, Pi, and Claude Code; paths below. |
| `docs/agents/skills/<name>/` | `~/.agents/skills/<name>`, `~/.claude/skills/<name>` | Shared global skills for Codex, Pi, and Claude Code; see below. |
| `nvim/`             | `~/.config/nvim/`            | kickstart-based config using native `vim.pack`.           |
| `rex/macos.sh`      | macOS `com.superlogical.rex` preferences | Manually applied appearance settings; personal experiment. |
| `tmux/`             | `~/.config/tmux/`            | Fallback multiplexer with 1-indexed windows and panes.    |
| `zsh/.zshrc`        | `~/.zshrc`                   | λ prompt + `nvim-reset` alias. No OMZ dependency.         |

Usage guides: [Neovim](nvim/README.md), [Herdr](herdr/README.md),
[Herdr app](herdr-app/README.md),
[tmux](tmux/README.md), [LazyGit](lazygit/README.md), [Fish](fish/README.md),
[Zsh](zsh/README.md), [Ghostty](ghostty/README.md), [Rex](rex/README.md), and the
[agent development workflow](docs/agents/development-workflow.md). Coding-agent constraints live in
[AGENTS.md](AGENTS.md) and the relevant tool's guidance.

## Quick start

| Platform | Repository support |
| --- | --- |
| macOS | Primary platform; local editor integration and installer fixture tests pass. |
| Linux | Installer support and simulated bootstrap tests; the complete setup has not been validated on a Linux host. |
| Native Windows | Unsupported by this setup: the installer targets Unix. |

Neovim itself supports macOS, Linux, and Windows; its [platform support](https://neovim.io/doc/user/support.html)
does not imply that this entire dotfiles setup supports each platform.

```bash
git clone https://github.com/desaidn/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh
```

For agent-assisted installation, use the repository-local
[install skill](.agents/skills/install/SKILL.md). It assesses the machine before
and after running the installer, verifies the intended workflows, and handles
configuration choices, preserved personal settings, and manual setup steps that
the script cannot reasonably decide.

Near the end on Linux, the script prints the absolute command that enters the
configured Fish environment. Run that command after installation; at the
standard Homebrew prefix it is:

```bash
exec "/home/linuxbrew/.linuxbrew/bin/fish" -l
```

The installer does not change the account's login shell.

On a host that cannot install the pinned Mise runtimes, complete the remaining
setup explicitly in degraded mode:

```bash
./install.sh --skip-mise-runtimes
```

`install.sh` is **idempotent and non-destructive**:

- It installs missing platform prerequisites, Homebrew, the tracked
  [`Brewfile`](Brewfile), and the runtimes in
  [`mise/conf.d/00-dotfiles.toml`](mise/conf.d/00-dotfiles.toml).
- On macOS, a missing Xcode Command Line Tools install may require completing
  Apple's system dialog and rerunning the script. On Linux, native bootstrap
  packages are supported through `apt-get`, `dnf`, `yum`, and `pacman`.
- On macOS, it installs missing Ghostty, JetBrains Mono, Herdr app, Raycast,
  and FlashSpace casks, preserving compatible manual installations. Herdr app's
  cask requires Apple Silicon; the app handles Herdr core installation on first
  launch.
- Herdr app personal files are linked individually, with generated files and
  runtime state kept local. `HERDR_APP_HOME` may select another absolute home.
  Herdr manages its keymap, welcome flow, and shared preferences. Custom files
  and existing app state are preserved. Linux skips its app and configuration.
- Run it as a normal user with sudo access. Homebrew and this dotfiles setup
  intentionally refuse a root-owned installation.
- Existing files/dirs at ordinary configuration link targets are renamed to
  `<path>.bak.<unix-timestamp>`, never deleted. Existing unmanaged global
  instruction files require explicit migration before installation.
- Configuration linking is serialized so concurrent installers cannot replace
  each other's backups. A competing run stops with the lock path. If an abruptly
  killed process leaves `~/.local/share/dotfiles/.install-lock`, confirm no
  installer is running, then remove that empty directory with `rmdir` and retry.
- Re-running it with the current manifests performs checks and no package or
  link mutations. Brew is invoked with `--no-upgrade`, so the installer does
  not request broad upgrades; Homebrew may still upgrade a dependency when a
  newly installed formula requires it.
- `--skip-mise-runtimes` skips runtime installation and validation and does
  not create or update the tracked Mise fragment link. It never removes an
  existing fragment. Shared agent instructions are still linked; Mise and `uv`
  remain Homebrew-managed applications.
- It links the shared workflow into each supported harness's global instruction
  location, including when that harness is not installed yet.
- `./uninstall.sh` removes only symlinks owned by this repository. It does not
  uninstall dependencies or runtimes.
  `./uninstall.sh --restore` also restores the newest unambiguous backup where
  that can be done without replacing user state.

## Daily workspace

On macOS, open Herdr app for the daily workspace. Work on a Linux machine,
such as a remote development host, happens in spaces on that machine after adding it
under Settings → Machines; see the [Herdr app guide](herdr-app/README.md#work-on-another-machine).

```bash
# Daily workspace on macOS
herdr-app

# Shelved alternative: Herdr TUI, from Ghostty or an SSH shell
herdr

# Deliberate fallback/compatibility session
tmux new-session -A -s dev
```

These are top-level alternatives. Herdr TUI keeps its own server and state,
separate from Herdr app's core; plain `herdr` still starts or reattaches it on
macOS or Linux. Tmux remains independently available for tmux-specific
workflows.

## Shared agent instructions

`install.sh` links the complete
[agent development workflow](docs/agents/development-workflow.md) into these
global instruction locations:

| Harness | Default managed path | Configured location |
| --- | --- | --- |
| Codex | `~/.codex/AGENTS.md` | `$CODEX_HOME/AGENTS.md` when `CODEX_HOME` is set |
| Pi | `~/.pi/agent/AGENTS.md` | `$PI_CODING_AGENT_DIR/AGENTS.md` when `PI_CODING_AGENT_DIR` is set |
| Claude Code | `~/.claude/rules/development-workflow.md` | Fixed global rules location |

The harnesses load these instructions automatically. All links share one
source, so editing the workflow updates the installed instructions. No Herdr
plugin or separate workflow executable is required. Harness
binaries remain optional and are installed separately.

`install.sh` also links each shared skill under `docs/agents/skills/` into the
global skill directories. Skills follow the open
[Agent Skills](https://agentskills.io) format, so one directory serves every
harness, and agents load a skill only when its description matches the task:

| Harness | Global skill directory |
| --- | --- |
| Codex and Pi | `~/.agents/skills/<name>` |
| Claude Code | `~/.claude/skills/<name>` |

| Skill | Purpose |
| --- | --- |
| [`development-review`](docs/agents/skills/development-review/SKILL.md) | Review, findings, adversarial review on request, approval, landing, and delivery, with one procedure on every machine |
| [`herdr-app`](docs/agents/skills/herdr-app/SKILL.md) | Driving Herdr app and `hc`: finding the agent's machine and tab, showing a tab when asked, starting and messaging agents, and harness-specific pitfalls |
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

The [agent development workflow](docs/agents/development-workflow.md) owns the
always-loaded WIP, review, approval, and landing rules; the
[`development-review` skill](docs/agents/skills/development-review/SKILL.md)
owns their procedure, including optional delivery as a code review submission
or GitHub pull request. Neovim and Hunk reviews
open in the task's terminal environment: Herdr app, Herdr TUI, tmux, or an
ordinary terminal. These rules apply only to coding agents; human Git and
LazyGit operations remain unrestricted.

## Dependency ownership

`install.sh` provisions these dependencies according to one ownership rule per
layer:

- The platform bootstraps Homebrew and the C/C++ compilers, SDKs, download, and
  archive tools that Homebrew and Neovim need. On macOS that means Xcode Command
  Line Tools; on Linux it means the distribution's development-tools packages.
- Homebrew owns applications and standalone CLIs.
- Mise owns versioned language runtimes.
- Neovim owns plugins, Treesitter parsers, and the LSP/formatter/linter/debugger
  packages declared in its language configuration.

### Homebrew applications

| Package | Requirement in this repo |
| --- | --- |
| `git` | Plugin retrieval and all Git-facing tools |
| `fish` | Primary shell; version 3.2 or newer |
| `zsh` | Secondary/login-shell handoff |
| `neovim` | `nvim`; version 0.12.5 or newer |
| `herdr` | Herdr TUI, the shelved alternative workspace manager |
| `tmux` | Fallback multiplexer; version 3.5 or newer for `extended-keys-format` |
| `lazygit` | Git Transaction Surface; version 0.64.0 or newer for `git.diffRenderers` |
| `hunk` | Diffing Solution and stacked working-tree and staged Review Surface; version 0.18.1 or newer for efficient concurrent watch sessions (0.12 introduced LazyGit rendering) |
| `mise` | Language runtime manager |
| `atuin` | Shell history integration |
| `gh` | GitHub issue workflows described under `docs/agents/` |
| `ripgrep` | `rg`; Neovim Telescope grep |
| `tree-sitter-cli` | `tree-sitter` 0.26.1 or newer; parser management |
| `cmake` | C/C++ project configuration, compilation databases, and CTest |
| `ninja` | Build runner for CMake projects that select the Ninja generator |
| `uv` | Python project and dependency management CLI; Mise continues to own Python runtimes |
| `xclip`, `wl-clipboard` | Linux X11 and Wayland clipboard providers |

On macOS, the setup also uses the `ghostty`, `font-jetbrains-mono`,
`herdr-app`, `raycast`, and `flashspace` casks. The installer provisions casks
separately from the Brewfile to preserve compatible manual installations.
Ghostty 1.3.0 or newer is required for its native glass background; Herdr app 0.1.12 is the validated
configuration baseline and newer versions are accepted. Its cask requires
Apple Silicon. Ghostty and Herdr app configuration is skipped on Linux.
Herdr app owns installation and updates of its Herdr core dependency; the
existing `herdr` Homebrew formula remains the independent TUI.

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
fragment is left untouched. Shared agent instructions do not require a runtime
and are linked in this mode too.

### Platform and development-only dependencies

Neovim also needs `curl`, `tar`, `gzip`, `unzip`, `diff`, and a C compiler to
populate plugins, parsers, and Undotree's diff view. C/C++ development uses the
platform's C and C++ compilers and standard libraries; the installer checks both
by compiling and linking a small program before changing configuration links.
clangd, clang-format, and CodeLLDB remain Mason-owned editor tools. macOS supplies
its clipboard provider; the Linux Brewfile installs Wayland and X11 providers.
Remote sessions without a display fall back to OSC 52 copy inside Neovim.
`make` arrives with the native development tools and enables optional plugin
enhancements. Expect is needed only for the real-PTY Hunk regression test.
`fd` is not a base dependency: fff.nvim owns normal file finding and `rg` is
already available to Telescope.

### Implementation language exceptions

Repository-owned automation and test runners use Lua or shell, following the
[language policy](AGENTS.md#implementation-languages). Lua runners use Neovim's
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
not automatically incompatible. Neovim installation, startup, and health checks
share [one minimum-version rule](nvim/lua/custom/lib/neovim.lua), currently 0.12.5.
Prereleases that meet the minimum are allowed, with an advisory in `:checkhealth`.

Check available Homebrew updates deliberately with `brew update` followed by
`brew outdated`; install chosen updates with `brew upgrade <package>`.
These checks do not run during shell or editor startup. The installer retains
its `--no-upgrade` policy. ([Homebrew commands](https://docs.brew.sh/Manpage))

Keep runtime updates as exact Mise manifest edits and retain the plugin lockfile.
Use [Neovim's maintenance commands](nvim/README.md#configuration) for plugin and
editor-tool updates. Validate relevant workflows after updates and raise a
minimum only when a required capability or known incompatibility justifies it.

For an agent-led full or scoped upgrade, use the shared
[upgrade-dependencies skill](.agents/skills/upgrade-dependencies/SKILL.md).
Ask an agent to read that file and upgrade the managed stack, or name a subset
such as Neovim. It follows the same ownership, validation, and review workflow.

See [the dependency research note](docs/dependency-research.md) for package
mapping and primary-source evidence.

## Per-machine activation

The `fish` and `zsh` rc files source an optional per-machine file if it exists:

- `~/.local/share/dotfiles/local.fish`
- `~/.local/share/dotfiles/local.zsh`

On first run, `install.sh` publishes complete templates atomically for files
that do not already exist. Interrupted creation cannot expose a partial file,
and existing user content is preserved. They contain `mise activate`, `mise completion`, `atuin init`, and
Homebrew activation for all three standard prefixes, plus optional fallback
paths for per-machine tools (`bun`, `ghcup`, `lmstudio`, `claude/local`).
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

The shared shell rc files set `EDITOR`, `VISUAL`, and `GIT_EDITOR` to `nvim`; per-machine files should only override that when a machine genuinely needs a different editor contract.

## Installer tests

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

## Rollback

After `install.sh` runs, anything it moved aside is at
`<original>.bak.<timestamp>`. To remove managed links or safely restore the
newest numeric backup:

```bash
./uninstall.sh             # remove repository-owned symlinks
./uninstall.sh --restore   # remove links and restore safe, unambiguous backups
```

`--restore` first builds a temporary helper with the platform C compiler (`cc`)
and SDK already required for installation. It uses the native exclusive-rename
operation so a file, directory, or symlink appearing at a restore destination
cannot be overwritten or receive the backup as a nested entry. If the helper
cannot be built, restoration stops before changing managed links or backups.
The helper is removed on exit; ordinary uninstall does not require compilation.
The destination filesystem must support exclusive rename. Unsupported operations
fail with the backup preserved; restoration never falls back to copy-and-remove.

Restoration never replaces an occupied path. If both a nested directory backup
and a file backup exist, or a directory backup cannot replace its directory
because that directory contains additional user files, the group is left
untouched and the command exits nonzero for manual resolution.
Older backups, installed packages and runtimes, per-machine activation files,
and unrelated state under `~/.local/share/dotfiles/` remain untouched.
