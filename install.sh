#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
BREWFILE="$REPO_ROOT/Brewfile"
MISE_BOOTSTRAP_CONFIG_DIR="$REPO_ROOT/mise"
MISE_MANIFEST="$MISE_BOOTSTRAP_CONFIG_DIR/conf.d/00-dotfiles.toml"
HOMEBREW_INSTALL_URL="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
BREW_BIN=""
LINUX_PACKAGE_MANAGER=""
LINUX_FISH_PATH=""
SKIP_MISE_RUNTIMES=0

usage() {
    printf 'Usage: %s [--skip-mise-runtimes]\n' "${0##*/}"
    printf '       %s --help\n' "${0##*/}"
}

case "$#" in
    0)
        ;;
    1)
        case "$1" in
            --skip-mise-runtimes)
                SKIP_MISE_RUNTIMES=1
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                usage >&2
                exit 2
                ;;
        esac
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac

OS_NAME="$(uname -s)"

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

section() {
    printf '\n==> %s\n' "$1"
}

case "$OS_NAME" in
    Darwin|Linux)
        ;;
    *)
        die "unsupported operating system '$OS_NAME'; this installer supports macOS and Linux"
        ;;
esac

[[ -n "${HOME:-}" ]] || die "HOME is not set"
[[ "$HOME" == /* && -d "$HOME" ]] ||
    die "HOME must be an absolute user directory"
HOME_DIRECTORY="$(cd -P -- "$HOME" 2>/dev/null && pwd -P)" ||
    die "HOME must be an accessible user directory"
[[ "$HOME_DIRECTORY" != "/" ]] ||
    die "HOME must not resolve to the filesystem root"
(( EUID != 0 )) || die "do not run this installer as root; run it as the user whose dotfiles are being installed"
LOCAL_DIR="$HOME/.local/share/dotfiles"
# Harness roots are configurable; never silently install instructions to an
# unused default location. Reject ambiguous paths before touching user files.
normalize_agent_directory() {
    local directory="$1"
    while [[ "$directory" == *//* ]]; do
        directory="${directory//\/\///}"
    done
    while [[ "$directory" == */ && "$directory" != / ]]; do
        directory="${directory%/}"
    done
    printf '%s' "$directory"
}
CODEX_DIRECTORY="$(normalize_agent_directory "${CODEX_HOME-$HOME/.codex}")"
PI_DIRECTORY="$(normalize_agent_directory "${PI_CODING_AGENT_DIR-$HOME/.pi/agent}")"
WORKFLOW_HOME="$(normalize_agent_directory "$HOME")"

# Resolve existing directory ancestors, including HOME aliases, without needing
# the final path to exist. Call with the parent when a symlink itself is replaced.
physical_path() {
    local directory="$1" suffix=""
    while [[ ! -d "$directory" ]]; do
        suffix="/${directory##*/}$suffix"
        directory="$(dirname "$directory")"
    done
    directory="$(cd -P -- "$directory" && pwd -P)"
    directory="${directory%/}$suffix"
    printf '%s' "${directory:-/}"
}

# HOME's own ancestry was validated above. Preserve redirects below it and
# at custom locations; do not follow them to another profile's instructions.
redirected_agent_parent() {
    local directory="$1"
    while [[ "$directory" != / ]]; do
        if [[ -L "$directory" ]]; then
            case "$WORKFLOW_HOME/" in
                "$directory/"*) ;;
                *) printf '%s' "$directory"; return ;;
            esac
        fi
        directory="$(dirname "$directory")"
    done
}

validate_agent_directory() {
    local directory="$1" setting="$2" ancestor
    [[ "$directory" == /* && "$directory" != / ]] ||
        die "$setting must name an absolute directory other than /"
    case "$directory/" in
        */./*|*/../*)
            die "$setting must not contain . or .. path components"
            ;;
    esac
    ancestor="$directory"
    while [[ "$ancestor" != / ]]; do
        if [[ ( -e "$ancestor" || -L "$ancestor" ) && ! -d "$ancestor" ]]; then
            die "'$ancestor' blocks required configuration directory"
        fi
        ancestor="$(dirname "$ancestor")"
    done
    if [[ -d "$directory" && "$(cd -P -- "$directory" && pwd -P)" == / ]]; then
        die "$setting must not resolve to the filesystem root"
    fi
}

preflight_workflow_links() {
    local directory target line redirected protected physical_directory physical_target
    local managed_targets=(
        .config/fish .config/ghostty .config/herdr/config.toml
        .config/hunk/config.toml .config/lazygit .config/mise/conf.d/00-dotfiles.toml
        .config/nvim .config/tmux .zshrc
        .local/share/dotfiles/local.fish .local/share/dotfiles/local.zsh
        .claude/rules/development-workflow.md
    )
    validate_agent_directory "$CODEX_DIRECTORY" CODEX_HOME
    validate_agent_directory "$PI_DIRECTORY" PI_CODING_AGENT_DIR
    # Never place a harness root inside a link that installation will create.
    for directory in "$CODEX_DIRECTORY" "$PI_DIRECTORY"; do
        physical_directory="$(physical_path "$directory")"
        for target in "${managed_targets[@]}"; do
            physical_target="$(physical_path "$(dirname "$HOME/$target")")/${target##*/}"
            case "$physical_directory/" in
                "$physical_target/"*)
                    die "agent configuration directory overlaps a managed link: $directory ($WORKFLOW_HOME/$target)"
                    ;;
            esac
        done
        for protected in "$CODEX_DIRECTORY/AGENTS.md" "$PI_DIRECTORY/AGENTS.md"; do
            physical_target="$(physical_path "$(dirname "$protected")")/${protected##*/}"
            case "$physical_directory/" in
                "$physical_target/"*) die "agent configuration directories overlap an instruction file: $directory" ;;
            esac
        done
    done
    # These containers can hold unrelated agent state and are never replaced.
    for directory in "$CODEX_DIRECTORY" "$PI_DIRECTORY" "$WORKFLOW_HOME/.claude/rules"; do
        validate_agent_directory "$directory" "agent configuration directory"
        redirected="$(redirected_agent_parent "$directory")"
        [[ -z "$redirected" ]] ||
            die "agent configuration directory is a symlink; preserve it and reconcile the workflow link explicitly: $redirected"
    done
    for target in "$CODEX_DIRECTORY/AGENTS.md" "$PI_DIRECTORY/AGENTS.md" \
        "$HOME/.claude/rules/development-workflow.md"
    do
        if [[ -e "$target" || -L "$target" ]] &&
            ! symlink_points_to "$target" "$REPO_ROOT/docs/agents/development-workflow.md"
        then
            die "existing global instructions must remain active; reconcile their content with the shared workflow before linking: $target"
        fi
    done
    if [[ -e "$CODEX_DIRECTORY/AGENTS.override.md" ||
        -L "$CODEX_DIRECTORY/AGENTS.override.md" ]]
    then
        die "Codex AGENTS.override.md shadows the shared workflow; reconcile it explicitly before installing: $CODEX_DIRECTORY/AGENTS.override.md"
    fi
    if [[ -f "$HOME/.claude/CLAUDE.md" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            case "$line" in
                *'<!-- dotfiles-devflow:begin'*)
                    die "retire the legacy dotfiles-devflow block in $HOME/.claude/CLAUDE.md while preserving unrelated guidance before installing"
                    ;;
            esac
        done <"$HOME/.claude/CLAUDE.md"
    fi
}

ensure_sudo() {
    command -v sudo >/dev/null 2>&1 || die "sudo is required to install system prerequisites and Homebrew"
    sudo -v || die "sudo authentication failed; retry in a terminal or configure passwordless sudo for headless use"
}

has_linux_clipboard() {
    command -v wl-copy >/dev/null 2>&1 ||
        command -v xclip >/dev/null 2>&1 ||
        command -v xsel >/dev/null 2>&1
}

collect_native_missing() {
    local command_name
    NATIVE_MISSING=()

    for command_name in cc c++ make ps curl file git tar gzip unzip diff; do
        command -v "$command_name" >/dev/null 2>&1 || NATIVE_MISSING+=("$command_name")
    done
}

validate_native_compilers() {
    if ! printf '#include <stdio.h>\nint main(void) { return puts("dotfiles"); }\n' |
        cc -x c -o /dev/null -
    then
        die "the C compiler cannot compile and link a program; repair the platform development tools and SDK, then rerun"
    fi
    if ! printf '#include <iostream>\nint main() { std::cout << "dotfiles"; }\n' |
        c++ -x c++ -o /dev/null -
    then
        die "the C++ compiler cannot compile and link the standard library; repair the platform development tools and SDK, then rerun"
    fi
}

detect_linux_package_manager() {
    if command -v apt-get >/dev/null 2>&1; then
        LINUX_PACKAGE_MANAGER="apt-get"
    elif command -v dnf >/dev/null 2>&1; then
        LINUX_PACKAGE_MANAGER="dnf"
    elif command -v yum >/dev/null 2>&1; then
        LINUX_PACKAGE_MANAGER="yum"
    elif command -v pacman >/dev/null 2>&1; then
        LINUX_PACKAGE_MANAGER="pacman"
    else
        die "unsupported Linux package manager; this installer supports apt-get, dnf, yum, and pacman"
    fi
}

install_linux_native_packages() {
    ensure_sudo
    section "Installing Linux system prerequisites"

    case "$LINUX_PACKAGE_MANAGER" in
        apt-get)
            sudo apt-get update
            sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y \
                build-essential procps curl file git tar gzip unzip diffutils \
                ca-certificates
            ;;
        dnf)
            if ! sudo dnf group install -y development-tools; then
                sudo dnf group install -y "Development Tools"
            fi
            sudo dnf install -y \
                gcc-c++ procps-ng curl file git tar gzip unzip diffutils ca-certificates
            ;;
        yum)
            sudo yum groupinstall -y "Development Tools"
            sudo yum install -y \
                gcc-c++ procps-ng curl file git tar gzip unzip diffutils ca-certificates
            ;;
        pacman)
            sudo pacman -S --needed --noconfirm \
                base-devel procps-ng curl file git tar gzip unzip diffutils \
                ca-certificates
            ;;
        *)
            die "internal error: Linux package manager was not detected"
            ;;
    esac
}

ensure_native_prerequisites() {
    if [[ "$OS_NAME" == "Darwin" ]]; then
        if ! command -v xcode-select >/dev/null 2>&1 || ! xcode-select -p >/dev/null 2>&1; then
            if command -v xcode-select >/dev/null 2>&1; then
                xcode-select --install >/dev/null 2>&1 || true
            fi
            die "Xcode Command Line Tools installation was requested; finish it, then rerun this installer"
        fi

        collect_native_missing
        if (( ${#NATIVE_MISSING[@]} > 0 )); then
            die "Xcode Command Line Tools are incomplete; missing: ${NATIVE_MISSING[*]}"
        fi
        validate_native_compilers
        return 0
    fi

    detect_linux_package_manager
    collect_native_missing
    if (( ${#NATIVE_MISSING[@]} > 0 )); then
        printf 'Missing Linux system prerequisites: %s\n' "${NATIVE_MISSING[*]}"
        install_linux_native_packages
        collect_native_missing
    fi

    if (( ${#NATIVE_MISSING[@]} > 0 )); then
        die "system prerequisite installation completed but these capabilities are still missing: ${NATIVE_MISSING[*]}"
    fi
    validate_native_compilers
}

brew_works() {
    [[ -n "$1" && -x "$1" ]] && "$1" --version >/dev/null 2>&1
}

find_brew() {
    local candidate candidates old_ifs

    candidate="$(command -v brew 2>/dev/null || true)"
    if brew_works "$candidate"; then
        BREW_BIN="$candidate"
        return 0
    fi

    if [[ -n "${DOTFILES_BREW_PATHS:-}" ]]; then
        candidates="$DOTFILES_BREW_PATHS"
    elif [[ "$OS_NAME" == "Linux" ]]; then
        candidates="/home/linuxbrew/.linuxbrew/bin/brew:/opt/homebrew/bin/brew:/usr/local/bin/brew"
    elif [[ "$(uname -m)" == "arm64" ]]; then
        candidates="/opt/homebrew/bin/brew:/usr/local/bin/brew"
    else
        candidates="/usr/local/bin/brew:/opt/homebrew/bin/brew"
    fi

    old_ifs="$IFS"
    IFS=:
    for candidate in $candidates; do
        if brew_works "$candidate"; then
            BREW_BIN="$candidate"
            IFS="$old_ifs"
            return 0
        fi
    done
    IFS="$old_ifs"
    return 1
}

activate_brew() {
    local shell_environment
    shell_environment="$("$BREW_BIN" shellenv)" ||
        die "Homebrew was found at '$BREW_BIN' but 'brew shellenv' failed"
    eval "$shell_environment"
    hash -r
}

ensure_homebrew() {
    local installer

    if find_brew; then
        activate_brew
        return 0
    fi

    ensure_sudo
    section "Installing Homebrew"
    if ! installer="$(curl -fsSL "$HOMEBREW_INSTALL_URL")"; then
        die "failed to download the official Homebrew installer"
    fi
    [[ -n "$installer" ]] || die "the downloaded Homebrew installer was empty"

    NONINTERACTIVE=1 /bin/bash -c "$installer"
    find_brew || die "Homebrew installation finished but brew was not found in a supported prefix"
    activate_brew
}

install_brew_dependencies() {
    section "Installing Homebrew applications"
    if "$BREW_BIN" bundle check --no-upgrade --file="$BREWFILE"; then
        echo "Homebrew applications are already installed."
    else
        "$BREW_BIN" bundle install --no-upgrade --file="$BREWFILE"
    fi
}

path_list_has_directory() {
    local directory_list="$1" child="$2" candidate old_ifs
    old_ifs="$IFS"
    IFS=:
    for candidate in $directory_list; do
        if [[ -d "$candidate/$child" ]]; then
            IFS="$old_ifs"
            return 0
        fi
    done
    IFS="$old_ifs"
    return 1
}

has_ghostty() {
    local application_dirs
    command -v ghostty >/dev/null 2>&1 && return 0
    application_dirs="${DOTFILES_APPLICATION_DIRS:-/Applications:$HOME/Applications}"
    path_list_has_directory "$application_dirs" "Ghostty.app"
}

has_jetbrains_mono_file() {
    local font_dirs candidate font old_ifs
    font_dirs="${DOTFILES_FONT_DIRS:-/Library/Fonts:$HOME/Library/Fonts}"
    old_ifs="$IFS"
    IFS=:
    for candidate in $font_dirs; do
        for font in "$candidate"/JetBrainsMono*; do
            if [[ -f "$font" ]]; then
                IFS="$old_ifs"
                return 0
            fi
        done
    done
    IFS="$old_ifs"
    return 1
}

brew_cask_installed() {
    "$BREW_BIN" list --cask --versions "$1" >/dev/null 2>&1
}

install_macos_casks() {
    if [[ "$OS_NAME" != "Darwin" ]]; then
        return 0
    fi

    section "Installing macOS applications"
    if ! has_ghostty; then
        if brew_cask_installed ghostty; then
            die "Homebrew records the Ghostty cask, but Ghostty.app is missing; repair the cask and rerun"
        fi
        "$BREW_BIN" install --cask ghostty
    fi
    has_ghostty || die "Ghostty installation completed but Ghostty.app could not be found"

    if ! has_jetbrains_mono_file; then
        if brew_cask_installed font-jetbrains-mono; then
            die "Homebrew records the JetBrains Mono cask, but its font files are missing; repair the cask and rerun"
        fi
        "$BREW_BIN" install --cask font-jetbrains-mono
    fi
    has_jetbrains_mono_file ||
        die "JetBrains Mono installation completed but the font could not be found"
}

numeric_prefix() {
    local value="$1"
    value="${value%%[!0-9]*}"
    [[ -n "$value" ]] || value=0
    while [[ ${#value} -gt 1 && "${value:0:1}" == "0" ]]; do
        value="${value#0}"
    done
    NUMERIC_PREFIX="$value"
}

version_at_least() {
    local actual_rest="$1" minimum_rest="$2"
    local actual_component minimum_component index

    for ((index = 0; index < 3; index++)); do
        actual_component="${actual_rest%%.*}"
        minimum_component="${minimum_rest%%.*}"

        if [[ "$actual_rest" == *.* ]]; then
            actual_rest="${actual_rest#*.}"
        else
            actual_rest=""
        fi
        if [[ "$minimum_rest" == *.* ]]; then
            minimum_rest="${minimum_rest#*.}"
        else
            minimum_rest=""
        fi

        numeric_prefix "$actual_component"
        actual_component="$NUMERIC_PREFIX"
        numeric_prefix "$minimum_component"
        minimum_component="$NUMERIC_PREFIX"

        if (( actual_component > minimum_component )); then
            return 0
        fi
        if (( actual_component < minimum_component )); then
            return 1
        fi
    done
    return 0
}

validate_brew_dependencies() {
    local command_name output version
    local missing errors
    missing=()
    errors=()

    for command_name in \
        git fish zsh nvim herdr tmux lazygit hunk mise atuin gh rg \
        tree-sitter cmake ctest ninja uv
    do
        command -v "$command_name" >/dev/null 2>&1 || missing+=("$command_name")
    done
    if [[ "$OS_NAME" == "Linux" ]] && ! has_linux_clipboard; then
        missing+=("Linux clipboard provider")
    fi

    if (( ${#missing[@]} > 0 )); then
        die "Homebrew finished but required commands are not on PATH: ${missing[*]}"
    fi

    output="$(fish --version 2>/dev/null || true)"
    version="${output##* }"
    version_at_least "$version" "3.2.0" ||
        errors+=("Fish 3.2+ is required (found '${version:-unknown}')")

    output="$(tmux -V 2>/dev/null || true)"
    version="${output##* }"
    version_at_least "$version" "3.5.0" ||
        errors+=("tmux 3.5+ is required for extended-keys-format (found '${version:-unknown}')")

    output="$(lazygit --version 2>/dev/null || true)"
    version="${output#*version=}"
    version="${version%%,*}"
    version_at_least "$version" "0.64.0" ||
        errors+=("LazyGit 0.64+ is required for git.diffRenderers (found '${version:-unknown}')")

    output="$(hunk --version 2>/dev/null || true)"
    version="${output##* }"
    version_at_least "$version" "0.18.1" ||
        errors+=("Hunk 0.18.1+ is required (found '${version:-unknown}')")

    output="$(tree-sitter --version 2>/dev/null || true)"
    version="${output##* }"
    version_at_least "$version" "0.26.1" ||
        errors+=("tree-sitter CLI 0.26.1+ is required (found '${version:-unknown}')")

    if ! output="$(
        DOTFILES_NVIM_CHECK="$REPO_ROOT/nvim/lua/custom/lib/neovim.lua" \
            NVIM_LOG_FILE=/dev/null nvim --clean --headless -c 'lua
                local loaded, supported, message = pcall(function()
                    return dofile(vim.env.DOTFILES_NVIM_CHECK).check()
                end)
                if not loaded or not supported then
                    io.stderr:write(tostring(loaded and message or supported), "\n")
                    vim.cmd("cquit 1")
                end
            ' -c qa 2>&1
    )"; then
        errors+=("Neovim compatibility check failed: $output")
    fi

    if (( ${#errors[@]} > 0 )); then
        printf 'Installed application versions do not satisfy this configuration:\n' >&2
        printf '  %s\n' "${errors[@]}" >&2
        exit 1
    fi
}

install_mise_runtimes() (
    local active_version command_name command_path expected_version
    local environment config_sources
    local manifest_key mise_command_path output tool_name version
    local mismatched missing version_mismatches

    section "Installing Mise runtimes"
    cd -- "$REPO_ROOT"
    export MISE_CONFIG_DIR="$MISE_BOOTSTRAP_CONFIG_DIR"
    export MISE_SYSTEM_CONFIG_DIR="$MISE_BOOTSTRAP_CONFIG_DIR"
    export MISE_CEILING_PATHS="$REPO_ROOT"
    unset \
        MISE_CONFIG_FILE \
        MISE_GLOBAL_CONFIG_FILE \
        MISE_GLOBAL_CONFIG_ROOT \
        MISE_IGNORED_CONFIG_PATHS \
        MISE_NO_CONFIG \
        MISE_DISABLE_TOOLS \
        MISE_ENV \
        MISE_ENV_FILE \
        MISE_NODE_VERSION \
        MISE_PYTHON_VERSION \
        MISE_RUST_VERSION \
        MISE_JAVA_VERSION

    # Bound both global/system and project discovery, then verify the effective
    # source set before Mise can install tools or evaluate a foreign environment.
    config_sources="$(mise config ls --json)" || die "Mise configuration discovery failed"
    if ! DOTFILES_MISE_SOURCES="$config_sources" DOTFILES_MISE_MANIFEST="$MISE_MANIFEST" \
        NVIM_LOG_FILE=/dev/null nvim --clean --headless -i NONE -c 'lua
            local ok, sources = pcall(vim.json.decode, vim.env.DOTFILES_MISE_SOURCES)
            if not ok or type(sources) ~= "table" or #sources ~= 1 or type(sources[1]) ~= "table"
                or sources[1].path ~= vim.env.DOTFILES_MISE_MANIFEST then
                io.stderr:write("Mise must load only the tracked runtime manifest\n")
                vim.cmd("cquit 1")
            end
        ' -c qa
    then
        die "unexpected Mise configuration; inspect mise config ls before retrying"
    fi

    if mise install --dry-run-code >/dev/null 2>&1; then
        echo "Mise runtimes are already installed."
    else
        mise install --yes
    fi

    environment="$(mise env --shell bash)" ||
        die "Mise runtimes installed but environment resolution failed"
    eval "$environment"
    hash -r

    missing=()
    mismatched=()
    for command_name in node npm python rustc cargo rustfmt java javac; do
        command_path="$(command -v "$command_name" 2>/dev/null || true)"
        if [[ -z "$command_path" ]]; then
            missing+=("$command_name")
            continue
        fi

        mise_command_path="$(mise which "$command_name" 2>/dev/null || true)"
        if [[ -z "$mise_command_path" || "$command_path" != "$mise_command_path" ]]; then
            mismatched+=("$command_name")
        fi
    done
    if (( ${#missing[@]} > 0 )); then
        die "Mise finished but required runtime commands are not on PATH: ${missing[*]}"
    fi
    if (( ${#mismatched[@]} > 0 )); then
        die "Mise activation did not select configured runtime commands: ${mismatched[*]}"
    fi

    version_mismatches=()
    for tool_name in node python rust java; do
        if [[ "$tool_name" == "rust" ]]; then
            manifest_key="tools.core:rust.version"
        else
            manifest_key="tools.core:$tool_name"
        fi
        expected_version="$(mise config get -f "$MISE_MANIFEST" "$manifest_key")" ||
            die "Mise could not read '$manifest_key' from the tracked manifest"
        active_version="$(mise current "$tool_name" 2>/dev/null || true)"
        if [[ "$active_version" != "$expected_version" ]]; then
            version_mismatches+=(
                "$tool_name=$active_version (expected $expected_version)"
            )
        fi
    done
    if (( ${#version_mismatches[@]} > 0 )); then
        die "Mise runtime versions do not match the tracked manifest: ${version_mismatches[*]}"
    fi

    cargo clippy --version >/dev/null 2>&1 ||
        die "Mise's Rust toolchain is missing the configured Clippy component"
    rust_sysroot="$(rustc --print sysroot 2>/dev/null || true)"
    [[ -n "$rust_sysroot" && -d "$rust_sysroot/lib/rustlib/src/rust/library" ]] ||
        die "Mise's Rust toolchain is missing the configured rust-src component"

    output="$(java -version 2>&1)" || die "Mise's Java runtime is not runnable"
    version="${output#*\"}"
    version="${version%%\"*}"
    version_at_least "$version" "21.0.0" ||
        die "Java runtime 21+ is required (found '${version:-unknown}')"

    output="$(javac -version 2>&1 || true)"
    version="${output##* }"
    version_at_least "$version" "21.0.0" ||
        die "JDK 21+ is required (found '${version:-unknown}')"
)

backup_existing() {
    local target="$1" timestamp backup
    if [[ -e "$target" || -L "$target" ]]; then
        timestamp="$(date +%s)"
        backup="${target}.bak.${timestamp}"
        while [[ -e "$backup" || -L "$backup" ]]; do
            timestamp=$((timestamp + 1))
            backup="${target}.bak.${timestamp}"
        done
        mv "$target" "$backup"
        echo "  backed up:      $target"
    fi
}

symlink_points_to() {
    [[ -L "$1" && "$1" -ef "$2" ]]
}

link() {
    local src="$REPO_ROOT/$1" dst="$2"
    [[ "$dst" == /* ]] || dst="$HOME/$dst"
    if symlink_points_to "$dst" "$src"; then
        return 0
    fi
    mkdir -p "$(dirname "$dst")"
    backup_existing "$dst"
    ln -s "$src" "$dst"
    echo "  linked:         $dst"
}

prepare_local_config_dir() {
    local target="$1"
    if [[ ! -d "$target" || -L "$target" ]]; then
        backup_existing "$target"
        mkdir -p "$target"
    fi
}

link_nested() {
    local source_rel="$1" target_rel="$2" container_rel="$3"

    if symlink_points_to "$HOME/$target_rel" "$REPO_ROOT/$source_rel"; then
        return 0
    fi
    prepare_local_config_dir "$HOME/$container_rel"
    link "$source_rel" "$target_rel"
}

preflight_link_location() {
    local source="$REPO_ROOT/$1" target="$2" container="${3:-}" location entry
    [[ "$target" == /* ]] || target="$HOME/$target"
    symlink_points_to "$target" "$source" && return 0
    for entry in "$target" ${container:+"$HOME/$container"}; do
        # Replacing a symlink does not move its referent. Resolve its parent,
        # not the entry itself, when comparing the paths that will be moved.
        entry="$(physical_path "$(dirname "$entry")")/${entry##*/}"
        for location in "$REPO_ROOT" "$(physical_path "$source")"; do
            case "$location/" in
                "$entry/"*) die "checkout or configuration source overlaps an installation target: $entry; move the checkout outside managed paths" ;;
            esac
        done
    done
}

preflight_links() {
    local source required_directory
    local directory_sources file_sources required_directories

    directory_sources=(
        fish
        lazygit
        nvim
        tmux
    )
    if [[ "$OS_NAME" == "Darwin" ]]; then
        directory_sources+=("ghostty")
    fi

    file_sources=(
        Brewfile
        docs/agents/development-workflow.md
        herdr/config.toml
        hunk/config.toml
        mise/conf.d/00-dotfiles.toml
        nvim/lua/custom/lib/neovim.lua
        zsh/.zshrc
        templates/local.fish
        templates/local.zsh
    )

    for source in "${directory_sources[@]}"; do
        [[ -d "$REPO_ROOT/$source" ]] ||
            die "missing or invalid tracked configuration directory: $REPO_ROOT/$source"
    done
    for source in "${file_sources[@]}"; do
        [[ -f "$REPO_ROOT/$source" ]] ||
            die "missing or invalid tracked configuration file: $REPO_ROOT/$source"
    done

    for source in "${directory_sources[@]}"; do
        preflight_link_location "$source" ".config/$source"
    done
    preflight_link_location herdr/config.toml .config/herdr/config.toml .config/herdr
    preflight_link_location hunk/config.toml .config/hunk/config.toml .config/hunk
    if (( SKIP_MISE_RUNTIMES == 0 )); then
        preflight_link_location mise/conf.d/00-dotfiles.toml .config/mise/conf.d/00-dotfiles.toml .config/mise/conf.d
    fi
    preflight_link_location zsh/.zshrc .zshrc

    required_directories=(
        "$HOME/.config"
        "$HOME/.local"
        "$HOME/.local/share"
        "$LOCAL_DIR"
    )
    if (( SKIP_MISE_RUNTIMES == 0 )); then
        required_directories+=(
            "$HOME/.config/mise"
        )
    fi

    for required_directory in "${required_directories[@]}"; do
        if [[ ( -e "$required_directory" || -L "$required_directory" ) &&
            ! -d "$required_directory" ]]
        then
            die "'$required_directory' blocks required configuration directory"
        fi
    done

    preflight_workflow_links
}

initialize_local_template() (
    local template="$1" target="$LOCAL_DIR/$1" staging
    [[ ! -e "$target" && ! -L "$target" ]] || return 0
    staging="$(mktemp -d "$LOCAL_DIR/.template.XXXXXX")"
    # Only this invocation's private staging file is removed. User destinations
    # are never overwritten, including a file created concurrently with copying.
    trap '[[ ! -f "$staging/$template" ]] || unlink "$staging/$template"; rmdir "$staging"' EXIT
    trap 'exit 1' HUP INT TERM
    cp "$REPO_ROOT/templates/$template" "$staging/$template"
    if ! ln "$staging/$template" "$LOCAL_DIR/" 2>/dev/null; then
        [[ -e "$target" || -L "$target" ]] || die "could not initialize local template: $target"
    fi
)

link_configs() {
    section "Linking configuration"
    link fish        .config/fish
    if [[ "$OS_NAME" == "Darwin" ]]; then
        link ghostty     .config/ghostty
    else
        echo "  skipped:        $HOME/.config/ghostty (macOS-only)"
    fi
    link_nested herdr/config.toml .config/herdr/config.toml .config/herdr
    link_nested hunk/config.toml .config/hunk/config.toml .config/hunk
    link lazygit     .config/lazygit
    if (( SKIP_MISE_RUNTIMES == 0 )); then
        link_nested \
            mise/conf.d/00-dotfiles.toml \
            .config/mise/conf.d/00-dotfiles.toml \
            .config/mise/conf.d
    else
        echo "  skipped:        $HOME/.config/mise/conf.d/00-dotfiles.toml (--skip-mise-runtimes)"
    fi
    link nvim        .config/nvim
    link tmux        .config/tmux
    link zsh/.zshrc  .zshrc
    preflight_workflow_links
    link docs/agents/development-workflow.md "$CODEX_DIRECTORY/AGENTS.md"
    link docs/agents/development-workflow.md "$PI_DIRECTORY/AGENTS.md"
    link docs/agents/development-workflow.md "$HOME/.claude/rules/development-workflow.md"

    mkdir -p "$LOCAL_DIR"
    for template in local.fish local.zsh; do
        initialize_local_template "$template"
    done
}

resolve_linux_fish_path() {
    local brew_prefix

    if [[ "$OS_NAME" != "Linux" ]]; then
        return 0
    fi

    brew_prefix="$("$BREW_BIN" --prefix)" ||
        die "Homebrew is installed, but its prefix could not be determined"
    LINUX_FISH_PATH="$brew_prefix/bin/fish"
    [[ -x "$LINUX_FISH_PATH" ]] ||
        die "Fish is installed, but its executable was not found at '$LINUX_FISH_PATH'"
}

print_next_steps() {
    [[ "$OS_NAME" == "Linux" ]] || return 0
    printf '\nLinux setup is complete. Enter the configured Fish environment with:\n'
    printf '  exec "%s" -l\n' "$LINUX_FISH_PATH"
}

preflight_links
ensure_native_prerequisites
ensure_homebrew
install_brew_dependencies
install_macos_casks
validate_brew_dependencies
resolve_linux_fish_path
if (( SKIP_MISE_RUNTIMES == 1 )); then
    section "Installing Mise runtimes"
    echo "Mise runtime installation and validation skipped by request."
else
    install_mise_runtimes
fi
link_configs
print_next_steps

if (( SKIP_MISE_RUNTIMES == 1 )); then
    printf '\nDotfiles installation complete with Mise runtime provisioning skipped.\n'
else
    printf '\nDotfiles installation complete.\n'
fi
