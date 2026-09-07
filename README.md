# dotfiles

Personal config monorepo. Clone anywhere, run `./install.sh`, and your system is wired up via symlinks into `~/.config/` and `~/`.

The setup is designed around one uniform code interface: Herdr is the daily workspace manager, Neovim is the development surface, terminal tools provide supporting workflows, and agent harnesses such as Codex or Claude Code are interchangeable drivers rather than separate ways of working. Tmux remains available as a deliberate fallback and compatibility multiplexer. The dependency posture is native-first and locally-owned: use Neovim's built-in APIs and standard terminal capabilities before adding plugin frameworks, and prefer small purpose-built tools with clear CLI boundaries over broad external layers.

## Layout

| Source              | Target                       | Notes                                                     |
| ------------------- | ---------------------------- | --------------------------------------------------------- |
| `fish/`             | `~/.config/fish/`            | Prompt + `nvim-reset` alias. Platform-agnostic.           |
| `ghostty/`          | `~/.config/ghostty/`         | macOS Ghostty terminal config.                            |
| `herdr/config.toml` | `~/.config/herdr/config.toml` | Daily workspace config; mutable runtime state is local.   |
| `hunk/config.toml`  | `~/.config/hunk/config.toml`  | Review preferences; mutable runtime state remains local.  |
| `lazygit/`          | `~/.config/lazygit/`         | Git Transaction Surface with Hunk as its Diffing Solution. |
| `mise/conf.d/00-dotfiles.toml` | `~/.config/mise/conf.d/00-dotfiles.toml` | Global runtime defaults; user config can override them. |
| `nvim/`             | `~/.config/nvim/`            | kickstart-based config using native `vim.pack`.           |
| `tmux/`             | `~/.config/tmux/`            | Fallback multiplexer with 1-indexed windows and panes.    |
| `tools/`            | `~/.local/bin/` per tool       | Source workspace for small, independently named agent tools. |
| `zsh/.zshrc`        | `~/.zshrc`                   | λ prompt + `nvim-reset` alias. No OMZ dependency.         |

Usage guides: [Neovim](nvim/README.md), [Herdr](herdr/README.md),
[tmux](tmux/README.md), [LazyGit](lazygit/README.md), [Fish](fish/README.md),
[Zsh](zsh/README.md), [Ghostty](ghostty/README.md), and
[agent tools](tools/README.md). Coding-agent constraints live in
[AGENTS.md](AGENTS.md) and the relevant tool's guidance.

## Quick start

| Platform | Repository support |
| --- | --- |
| macOS | Primary platform; local editor integration and installer fixture tests pass. |
| Linux | Installer support and simulated bootstrap tests; the complete setup has not been validated on a Linux host. |
| Native Windows | Unsupported by this setup: the installer targets Unix and devflow uses Unix file locking. |

Neovim itself supports macOS, Linux, and Windows; its [platform support](https://neovim.io/doc/user/support.html)
does not imply that this entire dotfiles setup supports each platform.

```bash
git clone https://github.com/desaidn/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh
```

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
  [`mise/conf.d/00-dotfiles.toml`](mise/conf.d/00-dotfiles.toml), then installs
  the repository's [`dotfiles-devflow`](tools/devflow/) package as an editable
  `uv` tool.
- On macOS, a missing Xcode Command Line Tools install may require completing
  Apple's system dialog and rerunning the script. On Linux, native bootstrap
  packages are supported through `apt-get`, `dnf`, `yum`, and `pacman`.
- Run it as a normal user with sudo access. Homebrew and this dotfiles setup
  intentionally refuse a root-owned installation.
- Existing files/dirs at link targets are renamed to `<path>.bak.<unix-timestamp>`, never deleted.
- Re-running it with the current manifests performs checks and no package or
  link mutations. Brew is invoked with `--no-upgrade`, so the installer does
  not request broad upgrades; Homebrew may still upgrade a dependency when a
  newly installed formula requires it.
- `--skip-mise-runtimes` skips runtime installation and validation and does
  not create or update the tracked Mise fragment link or Workflow Engine. It
  never removes an existing fragment or owned Workflow Engine. Mise and `uv`
  themselves remain Homebrew-managed applications.
- The generic installer never changes harness-global files under `~/.codex`
  or `~/.claude`; those adapters are an explicit opt-in described below.
- `./uninstall.sh` removes only symlinks and the receipted Workflow Engine
  owned by this repository. It does not uninstall dependencies or runtimes.
  `./uninstall.sh --restore` also restores the newest unambiguous backup where
  that can be done without replacing user state.

## Daily workspace

```bash
# Normal daily workspace
herdr

# Deliberate fallback/compatibility session
tmux new-session -A -s dev
```

These are top-level alternatives. Plain `herdr` starts or reattaches the daily workspace; tmux remains independently available when a tmux-specific workflow is required.

## Workflow Engine installation

The full install exposes `devflow` from `~/.local/bin`. The
`dotfiles-devflow` distribution
lives in the private `~/.local/share/dotfiles/uv-tools/` tool directory and
uses the exact Python selected by the tracked Mise manifest. An ownership
receipt binds that environment to this repository source and interpreter, so
an unchanged second install does not invoke `uv` again. The installer refuses
to overwrite an unreceipted executable, private environment, or ambiguous
receipt. A pending receipt is written before `uv` changes tool state: rerunning
may retry when no tool artifacts exist or finalize an entirely matching tool
environment without reinstalling, while partial or foreign state still stops
for explicit recovery. Ownership checks parse uv's TOML receipt semantically
with the receipted Python interpreter: harmless formatting, ordering, and
comments are accepted, while any extra, missing, duplicate, malformed, or
mismatched inventory is preserved and rejected. Install and uninstall invoke
`uv --no-config` with inherited uv, Python-environment, Conda, and pip settings
removed; network proxy and TLS/CA settings remain available.
The owned public inventory contains only the `devflow` entry point; partial or
foreign tool state is left intact.

Harness-global guidance is separate from installing the shared Workflow
Engine. Opt in explicitly for each harness used on a machine:

```bash
devflow harness install codex
devflow harness install claude
```

These commands manage only their marked guidance blocks. The generic dotfiles
installer does not create or edit `~/.codex/AGENTS.md` or
`~/.claude/CLAUDE.md`.

The [agent development workflow](docs/agents/development-workflow.md) owns the
complete WIP, review, approval, and landing procedure. It uses Herdr, Neovim,
and Hunk for local and external reviews. These rules apply only to coding
agents; human Git and LazyGit operations remain unrestricted.

## Dependency ownership

`install.sh` provisions these dependencies according to one ownership rule per
layer:

- The platform bootstraps Homebrew and the compiler/download/archive tools
  that Homebrew and Neovim need. On macOS that means Xcode Command Line Tools;
  on Linux it means the distribution's development-tools packages.
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
| `herdr` | Daily workspace manager |
| `tmux` | Fallback multiplexer; version 3.5 or newer for `extended-keys-format` |
| `lazygit` | Git Transaction Surface; version 0.64.0 or newer for `git.diffRenderers` |
| `hunk` | Diffing Solution and stacked working-tree and staged Review Surface; version 0.18.1 or newer for efficient concurrent watch sessions (0.12 introduced LazyGit rendering) |
| `mise` | Language runtime manager |
| `atuin` | Shell history integration |
| `gh` | GitHub issue workflows described under `docs/agents/` |
| `ripgrep` | `rg`; Neovim Telescope grep |
| `tree-sitter-cli` | `tree-sitter` 0.26.1 or newer; parser management |
| `uv` | Installs the Python 3.14+ Workflow Engine with Mise's pinned interpreter in an isolated persistent tool environment |
| `xclip`, `wl-clipboard` | Linux X11 and Wayland clipboard providers |

On macOS, the configured UI also uses the `ghostty` and
`font-jetbrains-mono` casks. Ghostty configuration is skipped on Linux.

### Mise runtimes

The enabled Neovim language capabilities require Node.js/npm, Python, Rust
with Cargo, Clippy, rustfmt, and rust-src, and a Java runtime and compiler at
version 21 or newer. These runtimes belong to Mise; Mason installs the declared
editor tooling. TypeScript is a
project-owned semantic exception: each recognized non-Deno workspace supplies
its root-local compiler, and Mason owns only the compatibility transport.
See [Neovim's project requirements](nvim/README.md#language-project-requirements)
for version routing and debugging setup.

The installer uses the tracked global defaults fragment
[`mise/conf.d/00-dotfiles.toml`](mise/conf.d/00-dotfiles.toml). It pins exact
Node.js, Python, and Rust versions plus Amazon Corretto JDK 21 at
`corretto-21.0.12.8.1`, so a successful second run does not silently resolve a
newer runtime. Runtime updates are deliberate manifest edits. Bootstrap
evaluates the tracked fragment in an isolated Mise config directory so user
overrides cannot mask missing pinned runtimes. A user's normal
`~/.config/mise/config.toml` remains untouched and has higher precedence in
interactive shells.

Java compatibility is independent of vendor; Corretto is the deliberate
provisioning choice in the manifest. Devflow accepts Python 3.14 and newer;
the pinned 3.14.7 baseline and isolated 3.15 release-candidate validation are
recorded in [ADR 0009](docs/adr/0009-use-modern-typed-python-for-workflow-automation.md).

`--skip-mise-runtimes` is an explicit degraded setup for hosts that cannot run
the pinned versions. Other dependencies and configurations are installed, but
runtime-dependent language tooling and the Workflow Engine may remain
unavailable. On a fresh setup, the tracked defaults fragment is not linked and
the Workflow Engine is not installed; an existing managed or user-owned
fragment and an existing owned Workflow Engine are left untouched.

### Platform and development-only dependencies

Neovim also needs `curl`, `tar`, `gzip`, `unzip`, `diff`, and a C compiler to
populate plugins, parsers, and Undotree's diff view. macOS supplies its
clipboard provider; the Linux Brewfile installs Wayland and X11 providers.
Remote sessions without a display fall back to OSC 52 copy inside Neovim.
`make` arrives with the native development tools and enables optional plugin
enhancements. Expect is needed only for the real-PTY Hunk regression test.
`fd` is not a base dependency: fff.nvim owns normal file finding and `rg` is
already available to Telescope.

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

See [the dependency research note](docs/dependency-research.md) for package
mapping and primary-source evidence.

## Per-machine activation

The `fish` and `zsh` rc files source an optional per-machine file if it exists:

- `~/.local/share/dotfiles/local.fish`
- `~/.local/share/dotfiles/local.zsh`

On first run, `install.sh` copies templates for files that do not already
exist. They contain `mise activate`, `mise completion`, `atuin init`, and
Homebrew activation for all three standard prefixes, plus gated PATH additions
for per-machine tools (`bun`, `ghcup`, `lmstudio`, `claude/local`)—every line
is a no-op on a machine that lacks the tool. Edit freely; these files live
outside the repo.

The shared shell rc files set `EDITOR`, `VISUAL`, and `GIT_EDITOR` to `nvim`; per-machine files should only override that when a machine genuinely needs a different editor contract.

## Installer tests

```bash
./tests/install_test.sh
```

The test runs the real installer and uninstaller against isolated macOS and
Linux fixtures with fake Homebrew, Mise, `uv`, `apt-get`, DNF, YUM, and Pacman
commands.
It requires a working Neovim executable to exercise the shared compatibility
helper against simulated versions in an isolated process.
It verifies fresh provisioning, manifest ownership, preflight failures,
Workflow Engine ownership, semantic receipt validation, hostile environment
isolation, backup/link behavior, explicit runtime-skip setup, safe restoration,
and a mutation-free second run without touching the network, sudo, package
managers, or the caller's home directory.

## Rollback

After `install.sh` runs, anything it moved aside is at
`<original>.bak.<timestamp>`. To remove managed links or safely restore the
newest numeric backup:

```bash
./uninstall.sh             # remove repository-owned symlinks
./uninstall.sh --restore   # remove links and restore safe, unambiguous backups
```

Restoration never replaces an occupied path. If both a nested directory backup
and a file backup exist, or a directory backup cannot replace its directory
because that directory contains additional user files, the group is left
untouched and the command exits nonzero for manual resolution.
Older backups, installed packages and runtimes, per-machine activation files,
and unrelated state under `~/.local/share/dotfiles/` remain untouched.
