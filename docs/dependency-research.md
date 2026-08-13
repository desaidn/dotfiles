# Dependency installation research

Checked 2026-07-26 against [`install.sh`](../install.sh), the Neovim inventory and bootstrap notes in [`nvim/`](../nvim/), and the repository's [`gh` issue-tracker contract](agents/issue-tracker.md). The resulting installer uses Homebrew as the declared package owner, then validates effective commands on `PATH`; Ghostty and JetBrains Mono also accept manually installed app/font files so Brew never overwrites them.

## Homebrew bootstrap boundary

- **macOS:** A supported Homebrew install requires Apple silicon or 64-bit Intel, macOS Sonoma 14 or newer on supported hardware, current Xcode Command Line Tools (CLT) or Xcode, and `/bin/bash`. Homebrew documents `xcode-select --install` for CLT; Apple confirms that CLT supplies the macOS SDK and toolchain binaries including `clang` and `git`. The supported prefixes are `/opt/homebrew` on Apple silicon and `/usr/local` on Intel. ([Homebrew installation](https://docs.brew.sh/Installation), [Apple CLT](https://developer.apple.com/documentation/xcode/installing-the-command-line-tools/))
- **Linux:** Homebrew must be bootstrapped with a working **system** C compiler and standard development tools; a later Homebrew `gcc` install does not replace that prerequisite. Homebrew's official examples are `build-essential procps curl file git` on Debian/Ubuntu, the development-tools group plus `procps-ng curl file` on Fedora/RHEL, and `base-devel procps-ng curl file git` on Arch. The supported prefix is `/home/linuxbrew/.linuxbrew`. Full Tier 1 additionally means supported Ubuntu (or a Homebrew image), system glibc 2.39+, kernel 3.2+, ARM64/AArch64 or x86_64 with SSSE3, and `sudo` access. ([Homebrew on Linux](https://docs.brew.sh/Homebrew-on-Linux), [support tiers](https://docs.brew.sh/Support-Tiers))
- The official installer is the same `/bin/bash -c "$(curl -fsSL …/install.sh)"` entry point on macOS and Linux; its printed `brew shellenv` step is required to put Homebrew on `PATH`. `install.sh` activates it for its own process, creates guarded per-machine Fish/Zsh activation files when absent, and prints an absolute Fish handoff on Linux so the newly installed environment is immediately reachable without modifying the login shell. ([Homebrew](https://brew.sh/), [post-install step](https://docs.brew.sh/Installation#post-installation-steps))

This makes CLT/Xcode on macOS and distro development tools on Linux the correct home for the initial compiler, `make`, and bootstrap `git`; attempting to provision the compiler through Homebrew is circular on Linux.

## Homebrew-managed applications

“Both” means the linked Homebrew formula currently publishes bottles for macOS (Apple silicon and Intel) and Linux (ARM64 and x86_64).

| Required command/app | Homebrew package | Homebrew availability | Repository role |
| --- | --- | --- | --- |
| `git` | [`git`](https://formulae.brew.sh/formula/git) formula | Both | Required everywhere; a bootstrap/system Git also satisfies the check |
| `fish` | [`fish`](https://formulae.brew.sh/formula/fish) formula | Both | Required primary shell. **Effective floor: 3.2**, because `config.fish` invokes `fish_add_path`, introduced in Fish 3.2.0. The current Homebrew stable (4.8.1) satisfies it. ([Fish 3.2 release notes](https://fishshell.com/docs/3.5/relnotes.html#fish-3-2-0-released-march-1-2021)) |
| `zsh` | [`zsh`](https://formulae.brew.sh/formula/zsh) formula | Both | Required handoff/login shell; a system Zsh satisfies the check |
| `nvim` | [`neovim`](https://formulae.brew.sh/formula/neovim) formula | Both | Required editor; formula name differs from command. **Exact gate: stable Neovim 0.12.4**; [`nvim/init.lua`](../nvim/init.lua) rejects every other version, and the current Homebrew stable is exactly 0.12.4. |
| `herdr` | [`herdr`](https://formulae.brew.sh/formula/herdr) formula | Both | Required daily workspace manager |
| `tmux` | [`tmux`](https://formulae.brew.sh/formula/tmux) formula | Both | Required fallback/compatibility multiplexer. **Effective floor: 3.7**, because the tracked message styles use `fill=`; tmux records that requirement under the 3.6b-to-3.7 changes. The current Homebrew stable (3.7b) satisfies it. ([tmux 3.7 CHANGES](https://raw.githubusercontent.com/tmux/tmux/3.7/CHANGES)) |
| `lazygit` | [`lazygit`](https://formulae.brew.sh/formula/lazygit) formula | Both | Required Git Transaction Surface. **Effective floor: 0.56**, which introduced the configured `git.pagers` interface used to select Hunk as the Diffing Solution. ([LazyGit 0.56 release](https://github.com/jesseduffield/lazygit/releases/tag/v0.56.0)) |
| `mise` | [`mise`](https://formulae.brew.sh/formula/mise) formula | Both | Required runtime manager |
| `atuin` | [`atuin`](https://formulae.brew.sh/formula/atuin) formula | Both | Required shell-history integration |
| `rg` | [`ripgrep`](https://formulae.brew.sh/formula/ripgrep) formula | Both | Required search tool; formula name differs from command |
| `tree-sitter` | [`tree-sitter-cli`](https://formulae.brew.sh/formula/tree-sitter-cli) formula | Both | Required parser-management CLI; formula name differs from command. The current formula supplies `tree-sitter` 0.26.11, satisfying nvim-treesitter main's requirement for 0.26.1 or later. ([nvim-treesitter requirements](https://github.com/nvim-treesitter/nvim-treesitter#requirements)) |
| `hunk` | [`hunk`](https://formulae.brew.sh/formula/hunk) formula | Both | Required Diffing Solution and stacked working-tree Review Surface. **Effective floor: 0.18.1** for concurrent watch sessions: 0.18 replaced the 250 ms Git polling loop with filesystem event hints, an authoritative Git signature, and a 10-second safety check. Hunk's frozen campaign measured 35–36 times fewer Git invocations and 1.8–6.4 times lower idle main-process CPU per session, subject to its stated platform and projection caveats. ([Hunk 0.18.1 release](https://github.com/modem-dev/hunk/releases/tag/v0.18.1), [watch benchmark](https://github.com/modem-dev/hunk/blob/d6e967bf5c5a3a93bb7796aa50e67ee3fec58179/docs/watch-benchmark-final.md#L9-L28)) |
| `xclip` / `wl-copy` | [`xclip`](https://formulae.brew.sh/formula/xclip) / [`wl-clipboard`](https://formulae.brew.sh/formula/wl-clipboard) | Linux (`xclip` also has macOS bottles) | X11 and Wayland clipboard providers installed by the Linux Brewfile |
| `Ghostty.app` or `ghostty` | [`ghostty`](https://formulae.brew.sh/cask/ghostty) cask (`brew install --cask ghostty`) | macOS only | Required only on macOS; the installer explicitly skips its config on Linux |

The installer validates Fish 3.2 or newer, tmux 3.7 or newer, LazyGit 0.56 or
newer, Hunk 0.18.1 or newer, tree-sitter CLI 0.26.1 or newer, and exactly stable
Neovim 0.12.4 after applying the Brewfile.

Ghostty's tracked configuration also selects **JetBrains Mono**. Homebrew maps that presentation dependency to the macOS-only [`font-jetbrains-mono`](https://formulae.brew.sh/cask/font-jetbrains-mono) cask. `install.sh` accepts either its Brew receipt or a matching font file in the standard macOS font directories.

One direct repository workflow is outside `install.sh`: [`docs/agents/issue-tracker.md`](agents/issue-tracker.md) requires the `gh` CLI for all issue operations. Homebrew's [`gh`](https://formulae.brew.sh/formula/gh) formula publishes macOS and Linux bottles.

## Neovim bootstrap, optional, and test-only tools

| Tool | Homebrew package and availability | Classification |
| --- | --- | --- |
| `make` | [`make`](https://formulae.brew.sh/formula/make) formula, both; Homebrew installs GNU Make as `gmake` unless its `gnubin` directory is added to `PATH` | **Optional build enhancement, normally bootstrap-provided.** The config tests for the exact command `make`; when absent it omits Telescope fzf-native and LuaSnip's jsregexp build, while the base config still loads. |
| `unzip` | [`unzip`](https://formulae.brew.sh/formula/unzip) formula, both, but keg-only | **Required Neovim/Mason helper.** Use the platform command or explicitly expose the keg binary; a bare keg-only install does not add an unqualified `unzip` to the normal Homebrew prefix. |
| C compiler/build tools | No single bootstrap formula. [`llvm`](https://formulae.brew.sh/formula/llvm) exists on both platforms but is keg-only and is not a substitute for Homebrew's system-compiler prerequisite. | **Required platform bootstrap:** CLT/Xcode on macOS; distro development-tools package/group on Linux. |
| Mason transport/archive tools | System `curl` **or** GNU `wget`, GNU `tar` (`tar` or `gtar`), and `gzip`. Homebrew offers [`curl`](https://formulae.brew.sh/formula/curl) (both, keg-only), [`wget`](https://formulae.brew.sh/formula/wget) (both), [`gnu-tar`](https://formulae.brew.sh/formula/gnu-tar) (both, installs `gtar`), and [`gzip`](https://formulae.brew.sh/formula/gzip) (both). | **Required Mason bootstrap**, together with the already-listed `git` and `unzip`. Mason explicitly lists these Unix requirements. ([Mason requirements](https://github.com/mason-org/mason.nvim#requirements)) |
| `diff` | Platform `diffutils` package | **Required Undotree helper.** Undotree's enabled diff panel invokes `diff`; the Linux native bootstrap supplies it. |
| `fd` | [`fd`](https://formulae.brew.sh/formula/fd) formula, both | **Optional.** Telescope uses it when present. |
| Clipboard provider | `pbcopy`/`pbpaste` are macOS system tools. Linux Wayland sessions use `wl-copy`/`wl-paste`; [`xclip`](https://formulae.brew.sh/formula/xclip) and [`xsel`](https://formulae.brew.sh/formula/xsel) are the X11 alternatives. | **Platform runtime choice.** macOS needs no package. The Linux Brewfile installs both `wl-clipboard` and `xclip` so Neovim can select the provider appropriate to the active session. ([Neovim clipboard provider](https://github.com/neovim/neovim/blob/master/runtime/doc/provider.txt)) |
| `expect` | [`expect`](https://formulae.brew.sh/formula/expect) formula, both | **Test-only.** The real-PTY Hunk regression harness uses the absolute `/usr/bin/expect`, so the Homebrew binary does not satisfy that harness path without changing the test invocation. |

## Language-capability runtime ownership

The inventory in [`nvim/lua/custom/languages.lua`](../nvim/lua/custom/languages.lua) is passed wholesale to Mason Tool Installer, so Mason attempts to install every listed tool. Mason installs editor tooling, but its own documentation says that it shells out to external package managers such as `npm`; language runtimes remain machine capabilities. In this repository, **mise should own versioned Node, Python, and Rust runtimes plus Amazon Corretto JDK 21**, while Mason owns the LSP/formatter/linter executables. Mise has core backends for all four runtimes and deliberately does not replace system package management. ([Mason requirements](https://github.com/mason-org/mason.nvim#requirements), [mise core tools](https://mise.jdx.dev/core-tools.html), [mise ownership boundary](https://mise.jdx.dev/faq.html#mise-is-for-dev-tools-not-applications-or-system-packages))

The tracked Mise fragment pins Node 24.18.0, Python 3.14.6, Rust 1.97.1,
and Amazon Corretto JDK 21 at `corretto-21.0.12.8.1`. Exact selectors make a
successful second install a stable no-op; advancing a runtime is an explicit
manifest change rather than a side effect of resolving `latest`, `lts`, or a
moving major-version channel.

| Capability | Runtime prerequisite and evidence | Provisioning boundary |
| --- | --- | --- |
| JavaScript/TypeScript and npm-backed tools | `node` plus `npm`; current Mason entries such as [typescript-language-server](https://raw.githubusercontent.com/mason-org/mason-registry/main/packages/typescript-language-server/package.yaml), [Pyright](https://raw.githubusercontent.com/mason-org/mason-registry/main/packages/pyright/package.yaml), and [Prettier](https://raw.githubusercontent.com/mason-org/mason-registry/main/packages/prettier/package.yaml) declare npm sources. | **Capability runtime:** manage Node with mise. Homebrew's [`node`](https://formulae.brew.sh/formula/node) formula is available on both platforms if mise is not used. |
| Rust language tooling and native plugin fallback | `cargo`, `clippy`, and `rustfmt`; the tracked rust-analyzer settings load all Cargo features and use `clippy` for checks, while the language inventory invokes `rustfmt` through Conform. The tracked FFF install hook calls `download_or_build_binary()`, whose upstream contract downloads a prebuilt binary or falls back to a Cargo build. ([FFF installation](https://github.com/dmtrKovalenko/fff#installation)) | **Capability runtime/build fallback:** manage Rust with mise. The tracked minimal rustup profile explicitly adds both the `clippy` and `rustfmt` components. ([mise Rust backend](https://mise.jdx.dev/lang/rust.html), [rustup components](https://rust-lang.github.io/rustup/concepts/components.html)) |
| Python tooling | A Python/pip-capable runtime; Mason's [Ruff](https://raw.githubusercontent.com/mason-org/mason-registry/main/packages/ruff/package.yaml) entry is PyPI-backed, and the [JDTLS launcher](https://github.com/eclipse-jdtls/eclipse.jdt.ls#running-from-command-line-with-wrapper-script) also requires Python 3.9+. | **Capability runtime:** manage Python with mise. Homebrew's [`python`](https://formulae.brew.sh/formula/python@3.14) formula is available on both platforms. |
| Python debugging | `uv` is invoked directly by [`debug.lua`](../nvim/lua/kickstart/plugins/debug.lua), which runs debugpy through nvim-dap-python. | **Feature-specific CLI:** required only for Python DAP. [Mise can install `uv`](https://mise.jdx.dev/mise-cookbook/python.html#uv-scripts); Homebrew's [`uv`](https://formulae.brew.sh/formula/uv) formula has bottles on both platforms and matches this repository's brew-first application policy. |
| Java and Kotlin | JDTLS itself requires Java 21 or newer; Java/Kotlin projects also need their selected JDK even though Mason downloads [JDTLS](https://raw.githubusercontent.com/mason-org/mason-registry/main/packages/jdtls/package.yaml), [Kotlin LSP](https://raw.githubusercontent.com/mason-org/mason-registry/main/packages/kotlin-lsp/package.yaml), and [ktlint](https://raw.githubusercontent.com/mason-org/mason-registry/main/packages/ktlint/package.yaml). ([JDTLS requirements](https://github.com/eclipse-jdtls/eclipse.jdt.ls#requirements)) | **Capability runtime:** manage Amazon Corretto JDK 21 with mise; the tracked selector is `corretto-21.0.12.8.1`. Homebrew's [`openjdk@21`](https://formulae.brew.sh/formula/openjdk@21) is available on both platforms if mise is not used. |
| Haskell | Mason's [haskell-language-server](https://github.com/mason-org/mason-registry/blob/main/packages/haskell-language-server/package.yaml) installer directly invokes `ghcup`. | **Capability installer/runtime:** put `ghcup` on `PATH` before Mason installs HLS; Homebrew's [`ghcup`](https://formulae.brew.sh/formula/ghcup) formula has bottles on both platforms. [GHCup](https://www.haskell.org/ghcup/) remains the owner of GHC/project tools. |

## Installation-set implication

The full Homebrew-managed application set implied by the current configuration
and its brew-first policy is:

```text
git fish zsh neovim herdr tmux lazygit hunk mise atuin gh ripgrep
tree-sitter-cli uv ghcup
```

Bootstrap/system Git and Zsh can make the first run possible before their
formulae are installed. On Linux, the Brewfile additionally installs `xclip`
and `wl-clipboard`. `ghcup` is capability-specific but is currently needed
for Mason's unconditional HLS installation; it can leave the default set only
if that Haskell capability stops being unconditional. Add the `ghostty` and
`font-jetbrains-mono` casks only on macOS. Keep compiler/build tools outside
the Homebrew set at the platform-bootstrap layer, and do not add `fd` solely
for an unused alternate finder path. Provision language runtimes through Mise
before Mason's first full inventory install; treat clipboard provisioning as
OS-specific and Expect as a development-test dependency.

The Brewfile is applied with `brew bundle check --no-upgrade` followed, only
when needed, by `brew bundle install --no-upgrade`. This avoids requesting a
general upgrade pass, but Homebrew may still upgrade dependencies required to
install a newly missing formula; the installer documentation should preserve
that distinction.
