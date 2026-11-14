# dotfiles

Personal config monorepo. Clone it outside the configuration paths the
installer manages (for example `~/dotfiles`), run `./install.sh`, and the
system is wired up via symlinks into `~/.config/` and `~/`.

[Herdr app](herdr-app/README.md) is the daily terminal and workspace, Neovim
is the development surface, and agent harnesses such as Codex or Claude Code
are interchangeable drivers rather than separate ways of working. Ghostty with
[Herdr TUI](herdr/README.md) stays installed and configured on the shelf,
[Rex](rex/README.md) is a manually installed personal experiment, and tmux
remains a deliberate fallback multiplexer.
[AGENTS.md](AGENTS.md) is the canonical guide to the design, dependencies, and
contracts behind this setup.

## Quick start

| Platform | Repository support |
| --- | --- |
| macOS | Primary platform; local editor integration and installer fixture tests pass. |
| Linux | Installer support and simulated bootstrap tests; the complete setup has not been validated on a Linux host. |
| Native Windows | Unsupported by this setup: the installer targets Unix. |

Neovim itself supports macOS, Linux, and Windows; its
[platform support](https://neovim.io/doc/user/support.html) does not imply
that this entire dotfiles setup supports each platform.

```bash
git clone https://github.com/desaidn/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh
```

`install.sh` is idempotent and non-destructive: it installs missing
dependencies, renames anything at an ordinary configuration link target to
`<path>.bak.<unix-timestamp>` instead of deleting it, and a re-run with the
current manifests performs checks without package or link mutations. Existing
unmanaged agent instruction or skill files stop installation for explicit
migration instead of being moved. Run it as a normal user with sudo access.
The [Install Contract](AGENTS.md#install-contract) specifies the full behavior.

For agent-assisted installation, use the repository-local
[install skill](.agents/skills/install/SKILL.md). It assesses the machine
before and after running the installer, verifies the intended workflows, and
handles configuration choices, preserved personal settings, and manual setup
steps that the script cannot reasonably decide.

Near the end on Linux, the script prints the absolute command that enters the
configured Fish environment. Run that command after installation; at the
standard Homebrew prefix it is
`exec "/home/linuxbrew/.linuxbrew/bin/fish" -l`. The installer does not change
the account's login shell.

On a host that cannot install the pinned Mise runtimes, complete the remaining
setup explicitly in degraded mode with `./install.sh --skip-mise-runtimes`;
see [the Install Contract](AGENTS.md#install-contract) for its exact scope.

## Layout

| Source              | Target                       | Notes                                        |
| ------------------- | ---------------------------- | -------------------------------------------- |
| `fish/`             | `~/.config/fish/`            | Prompt + `nvim-reset` alias                  |
| `ghostty/`          | `~/.config/ghostty/`         | macOS Ghostty terminal config                |
| `herdr/config.toml` | `~/.config/herdr/config.toml` | Shelved Herdr TUI config                    |
| `herdr-app/`        | Personal files under `~/.config/herdr-app/` | Daily app settings and theme; file-level links only |
| `hunk/config.toml`  | `~/.config/hunk/config.toml`  | Review preferences                          |
| `lazygit/`          | `~/.config/lazygit/`         | Git Transaction Surface                      |
| `mise/conf.d/00-dotfiles.toml` | `~/.config/mise/conf.d/00-dotfiles.toml` | Pinned global runtime defaults   |
| `docs/agents/development-workflow.md` | Harness-global instruction files | Shared agent workflow; see [AGENTS.md](AGENTS.md#shared-agent-instructions) |
| `docs/agents/skills/<name>/` | `~/.agents/skills/<name>`, `~/.claude/skills/<name>` | Shared global skills |
| `nvim/`             | `~/.config/nvim/`            | kickstart-based config using native `vim.pack` |
| `rex/macos.sh`      | macOS `com.superlogical.rex` preferences | Manually applied; personal experiment |
| `tmux/`             | `~/.config/tmux/`            | Fallback multiplexer; 1-indexed windows and panes |
| `zsh/.zshrc`        | `~/.zshrc`                   | λ prompt; no OMZ dependency                  |

Mutable runtime state (Herdr, Hunk, Herdr app) stays local and untracked.

## Daily workspace

On macOS, open Herdr app for the daily workspace. Work on a Linux machine,
such as a remote development host, happens in spaces on that machine after
adding it under Settings → Machines; see the
[Herdr app guide](herdr-app/README.md#work-on-another-machine).

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

Per-machine shell overrides live in `~/.local/share/dotfiles/local.fish` and
`local.zsh`; see [per-machine activation](AGENTS.md#per-machine-activation).

## Rollback

```bash
./uninstall.sh             # remove repository-owned symlinks
./uninstall.sh --restore   # remove links and restore safe, unambiguous backups
```

Anything `install.sh` moved aside is at `<original>.bak.<timestamp>`.
`uninstall.sh` removes only symlinks owned by this repository and does not
uninstall dependencies or runtimes. The
[Uninstall Contract](AGENTS.md#uninstall-contract) specifies the restoration
semantics and safety guarantees.

## Guides

Usage guides: [Neovim](nvim/README.md), [Herdr app](herdr-app/README.md),
[Herdr TUI](herdr/README.md), [tmux](tmux/README.md),
[LazyGit](lazygit/README.md), [Fish](fish/README.md), [Zsh](zsh/README.md),
[Ghostty](ghostty/README.md), and [Rex](rex/README.md).

Agent guidance: [AGENTS.md](AGENTS.md) owns constraints, the dependency
inventory, and the install/uninstall contracts; the
[agent development workflow](docs/agents/development-workflow.md) owns the
always-loaded review rules.
