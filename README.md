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
| `lazygit/`          | `~/.config/lazygit/`         | Git TUI with Neovim editor handoff and native staging UI. |
| `mise/conf.d/`      | `~/.config/mise/conf.d/`     | Global runtime defaults; user config can override them.   |
| `nvim/`             | `~/.config/nvim/`            | kickstart-based config using native `vim.pack`.           |
| `tmux/`             | `~/.config/tmux/`            | Fallback multiplexer with 1-indexed windows and panes.    |
| `zsh/.zshrc`        | `~/.zshrc`                   | λ prompt + `nvim-reset` alias. No OMZ dependency.         |

Each subdirectory has its own `README.md` (and `AGENTS.md` where relevant).

## Code interface contract

This repo keeps the interface to code agent-harness agnostic:

- Start and return to Neovim for editing.
- Use Herdr as the normal top-level workspace manager; use tmux directly only for fallback or compatibility work rather than nesting it inside Herdr.
- Prefer native Neovim features and Lua APIs when they can express the workflow clearly.
- Keep external dependencies narrow, durable, and easy to replace; avoid plugin layers that only wrap behavior Neovim already owns.
- Use self-made or locally-owned performant tools when a workflow needs more than native Neovim but should remain inspectable, fast, and independent of an agent harness.
- Use gitsigns for local in-buffer hunk operations.
- Use Hunk directly from Neovim for full stacked working-tree review.
- Use lazygit for Git state, staging, stashes, history, branches, and commits.
- Let shell configuration declare Neovim as the global editor through `EDITOR`, `VISUAL`, and `GIT_EDITOR`.
- Use flatten.nvim for editor handoff from terminal tools back into the host Neovim instance.
- Keep Neovim gitsigns actions hunk-local; buffer-wide Git transactions belong in lazygit.
- Prefer upstream defaults unless a deviation directly supports the uniform code interface.
- Keep Codex, Claude Code, and future harnesses as adapters over the same files, commands, and review surfaces.

Harness-specific files should only bridge into the shared workflow. They should not introduce a second review model, separate Git transaction surface, or different way to open code. Global Git behavior stays outside this contract unless the repo explicitly starts managing Git config.

## Quick start

```bash
git clone https://github.com/desaidn/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh
```

`install.sh` is **idempotent and non-destructive**:

- It installs missing platform prerequisites, Homebrew, the tracked
  [`Brewfile`](Brewfile), and the runtimes in
  [`mise/conf.d/00-dotfiles.toml`](mise/conf.d/00-dotfiles.toml).
- On macOS, a missing Xcode Command Line Tools install may require completing
  Apple's system dialog and rerunning the script. On Linux, native bootstrap
  packages are supported through `apt-get`, `dnf`, and `pacman`.
- Run it as a normal user with sudo access. Homebrew and this dotfiles setup
  intentionally refuse a root-owned installation.
- Existing files/dirs at link targets are renamed to `<path>.bak.<unix-timestamp>`, never deleted.
- Re-running it with the same resolved dependency set performs checks and no
  package or link mutations. It does not upgrade already-installed Brew
  packages.
- Use `./uninstall.sh` to remove the symlinks (and optionally restore the most recent backup).

## Daily workspace

```bash
# Normal daily workspace
herdr

# Deliberate fallback/compatibility session
tmux new-session -A -s dev
```

These are top-level alternatives. Plain `herdr` starts or reattaches the daily workspace; tmux remains independently available when a tmux-specific workflow is required.

## Dependency ownership

`install.sh` provisions these dependencies according to one ownership rule per
layer:

- The platform bootstraps Homebrew and the compiler/download/archive tools
  that Homebrew and Neovim need. On macOS that means Xcode Command Line Tools;
  on Linux it means the distribution's development-tools packages.
- Homebrew owns applications and standalone CLIs.
- Mise owns versioned language runtimes.
- Neovim owns plugins, Treesitter parsers, and the LSP/formatter/linter/debugger
  packages declared in its Language Tooling Inventory.

### Homebrew applications

| Package | Requirement in this repo |
| --- | --- |
| `git` | Plugin retrieval and all Git-facing tools |
| `fish` | Primary shell; version 3.2 or newer |
| `zsh` | Secondary/login-shell handoff |
| `neovim` | `nvim`; exactly stable 0.12.4 |
| `herdr` | Daily workspace manager |
| `tmux` | Fallback multiplexer; version 3.7 or newer |
| `lazygit` | Git transaction surface |
| `hunk` | Stacked working-tree review surface |
| `mise` | Language runtime manager |
| `atuin` | Shell history integration |
| `gh` | GitHub issue workflows described under `docs/agents/` |
| `ripgrep` | `rg`; Neovim Telescope grep |
| `tree-sitter-cli` | `tree-sitter` 0.26.1 or newer; parser management |
| `uv` | Python debugging through nvim-dap-python |
| `ghcup` | Haskell Language Server installation; capability-specific |
| `xclip`, `wl-clipboard` | Linux X11 and Wayland clipboard providers |

On macOS, the configured UI also uses the `ghostty` and
`font-jetbrains-mono` casks. Ghostty configuration is skipped on Linux.

### Mise runtimes

The enabled Neovim language capabilities require Node.js/npm, Python, Rust
with Cargo and Clippy, Go, and a JDK 21 or newer. These runtimes belong to
Mise; Mason installs the corresponding editor tooling. Haskell is the current
exception: Mason's Haskell Language Server recipe invokes `ghcup` directly.

The installer uses the tracked global defaults fragment
[`mise/conf.d/00-dotfiles.toml`](mise/conf.d/00-dotfiles.toml). Its channel
selectors express the runtime update policy, while a user's normal
`~/.config/mise/config.toml` remains untouched and has higher precedence.

### Platform and development-only dependencies

Neovim also needs `curl`, `tar`, `gzip`, `unzip`, `diff`, and a C compiler to
populate plugins, parsers, and Undotree's diff view. macOS supplies its
clipboard provider; the Linux Brewfile installs Wayland and X11 providers.
`make` arrives with the native development tools and enables optional plugin
enhancements. Expect is needed only for the real-PTY Hunk regression test.
`fd` is not a base dependency: fff.nvim owns normal file finding and `rg` is
already available to Telescope.

The exact Neovim 0.12.4 requirement is deliberately validated after Brew
installation. Because Homebrew formulae are rolling, a future Neovim formula
that no longer supplies 0.12.4 will cause a clear validation failure rather
than linking an incompatible editor configuration.

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

The test runs the real installer against isolated macOS and Debian fixtures
with fake package managers. It verifies fresh provisioning, backup/link
behavior, and a mutation-free second run without touching the network, sudo,
Homebrew, or the caller's home directory.

## Rollback

After `install.sh` runs, anything it moved aside is at `~/<original>.bak.<timestamp>` (or `~/.config/<name>.bak.<timestamp>`). To restore:

```bash
./uninstall.sh                    # removes symlinks
mv ~/.zshrc.bak.<ts> ~/.zshrc     # restore by hand if you want the originals back
```
