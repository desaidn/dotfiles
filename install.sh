#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
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
DEVFLOW_SOURCE="$REPO_ROOT/devflow"
DEVFLOW_DISTRIBUTION="dotfiles-devflow"
DEVFLOW_TOOL_DIR="$LOCAL_DIR/uv-tools"
DEVFLOW_TOOL_ENV="$DEVFLOW_TOOL_DIR/$DEVFLOW_DISTRIBUTION"
DEVFLOW_BIN_DIR="$HOME/.local/bin"
DEVFLOW_RECEIPT="$LOCAL_DIR/devflow-tool.receipt"
DEVFLOW_INSTALL_STATE=""
DEVFLOW_RECEIPT_STATUS=""
DEVFLOW_RECEIPT_SOURCE=""
DEVFLOW_RECEIPT_PYTHON=""

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
                procps-ng curl file git tar gzip unzip diffutils ca-certificates
            ;;
        yum)
            sudo yum groupinstall -y "Development Tools"
            sudo yum install -y \
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

    output="$(lazygit --version 2>/dev/null || true)"
    version="${output#*version=}"
    version="${version%%,*}"
    version_at_least "$version" "0.56.0" ||
        errors+=("LazyGit 0.56+ is required (found '${version:-unknown}')")

    output="$(hunk --version 2>/dev/null || true)"
    version="${output##* }"
    version_at_least "$version" "0.18.1" ||
        errors+=("Hunk 0.18.1+ is required (found '${version:-unknown}')")

    output="$(tree-sitter --version 2>/dev/null || true)"
    version="${output##* }"
    version_at_least "$version" "0.26.1" ||
        errors+=("tree-sitter CLI 0.26.1+ is required (found '${version:-unknown}')")

    output="$(nvim --version 2>/dev/null || true)"
    output="${output%%$'\n'*}"
    if [[ "$output" != "NVIM v0.12.5" ]]; then
        errors+=("stable Neovim 0.12.5 is required (found '${output:-unknown}')")
    fi

    if (( ${#errors[@]} > 0 )); then
        printf 'Installed application versions do not satisfy this configuration:\n' >&2
        printf '  %s\n' "${errors[@]}" >&2
        exit 1
    fi
}

install_mise_runtimes() (
    local activation
    local active_version command_name command_path expected_version
    local manifest_key mise_command_path output tool_name version
    local mismatched missing version_mismatches

    section "Installing Mise runtimes"
    cd -- "$REPO_ROOT"
    export MISE_CONFIG_DIR="$MISE_BOOTSTRAP_CONFIG_DIR"
    unset \
        MISE_CONFIG_FILE \
        MISE_GLOBAL_CONFIG_FILE \
        MISE_GLOBAL_CONFIG_ROOT \
        MISE_IGNORED_CONFIG_PATHS \
        MISE_NO_CONFIG \
        MISE_DISABLE_TOOLS \
        MISE_NODE_VERSION \
        MISE_PYTHON_VERSION \
        MISE_RUST_VERSION \
        MISE_JAVA_VERSION

    if mise install --dry-run-code >/dev/null 2>&1; then
        echo "Mise runtimes are already installed."
    else
        mise install --yes
    fi

    activation="$(mise activate bash)" || die "Mise runtimes installed but shell activation failed"
    eval "$activation"
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

    output="$(java -version 2>&1 || true)"
    if [[ "$output" != *"Corretto-21."* ]]; then
        die "Amazon Corretto JDK 21 is required (java -version did not report Corretto 21)"
    fi

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

load_devflow_receipt() {
    local line
    local lines=()

    [[ -f "$DEVFLOW_RECEIPT" && ! -L "$DEVFLOW_RECEIPT" ]] || return 1
    while IFS= read -r line; do
        lines+=("$line")
    done <"$DEVFLOW_RECEIPT"
    [[ ${#lines[@]} == 3 ]] || return 1
    case "${lines[0]}" in
        dotfiles-devflow-v2)
            DEVFLOW_RECEIPT_STATUS="final"
            ;;
        dotfiles-devflow-pending-v2)
            DEVFLOW_RECEIPT_STATUS="pending"
            ;;
        *)
            return 1
            ;;
    esac
    [[ -n "${lines[1]}" && -n "${lines[2]}" ]] || return 1

    DEVFLOW_RECEIPT_SOURCE="${lines[1]}"
    DEVFLOW_RECEIPT_PYTHON="${lines[2]}"
}

clear_devflow_resolver_environment() {
    local variable

    while IFS= read -r variable; do
        case "$variable" in
            UV_*|PYTHON*|VIRTUAL_ENV*|CONDA_*|PIP_*)
                unset "$variable"
                ;;
        esac
    done < <(compgen -e)
}

devflow_uv_receipt_matches() {
    local expected_python="$1" expected_source="$2"

    [[ -f "$DEVFLOW_TOOL_ENV/uv-receipt.toml" &&
        ! -L "$DEVFLOW_TOOL_ENV/uv-receipt.toml" ]] || return 1
    (
        clear_devflow_resolver_environment
        "$expected_python" - \
            "$DEVFLOW_TOOL_ENV/uv-receipt.toml" \
            "$expected_python" \
            "$expected_source" \
            "$DEVFLOW_BIN_DIR" \
            "$DEVFLOW_DISTRIBUTION" <<'PYTHON'
from __future__ import annotations

import sys
import tomllib
from collections.abc import Mapping, Sequence


def records_match(
    value: object,
    *,
    keys: tuple[str, ...],
    expected: frozenset[tuple[str, ...]],
) -> bool:
    if not isinstance(value, Sequence) or isinstance(value, (str, bytes)):
        return False
    records: list[tuple[str, ...]] = []
    for item in value:
        if not isinstance(item, Mapping) or set(item) != set(keys):
            return False
        record = tuple(item[key] for key in keys)
        if not all(isinstance(field, str) for field in record):
            return False
        records.append(record)
    return len(records) == len(expected) and frozenset(records) == expected


receipt_path, expected_python, expected_source, bin_dir, distribution = sys.argv[1:]
try:
    with open(receipt_path, "rb") as receipt_file:
        receipt = tomllib.load(receipt_file)
except (OSError, UnicodeError, tomllib.TOMLDecodeError):
    raise SystemExit(1) from None

if set(receipt) != {"tool"} or not isinstance(receipt["tool"], Mapping):
    raise SystemExit(1)
tool = receipt["tool"]
if set(tool) != {"requirements", "python", "entrypoints"}:
    raise SystemExit(1)
if tool["python"] != expected_python:
    raise SystemExit(1)
if not records_match(
    tool["requirements"],
    keys=("name", "editable"),
    expected=frozenset({(distribution, expected_source)}),
):
    raise SystemExit(1)
expected_entrypoints = frozenset(
    {("devflow", f"{bin_dir}/devflow", distribution)}
)
if not records_match(
    tool["entrypoints"],
    keys=("name", "install-path", "from"),
    expected=expected_entrypoints,
):
    raise SystemExit(1)
PYTHON
    )
}

devflow_environment_matches() {
    local expected_python="$1" expected_source="$2"
    local candidate line
    local source_markers=() source_lines=()

    devflow_uv_receipt_matches "$expected_python" "$expected_source" ||
        return 1
    symlink_points_to "$DEVFLOW_TOOL_ENV/bin/python" "$expected_python" ||
        return 1

    for candidate in \
        "$DEVFLOW_TOOL_ENV"/lib/python*/site-packages/dotfiles_devflow.pth
    do
        [[ -f "$candidate" && ! -L "$candidate" ]] || continue
        source_markers+=("$candidate")
    done
    [[ ${#source_markers[@]} == 1 ]] || return 1
    while IFS= read -r line || [[ -n "$line" ]]; do
        source_lines+=("$line")
    done <"${source_markers[0]}"
    [[ ${#source_lines[@]} == 1 &&
        "${source_lines[0]}" == "$expected_source/src" ]]
}

devflow_public_entrypoints_match() {
    symlink_points_to \
        "$DEVFLOW_BIN_DIR/devflow" \
        "$DEVFLOW_TOOL_ENV/bin/devflow"
}

devflow_installation_matches() {
    local expected_python="$1" expected_source="$2"

    [[ -d "$DEVFLOW_TOOL_ENV" && ! -L "$DEVFLOW_TOOL_ENV" ]] ||
        return 1
    devflow_environment_matches "$expected_python" "$expected_source" ||
        return 1
    devflow_public_entrypoints_match
}

devflow_installation_is_absent() {
    [[ ! -e "$DEVFLOW_TOOL_ENV" && ! -L "$DEVFLOW_TOOL_ENV" ]] ||
        return 1
    [[ ! -e "$DEVFLOW_BIN_DIR/devflow" && ! -L "$DEVFLOW_BIN_DIR/devflow" ]]
}

preflight_devflow_state() {
    if [[ ! -e "$DEVFLOW_RECEIPT" && ! -L "$DEVFLOW_RECEIPT" ]]; then
        devflow_installation_is_absent ||
            die "existing Workflow Engine files have no dotfiles ownership receipt; preserve or remove them explicitly"
        DEVFLOW_INSTALL_STATE="absent"
        return 0
    fi

    load_devflow_receipt ||
        die "the Workflow Engine ownership receipt is invalid or ambiguous: $DEVFLOW_RECEIPT"
    [[ "$DEVFLOW_RECEIPT_SOURCE" == "$DEVFLOW_SOURCE" ]] ||
        die "the Workflow Engine ownership receipt belongs to a different source: $DEVFLOW_RECEIPT_SOURCE"

    case "$DEVFLOW_RECEIPT_STATUS" in
        final)
            devflow_installation_matches \
                "$DEVFLOW_RECEIPT_PYTHON" "$DEVFLOW_RECEIPT_SOURCE" ||
                die "the Workflow Engine environment does not match its ownership receipt"
            DEVFLOW_INSTALL_STATE="owned"
            ;;
        pending)
            if devflow_installation_is_absent; then
                DEVFLOW_INSTALL_STATE="pending-empty"
            elif devflow_installation_matches \
                "$DEVFLOW_RECEIPT_PYTHON" "$DEVFLOW_RECEIPT_SOURCE"
            then
                DEVFLOW_INSTALL_STATE="pending-complete"
            else
                die "the pending Workflow Engine installation is partial or does not match its ownership receipt"
            fi
            ;;
        *)
            die "internal error: unsupported Workflow Engine receipt state"
            ;;
    esac
}

resolve_mise_python_path() (
    cd -- "$REPO_ROOT"
    export MISE_CONFIG_DIR="$MISE_BOOTSTRAP_CONFIG_DIR"
    unset \
        MISE_CONFIG_FILE \
        MISE_GLOBAL_CONFIG_FILE \
        MISE_GLOBAL_CONFIG_ROOT \
        MISE_IGNORED_CONFIG_PATHS \
        MISE_NO_CONFIG \
        MISE_DISABLE_TOOLS \
        MISE_NODE_VERSION \
        MISE_PYTHON_VERSION \
        MISE_RUST_VERSION \
        MISE_JAVA_VERSION
    mise which python
)

run_devflow_uv() (
    clear_devflow_resolver_environment
    export UV_TOOL_DIR="$DEVFLOW_TOOL_DIR"
    export UV_TOOL_BIN_DIR="$DEVFLOW_BIN_DIR"
    uv --no-config "$@"
)

write_devflow_receipt() {
    local marker="$1" python_path="$2"
    local receipt_temporary="$DEVFLOW_RECEIPT.tmp.$$"

    [[ ! -e "$receipt_temporary" && ! -L "$receipt_temporary" ]] ||
        die "temporary Workflow Engine receipt already exists: $receipt_temporary"
    (
        umask 077
        printf '%s\n%s\n%s\n' \
            "$marker" "$DEVFLOW_SOURCE" "$python_path" \
            >"$receipt_temporary"
    )
    mv "$receipt_temporary" "$DEVFLOW_RECEIPT"
}

install_devflow() {
    local python_path

    section "Installing Workflow Engine"
    python_path="$(resolve_mise_python_path)" ||
        die "Mise could not resolve the tracked Python interpreter for the Workflow Engine"
    [[ "$python_path" == /* && -x "$python_path" ]] ||
        die "Mise returned an invalid Python interpreter for the Workflow Engine: $python_path"

    if [[ "$DEVFLOW_INSTALL_STATE" == "owned" ]]; then
        [[ "$DEVFLOW_RECEIPT_PYTHON" == "$python_path" ]] ||
            die "the owned Workflow Engine uses a different Python interpreter; uninstall it explicitly before reinstalling"
        "$DEVFLOW_BIN_DIR/devflow" --help >/dev/null 2>&1 ||
            die "the owned Workflow Engine executable is not runnable"
        echo "Workflow Engine is already installed."
        return 0
    fi

    mkdir -p "$DEVFLOW_TOOL_DIR" "$DEVFLOW_BIN_DIR"
    case "$DEVFLOW_INSTALL_STATE" in
        absent)
            write_devflow_receipt \
                "dotfiles-devflow-pending-v2" "$python_path"
            ;;
        pending-empty|pending-complete)
            [[ "$DEVFLOW_RECEIPT_PYTHON" == "$python_path" ]] ||
                die "the pending Workflow Engine installation uses a different Python interpreter"
            ;;
        *)
            die "internal error: unknown Workflow Engine install state '$DEVFLOW_INSTALL_STATE'"
            ;;
    esac

    if [[ "$DEVFLOW_INSTALL_STATE" == "pending-complete" ]]; then
        "$DEVFLOW_BIN_DIR/devflow" --help >/dev/null 2>&1 ||
            die "the pending Workflow Engine executable is not runnable"
        write_devflow_receipt "dotfiles-devflow-v2" "$python_path"
        echo "Workflow Engine installation resumed."
        return 0
    fi

    run_devflow_uv tool install \
        --python "$python_path" \
        --no-python-downloads \
        --editable "$DEVFLOW_SOURCE"

    [[ -d "$DEVFLOW_TOOL_ENV" && ! -L "$DEVFLOW_TOOL_ENV" ]] ||
        die "uv completed without creating the Workflow Engine environment"
    devflow_environment_matches "$python_path" "$DEVFLOW_SOURCE" ||
        die "uv created a Workflow Engine environment with unexpected provenance"
    symlink_points_to \
        "$DEVFLOW_BIN_DIR/devflow" \
        "$DEVFLOW_TOOL_ENV/bin/devflow" ||
        die "uv completed without creating the expected Workflow Engine executable: devflow"
    "$DEVFLOW_BIN_DIR/devflow" --help >/dev/null 2>&1 ||
        die "uv installed a Workflow Engine executable that is not runnable"

    write_devflow_receipt "dotfiles-devflow-v2" "$python_path"
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
    local directory_sources file_sources package_directories required_directories

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
        devflow/pyproject.toml
        devflow/src/devflow/__init__.py
        devflow/src/devflow/guidance.md
        devflow/uv.lock
        herdr/config.toml
        hunk/config.toml
        mise/conf.d/00-dotfiles.toml
        zsh/.zshrc
        templates/local.fish
        templates/local.zsh
    )
    package_directories=(
        devflow
        devflow/src/devflow
    )

    for source in "${directory_sources[@]}"; do
        [[ -d "$REPO_ROOT/$source" ]] ||
            die "missing or invalid tracked configuration directory: $REPO_ROOT/$source"
    done
    for source in "${file_sources[@]}"; do
        [[ -f "$REPO_ROOT/$source" ]] ||
            die "missing or invalid tracked configuration file: $REPO_ROOT/$source"
    done
    for source in "${package_directories[@]}"; do
        [[ -d "$REPO_ROOT/$source" ]] ||
            die "missing or invalid tracked package directory: $REPO_ROOT/$source"
    done

    required_directories=(
        "$HOME/.config"
        "$HOME/.local"
        "$HOME/.local/share"
        "$LOCAL_DIR"
    )
    if (( SKIP_MISE_RUNTIMES == 0 )); then
        required_directories+=(
            "$HOME/.config/mise"
            "$DEVFLOW_BIN_DIR"
            "$DEVFLOW_TOOL_DIR"
        )
    fi

    for required_directory in "${required_directories[@]}"; do
        if [[ ( -e "$required_directory" || -L "$required_directory" ) &&
            ! -d "$required_directory" ]]
        then
            die "'$required_directory' blocks required configuration directory"
        fi
    done

    if (( SKIP_MISE_RUNTIMES == 0 )); then
        preflight_devflow_state
    fi
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
if (( SKIP_MISE_RUNTIMES == 1 )); then
    section "Installing Mise runtimes"
    echo "Mise runtime installation and validation skipped by request."
else
    install_mise_runtimes
    install_devflow
fi
link_configs
print_next_steps

if (( SKIP_MISE_RUNTIMES == 1 )); then
    printf '\nDotfiles installation complete with Mise runtime provisioning skipped.\n'
else
    printf '\nDotfiles installation complete.\n'
fi
