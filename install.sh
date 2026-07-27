#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BREWFILE="$REPO_ROOT/Brewfile"
MISE_MANIFEST="$REPO_ROOT/mise/conf.d/00-dotfiles.toml"
HOMEBREW_INSTALL_URL="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
OS_NAME="$(uname -s)"
BREW_BIN=""
LINUX_PACKAGE_MANAGER=""
LINUX_FISH_PATH=""

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

    for command_name in cc make ps curl file git tar gzip unzip diff; do
        command -v "$command_name" >/dev/null 2>&1 || NATIVE_MISSING+=("$command_name")
    done
}

detect_linux_package_manager() {
    if command -v apt-get >/dev/null 2>&1; then
        LINUX_PACKAGE_MANAGER="apt-get"
    elif command -v dnf >/dev/null 2>&1; then
        LINUX_PACKAGE_MANAGER="dnf"
    elif command -v pacman >/dev/null 2>&1; then
        LINUX_PACKAGE_MANAGER="pacman"
    else
        die "unsupported Linux package manager; this installer supports apt-get, dnf, and pacman"
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
                procps-ng curl file git tar gzip unzip diffutils ca-certificates
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
            if [[ -e "$font" || -L "$font" ]]; then
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

    for index in 1 2 3; do
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
        tree-sitter uv ghcup
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
    version_at_least "$version" "3.7.0" ||
        errors+=("tmux 3.7+ is required (found '${version:-unknown}')")

    output="$(tree-sitter --version 2>/dev/null || true)"
    version="${output##* }"
    version_at_least "$version" "0.26.1" ||
        errors+=("tree-sitter CLI 0.26.1+ is required (found '${version:-unknown}')")

    output="$(nvim --version 2>/dev/null || true)"
    output="${output%%$'\n'*}"
    if [[ "$output" != "NVIM v0.12.4" ]]; then
        errors+=("stable Neovim 0.12.4 is required (found '${output:-unknown}')")
    fi

    if (( ${#errors[@]} > 0 )); then
        printf 'Installed application versions do not satisfy this configuration:\n' >&2
        printf '  %s\n' "${errors[@]}" >&2
        exit 1
    fi
}

install_mise_runtimes() {
    local activation previous_global_config had_global_config original_working_directory
    local command_name output version
    local missing

    section "Installing Mise runtimes"
    original_working_directory="$PWD"
    cd -- "$REPO_ROOT"

    if MISE_GLOBAL_CONFIG_FILE="$MISE_MANIFEST" mise install --dry-run-code >/dev/null 2>&1; then
        echo "Mise runtimes are already installed."
    else
        MISE_GLOBAL_CONFIG_FILE="$MISE_MANIFEST" mise install --yes
    fi

    had_global_config=0
    previous_global_config=""
    if [[ -n "${MISE_GLOBAL_CONFIG_FILE+x}" ]]; then
        had_global_config=1
        previous_global_config="$MISE_GLOBAL_CONFIG_FILE"
    fi
    export MISE_GLOBAL_CONFIG_FILE="$MISE_MANIFEST"
    activation="$(mise activate bash)" || die "Mise runtimes installed but shell activation failed"
    eval "$activation"
    if (( had_global_config == 1 )); then
        export MISE_GLOBAL_CONFIG_FILE="$previous_global_config"
    else
        unset MISE_GLOBAL_CONFIG_FILE
    fi
    hash -r

    missing=()
    for command_name in node npm python rustc cargo rustfmt java javac; do
        command -v "$command_name" >/dev/null 2>&1 || missing+=("$command_name")
    done
    if (( ${#missing[@]} > 0 )); then
        die "Mise finished but required runtime commands are not on PATH: ${missing[*]}"
    fi

    cargo clippy --version >/dev/null 2>&1 ||
        die "Mise's Rust toolchain is missing the configured Clippy component"

    output="$(java -version 2>&1 || true)"
    if [[ "$output" != *"Corretto-21."* ]]; then
        die "Amazon Corretto JDK 21 is required (java -version did not report Corretto 21)"
    fi

    output="$(javac -version 2>&1 || true)"
    version="${output##* }"
    version_at_least "$version" "21.0.0" ||
        die "JDK 21+ is required (found '${version:-unknown}')"

    cd -- "$original_working_directory"
}

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
    local src="$REPO_ROOT/$1" dst="$HOME/$2"
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

preflight_links() {
    local source required_directory
    local directory_sources file_sources

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
        herdr/config.toml
        hunk/config.toml
        mise/conf.d/00-dotfiles.toml
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

    for required_directory in \
        "$HOME/.config" \
        "$HOME/.config/mise" \
        "$HOME/.local" \
        "$HOME/.local/share" \
        "$LOCAL_DIR"
    do
        if [[ ( -e "$required_directory" || -L "$required_directory" ) &&
            ! -d "$required_directory" ]]
        then
            die "'$required_directory' blocks required configuration directory"
        fi
    done
}

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
    link_nested \
        mise/conf.d/00-dotfiles.toml \
        .config/mise/conf.d/00-dotfiles.toml \
        .config/mise/conf.d
    link nvim        .config/nvim
    link tmux        .config/tmux
    link zsh/.zshrc  .zshrc

    mkdir -p "$LOCAL_DIR"
    for template in local.fish local.zsh; do
        if [[ ! -e "$LOCAL_DIR/$template" && ! -L "$LOCAL_DIR/$template" ]]; then
            cp "$REPO_ROOT/templates/$template" "$LOCAL_DIR/"
        fi
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
install_mise_runtimes
link_configs
print_next_steps

printf '\nDotfiles installation complete.\n'
