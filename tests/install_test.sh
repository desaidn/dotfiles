#!/usr/bin/env bash
set -euo pipefail

TESTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$TESTS_DIR/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-install-test.XXXXXX")"

cleanup() {
    local cleanup_status=$?
    trap - EXIT
    if [[ "${DOTFILES_KEEP_TEST_TMP:-0}" == "1" ]]; then
        printf 'kept test fixtures at %s\n' "$TEST_ROOT" >&2
        exit "$cleanup_status"
    fi
    rm -rf "$TEST_ROOT"
    exit "$cleanup_status"
}
trap cleanup EXIT HUP INT TERM

fail() {
    printf 'not ok - %s\n' "$*" >&2
    exit 1
}

pass() {
    printf 'ok - %s\n' "$*"
}

assert_eq() {
    local expected="$1" actual="$2" message="$3"
    if [[ "$actual" != "$expected" ]]; then
        fail "$message (expected '$expected', got '$actual')"
    fi
}

assert_exists() {
    local path="$1"
    [[ -e "$path" || -L "$path" ]] || fail "expected path to exist: $path"
}

assert_not_exists() {
    local path="$1"
    [[ ! -e "$path" && ! -L "$path" ]] || fail "expected path not to exist: $path"
}

assert_symlink() {
    local target="$1" expected="$2"
    [[ -L "$target" ]] || fail "expected symlink: $target"
    assert_eq "$expected" "$(readlink "$target")" "unexpected symlink target for $target"
}

log_count() {
    local line="$1" log_file="$2" count
    count="$(grep -Fxc "$line" "$log_file" 2>/dev/null || true)"
    printf '%s\n' "${count:-0}"
}

assert_log_count() {
    local expected="$1" line="$2" log_file="$3"
    assert_eq "$expected" "$(log_count "$line" "$log_file")" "unexpected action count for '$line'"
}

log_prefix_count() {
    local prefix="$1" log_file="$2" count
    count="$(grep -c "^$prefix" "$log_file" 2>/dev/null || true)"
    printf '%s\n' "${count:-0}"
}

assert_log_prefix_count() {
    local expected="$1" prefix="$2" log_file="$3"
    assert_eq "$expected" "$(log_prefix_count "$prefix" "$log_file")" "unexpected action count for lines beginning '$prefix'"
}

write_fake_commands() {
    local command_name command_path
    for command_name in bash cat chmod cp date dirname env ln mkdir readlink; do
        command_path="$(command -v "$command_name")"
        ln -s "$command_path" "$FIXTURE_FAKE_BIN/$command_name"
    done

    cat >"$FIXTURE_FAKE_BIN/mv" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

flag="$DOTFILES_TEST_STATE/receipt-finalize-interruption"
if [[ -f "$flag" && "$#" == 2 &&
    "$2" == "$HOME/.local/share/dotfiles/devflow-tool.receipt" ]]
then
    first_line=""
    flag_state=""
    IFS= read -r first_line <"$1" || true
    IFS= read -r flag_state <"$flag" || true
    if [[ "$first_line" == "dotfiles-devflow-v1" &&
        "$flag_state" == "interrupt" ]]
    then
        printf 'consumed\n' >"$flag"
        exit 6
    fi
fi
exec "$DOTFILES_TEST_REAL_MV" "$@"
SCRIPT

    cat >"$FIXTURE_FAKE_BIN/uname" <<'SCRIPT'
#!/usr/bin/env bash
case "${1:-}" in
    -m)
        if [[ "$DOTFILES_TEST_OS" == "Darwin" ]]; then
            printf 'arm64\n'
        else
            printf 'x86_64\n'
        fi
        ;;
    *)
        printf '%s\n' "$DOTFILES_TEST_OS"
        ;;
esac
SCRIPT

    cat >"$FIXTURE_FAKE_BIN/xcode-select" <<'SCRIPT'
#!/usr/bin/env bash
case "${1:-}" in
    -p)
        printf '/Library/Developer/CommandLineTools\n'
        ;;
    --install)
        printf 'xcode-select install\n' >>"$DOTFILES_TEST_LOG"
        ;;
    *)
        exit 1
        ;;
esac
SCRIPT

    cat >"$FIXTURE_FAKE_BIN/curl" <<'SCRIPT'
#!/usr/bin/env bash
cat <<'INSTALLER'
#!/usr/bin/env bash
printf 'brew bootstrap\n' >>"$DOTFILES_TEST_LOG"
cp "$DOTFILES_TEST_BREW_TEMPLATE" "$DOTFILES_TEST_FAKE_BIN/brew"
chmod +x "$DOTFILES_TEST_FAKE_BIN/brew"
INSTALLER
SCRIPT

    cat >"$FIXTURE_FAKE_BIN/sudo" <<'SCRIPT'
#!/usr/bin/env bash
if [[ "${1:-}" == "-v" ]]; then
    exit 0
fi
if [[ "${1:-}" == "-n" || "${1:-}" == "--" ]]; then
    shift
fi
exec "$@"
SCRIPT

    cat >"$FIXTURE_PACKAGE_TEMPLATE" <<'SCRIPT'
#!/usr/bin/env bash
install_native_commands() {
    local command_name
    for command_name in cc make ps file git tar gzip unzip diff; do
        cp "$DOTFILES_TEST_GENERIC_TEMPLATE" "$DOTFILES_TEST_FAKE_BIN/$command_name"
        chmod +x "$DOTFILES_TEST_FAKE_BIN/$command_name"
    done
}

manager="${0##*/}"
printf '%s %s\n' "$manager" "$*" >>"$DOTFILES_TEST_LOG"
case "$manager" in
    apt-get)
        case " $* " in
            *" install "*)
                install_native_commands
                ;;
        esac
        ;;
    dnf)
        case " $* " in
            *" group install -y development-tools "*)
                if [[ ! -e "$DOTFILES_TEST_STATE/dnf-lowercase-group-tried" ]]; then
                    : >"$DOTFILES_TEST_STATE/dnf-lowercase-group-tried"
                    exit 1
                fi
                install_native_commands
                ;;
            *" group install -y Development Tools "*|*" install "*)
                install_native_commands
                ;;
        esac
        ;;
    yum)
        case " $* " in
            *" groupinstall "*|*" install "*)
                install_native_commands
                ;;
        esac
        ;;
    pacman)
        case " $* " in
            *" -S --needed --noconfirm "*)
                install_native_commands
                ;;
        esac
        ;;
esac
SCRIPT

    if [[ "$FIXTURE_PACKAGE_MANAGER" != "none" ]]; then
        cp "$FIXTURE_PACKAGE_TEMPLATE" "$FIXTURE_FAKE_BIN/$FIXTURE_PACKAGE_MANAGER"
        chmod +x "$FIXTURE_FAKE_BIN/$FIXTURE_PACKAGE_MANAGER"
    fi

    cat >"$FIXTURE_GENERIC_TEMPLATE" <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT

    cat >"$FIXTURE_MISE_TEMPLATE" <<'SCRIPT'
#!/usr/bin/env bash
if [[ "$PWD" != "$DOTFILES_TEST_REPO_ROOT" ]]; then
    printf 'mise invoked from unexpected directory: %s\n' "$PWD" >&2
    exit 4
fi
if [[ "${MISE_CONFIG_DIR:-}" != "$DOTFILES_TEST_REPO_ROOT/mise" ]]; then
    printf 'mise received unexpected config directory: %s\n' "${MISE_CONFIG_DIR:-unset}" >&2
    exit 4
fi
if [[ -n "${MISE_CONFIG_FILE:-}" ||
    -n "${MISE_GLOBAL_CONFIG_FILE:-}" ||
    -n "${MISE_GLOBAL_CONFIG_ROOT:-}" ||
    -n "${MISE_IGNORED_CONFIG_PATHS:-}" ||
    -n "${MISE_NO_CONFIG:-}" ||
    -n "${MISE_DISABLE_TOOLS:-}" ||
    -n "${MISE_NODE_VERSION:-}" ||
    -n "${MISE_PYTHON_VERSION:-}" ||
    -n "${MISE_RUST_VERSION:-}" ||
    -n "${MISE_JAVA_VERSION:-}" ]]
then
    printf 'mise received an external config or tool override\n' >&2
    exit 4
fi

write_runtime_commands() {
    local command_name
    mkdir -p "$DOTFILES_TEST_STATE/rust-sysroot/lib/rustlib/src/rust/library"
    for command_name in node npm python python3 rustc cargo clippy rustfmt java javac; do
        cp "$DOTFILES_TEST_RUNTIME_TEMPLATE" "$DOTFILES_TEST_FAKE_BIN/$command_name"
        chmod +x "$DOTFILES_TEST_FAKE_BIN/$command_name"
    done
}

case "${1:-}" in
    config)
        if [[ "${2:-}" != "get" || "${3:-}" != "-f" ||
            "${4:-}" != "$DOTFILES_TEST_REPO_ROOT/mise/conf.d/00-dotfiles.toml" ]]
        then
            exit 2
        fi
        case "${5:-}" in
            "tools.core:node")
                printf '24.18.0\n'
                ;;
            "tools.core:python")
                printf '3.14.7\n'
                ;;
            "tools.core:rust.version")
                printf '1.97.1\n'
                ;;
            "tools.core:java")
                printf 'corretto-21.0.12.8.1\n'
                ;;
            *)
                exit 2
                ;;
        esac
        ;;
    current)
        if [[ -e "$DOTFILES_TEST_STATE/mise-version-mismatch" &&
            "${2:-}" == "node" ]]
        then
            printf '18.20.2\n'
        else
            case "${2:-}" in
                node)
                    printf '24.18.0\n'
                    ;;
                python)
                    printf '3.14.7\n'
                    ;;
                rust)
                    printf '1.97.1\n'
                    ;;
                java)
                    printf 'corretto-21.0.12.8.1\n'
                    ;;
                *)
                    exit 2
                    ;;
            esac
        fi
        ;;
    install)
        case " $* " in
            *" --dry-run-code "*|*" --dry-run "*)
                printf 'mise dry-run\n' >>"$DOTFILES_TEST_LOG"
                [[ -e "$DOTFILES_TEST_STATE/mise-installed" ]]
                ;;
            *)
                printf 'mise install\n' >>"$DOTFILES_TEST_LOG"
                : >"$DOTFILES_TEST_STATE/mise-installed"
                write_runtime_commands
                ;;
        esac
        ;;
    activate)
        printf 'mise activate\n' >>"$DOTFILES_TEST_LOG"
        printf 'export PATH="%s:$PATH"\n' "$DOTFILES_TEST_FAKE_BIN"
        ;;
    which)
        if [[ -e "$DOTFILES_TEST_STATE/mise-which-mismatch" ]]; then
            printf '%s/not-selected/%s\n' "$DOTFILES_TEST_STATE" "${2:-unknown}"
        else
            printf '%s/%s\n' "$DOTFILES_TEST_FAKE_BIN" "${2:-unknown}"
        fi
        ;;
    *)
        exit 0
        ;;
esac
SCRIPT

    cat >"$FIXTURE_RUNTIME_TEMPLATE" <<'SCRIPT'
#!/usr/bin/env bash
case "${0##*/}" in
    java)
        printf 'openjdk version "21.0.12"\n' >&2
        if [[ -e "$DOTFILES_TEST_STATE/non-corretto-java" ]]; then
            printf 'OpenJDK Runtime Environment Temurin-21.0.12+8\n' >&2
        else
            printf 'OpenJDK Runtime Environment Corretto-21.0.12.8.1\n' >&2
        fi
        ;;
    node)
        printf 'v24.18.0\n'
        ;;
    npm)
        printf '11.4.2\n'
        ;;
    python|python3)
        if [[ "${1:-}" == "-" ]]; then
            exec "$DOTFILES_TEST_REAL_PYTHON" "$@"
        fi
        printf 'Python 3.14.7\n'
        ;;
    rustc)
        if [[ " ${*:-} " == *' --print sysroot '* ]]; then
            printf '%s\n' "$DOTFILES_TEST_STATE/rust-sysroot"
        else
            printf 'rustc 1.97.1\n'
        fi
        ;;
    cargo)
        printf 'cargo 1.97.1\n'
        ;;
    clippy)
        printf 'clippy 0.1.97\n'
        ;;
    rustfmt)
        printf 'rustfmt 1.8.0-stable\n'
        ;;
    javac)
        printf 'javac 21.0.12\n'
        ;;
esac
SCRIPT

    cat >"$FIXTURE_UV_TEMPLATE" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

tool_dir="${UV_TOOL_DIR:-}"
bin_dir="${UV_TOOL_BIN_DIR:-}"
expected_tool_dir="$HOME/.local/share/dotfiles/uv-tools"
expected_bin_dir="$HOME/.local/bin"
no_config=0

if [[ "${1:-}" == "--no-config" ]]; then
    no_config=1
    shift
fi

if [[ -e "$DOTFILES_TEST_STATE/expect-uv-isolation" ]]; then
    (( no_config == 1 )) || {
        printf 'uv was not isolated from configuration files\n' >&2
        exit 4
    }
    for variable in $(compgen -e); do
        case "$variable" in
            UV_TOOL_DIR|UV_TOOL_BIN_DIR)
                ;;
            UV_*|PYTHON*|VIRTUAL_ENV*|CONDA_*|PIP_*)
                printf 'uv inherited forbidden environment variable: %s\n' \
                    "$variable" >&2
                exit 4
                ;;
        esac
    done
    [[ "${HTTP_PROXY:-}" == "http://proxy.example:8080" &&
        "${HTTPS_PROXY:-}" == "https://proxy.example:8443" &&
        "${NO_PROXY:-}" == "localhost,127.0.0.1" &&
        "${SSL_CERT_FILE:-}" == "$DOTFILES_TEST_STATE/test-ca.pem" ]] || {
        printf 'uv did not preserve proxy and CA environment\n' >&2
        exit 4
    }
fi

[[ "$tool_dir" == "$expected_tool_dir" ]] || {
    printf 'uv received unexpected tool directory: %s\n' "${tool_dir:-unset}" >&2
    exit 4
}
[[ "$bin_dir" == "$expected_bin_dir" ]] || {
    printf 'uv received unexpected bin directory: %s\n' "${bin_dir:-unset}" >&2
    exit 4
}
case " $* " in
    *" --force "*)
        printf 'uv received forbidden --force option\n' >&2
        exit 4
        ;;
esac

case "${1:-} ${2:-}" in
    "tool install")
        [[ "$#" == 7 &&
            "${3:-}" == "--python" &&
            "${4:-}" == "$DOTFILES_TEST_FAKE_BIN/python" &&
            "${5:-}" == "--no-python-downloads" &&
            "${6:-}" == "--editable" &&
            "${7:-}" == "$DOTFILES_TEST_REPO_ROOT/devflow" ]] || {
            printf 'unexpected uv tool install arguments: %s\n' "$*" >&2
            exit 4
        }
        printf 'uv tool install|%s|%s|%s\n' "$tool_dir" "$bin_dir" "$*" \
            >>"$DOTFILES_TEST_LOG"
        [[ ! -e "$DOTFILES_TEST_STATE/uv-install-failure" ]] || exit 5
        mkdir -p \
            "$tool_dir/dotfiles-devflow/bin" \
            "$tool_dir/dotfiles-devflow/lib/python3.14/site-packages" \
            "$bin_dir"
        ln -s "$DOTFILES_TEST_FAKE_BIN/python" \
            "$tool_dir/dotfiles-devflow/bin/python"
        printf '%s' "$DOTFILES_TEST_REPO_ROOT/devflow/src" \
            >"$tool_dir/dotfiles-devflow/lib/python3.14/site-packages/dotfiles_devflow.pth"
        printf '%s\n' \
            '[tool]' \
            "requirements = [{ name = \"dotfiles-devflow\", editable = \"$DOTFILES_TEST_REPO_ROOT/devflow\" }]" \
            "python = \"$DOTFILES_TEST_FAKE_BIN/python\"" \
            'entrypoints = [' \
            "    { name = \"devflow\", install-path = \"$bin_dir/devflow\", from = \"dotfiles-devflow\" }," \
            "    { name = \"devflow-pre-push\", install-path = \"$bin_dir/devflow-pre-push\", from = \"dotfiles-devflow\" }," \
            "    { name = \"devflow-reference-transaction\", install-path = \"$bin_dir/devflow-reference-transaction\", from = \"dotfiles-devflow\" }," \
            ']' \
            >"$tool_dir/dotfiles-devflow/uv-receipt.toml"
        for executable in \
            devflow devflow-reference-transaction devflow-pre-push
        do
            cp "$DOTFILES_TEST_GENERIC_TEMPLATE" \
                "$tool_dir/dotfiles-devflow/bin/$executable"
            chmod +x "$tool_dir/dotfiles-devflow/bin/$executable"
            ln -s "$tool_dir/dotfiles-devflow/bin/$executable" \
                "$bin_dir/$executable"
        done
        if [[ -e "$DOTFILES_TEST_STATE/uv-interrupt-after-install" ]]; then
            printf 'consumed\n' \
                >"$DOTFILES_TEST_STATE/uv-interrupt-after-install"
            exit 6
        fi
        ;;
    "tool uninstall")
        [[ "$#" == 3 && "${3:-}" == "dotfiles-devflow" ]] || {
            printf 'unexpected uv tool uninstall arguments: %s\n' "$*" >&2
            exit 4
        }
        printf 'uv tool uninstall|%s|%s|%s\n' "$tool_dir" "$bin_dir" "$*" \
            >>"$DOTFILES_TEST_LOG"
        for executable in \
            devflow devflow-reference-transaction devflow-pre-push
        do
            rm -f "$bin_dir/$executable"
        done
        rm -rf "$tool_dir/dotfiles-devflow"
        ;;
    *)
        printf 'unexpected uv command: %s\n' "$*" >&2
        exit 4
        ;;
esac
SCRIPT

    cat >"$FIXTURE_FORMULA_TEMPLATE" <<'SCRIPT'
#!/usr/bin/env bash
case "${0##*/}" in
    fish)
        if [[ "${1:-}" == "-l" ]]; then
            [[ -L "$HOME/.config/fish" ]] || exit 5
            [[ -f "$HOME/.local/share/dotfiles/local.fish" ]] || exit 5
            printf 'fish login environment ready\n' >>"$DOTFILES_TEST_LOG"
        else
            printf 'fish, version 4.0.2\n'
        fi
        ;;
    nvim)
        if [[ -f "$DOTFILES_TEST_STATE/nvim-version" ]]; then
            IFS= read -r nvim_version <"$DOTFILES_TEST_STATE/nvim-version"
            printf '%s\n' "$nvim_version"
        else
            printf 'NVIM v0.12.5\n'
        fi
        ;;
    tmux)
        printf 'tmux 3.7b\n'
        ;;
    lazygit)
        if [[ -e "$DOTFILES_TEST_STATE/old-lazygit" ]]; then
            printf 'commit=, build date=, build source=Homebrew, version=0.55.2, os=darwin, arch=arm64\n'
        else
            printf 'commit=, build date=, build source=Homebrew, version=0.63.0, os=darwin, arch=arm64\n'
        fi
        ;;
    hunk)
        if [[ -e "$DOTFILES_TEST_STATE/old-hunk" ]]; then
            printf '0.18.0\n'
        else
            printf '0.18.1\n'
        fi
        ;;
    tree-sitter)
        printf 'tree-sitter 0.26.1\n'
        ;;
    *)
        exit 0
        ;;
esac
SCRIPT

    cat >"$FIXTURE_BREW_TEMPLATE" <<'SCRIPT'
#!/usr/bin/env bash
install_formula_commands() {
    local command_name
    for command_name in git fish zsh nvim herdr tmux lazygit atuin gh rg tree-sitter hunk ghcup wl-copy wl-paste xclip; do
        cp "$DOTFILES_TEST_FORMULA_TEMPLATE" "$DOTFILES_TEST_FAKE_BIN/$command_name"
        chmod +x "$DOTFILES_TEST_FAKE_BIN/$command_name"
    done
    cp "$DOTFILES_TEST_MISE_TEMPLATE" "$DOTFILES_TEST_FAKE_BIN/mise"
    chmod +x "$DOTFILES_TEST_FAKE_BIN/mise"
    cp "$DOTFILES_TEST_UV_TEMPLATE" "$DOTFILES_TEST_FAKE_BIN/uv"
    chmod +x "$DOTFILES_TEST_FAKE_BIN/uv"
}

cask_name() {
    local argument name=""
    for argument in "$@"; do
        case "$argument" in
            install|list|--cask|--versions|--quiet)
                ;;
            --*)
                ;;
            *)
                name="$argument"
                ;;
        esac
    done
    printf '%s\n' "$name"
}

case "${1:-}" in
    shellenv)
        printf 'export PATH="%s:$PATH"\n' "$DOTFILES_TEST_FAKE_BIN"
        ;;
    bundle)
        case " $* " in
            *" --no-upgrade "*)
                ;;
            *)
                printf 'unsafe brew bundle arguments: %s\n' "$*" >&2
                exit 3
                ;;
        esac
        case " $* " in
            *" --file=$DOTFILES_TEST_REPO_ROOT/Brewfile "*|*" --file=$DOTFILES_TEST_REPO_ROOT/Brewfile")
                ;;
            *)
                printf 'brew bundle did not receive the tracked Brewfile: %s\n' "$*" >&2
                exit 3
                ;;
        esac
        case " $* " in
            *" check "*)
                printf 'brew bundle check\n' >>"$DOTFILES_TEST_LOG"
                [[ -e "$DOTFILES_TEST_STATE/bundle-installed" ]]
                ;;
            *" install "*)
                printf 'brew bundle install\n' >>"$DOTFILES_TEST_LOG"
                : >"$DOTFILES_TEST_STATE/bundle-installed"
                install_formula_commands
                ;;
            *)
                exit 2
                ;;
        esac
        ;;
    list)
        case " $* " in
            *" --cask "*)
                name="$(cask_name "$@")"
                [[ -e "$DOTFILES_TEST_STATE/cask-$name" ]]
                ;;
            *)
                exit 0
                ;;
        esac
        ;;
    install)
        case " $* " in
            *" --cask "*)
                name="$(cask_name "$@")"
                printf 'brew cask install %s\n' "$name" >>"$DOTFILES_TEST_LOG"
                : >"$DOTFILES_TEST_STATE/cask-$name"
                case "$name" in
                    ghostty)
                        mkdir -p "$DOTFILES_TEST_APPLICATION_DIR/Ghostty.app"
                        cp "$DOTFILES_TEST_GENERIC_TEMPLATE" "$DOTFILES_TEST_FAKE_BIN/ghostty"
                        chmod +x "$DOTFILES_TEST_FAKE_BIN/ghostty"
                        ;;
                    font-jetbrains-mono)
                        mkdir -p "$DOTFILES_TEST_FONT_DIR"
                        : >"$DOTFILES_TEST_FONT_DIR/JetBrainsMono-Regular.ttf"
                        ;;
                esac
                ;;
            *)
                install_formula_commands
                ;;
        esac
        ;;
    --prefix)
        printf '%s\n' "$DOTFILES_TEST_BREW_PREFIX"
        ;;
    *)
        exit 0
        ;;
esac
SCRIPT

    chmod +x \
        "$FIXTURE_FAKE_BIN/curl" \
        "$FIXTURE_FAKE_BIN/sudo" \
        "$FIXTURE_FAKE_BIN/uname" \
        "$FIXTURE_FAKE_BIN/xcode-select" \
        "$FIXTURE_BREW_TEMPLATE" \
        "$FIXTURE_FORMULA_TEMPLATE" \
        "$FIXTURE_GENERIC_TEMPLATE" \
        "$FIXTURE_MISE_TEMPLATE" \
        "$FIXTURE_FAKE_BIN/mv" \
        "$FIXTURE_PACKAGE_TEMPLATE" \
        "$FIXTURE_RUNTIME_TEMPLATE" \
        "$FIXTURE_UV_TEMPLATE"
}

new_fixture() {
    local name="$1" os_name="$2" package_manager="${3:-}"
    FIXTURE_ROOT="$TEST_ROOT/$name"
    FIXTURE_HOME="$FIXTURE_ROOT/home"
    FIXTURE_FAKE_BIN="$FIXTURE_ROOT/bin"
    FIXTURE_STATE="$FIXTURE_ROOT/state"
    FIXTURE_LOG="$FIXTURE_ROOT/actions.log"
    FIXTURE_OUTPUT="$FIXTURE_ROOT/install.out"
    FIXTURE_APPLICATION_DIR="$FIXTURE_ROOT/Applications"
    FIXTURE_FONT_DIR="$FIXTURE_ROOT/Fonts"
    FIXTURE_BREW_TEMPLATE="$FIXTURE_ROOT/brew-template"
    FIXTURE_FORMULA_TEMPLATE="$FIXTURE_ROOT/formula-template"
    FIXTURE_GENERIC_TEMPLATE="$FIXTURE_ROOT/generic-template"
    FIXTURE_MISE_TEMPLATE="$FIXTURE_ROOT/mise-template"
    FIXTURE_RUNTIME_TEMPLATE="$FIXTURE_ROOT/runtime-template"
    FIXTURE_UV_TEMPLATE="$FIXTURE_ROOT/uv-template"
    FIXTURE_PACKAGE_TEMPLATE="$FIXTURE_ROOT/package-template"
    FIXTURE_CALLER_DIR="$FIXTURE_ROOT/caller"
    FIXTURE_INSTALL_REPO_ROOT="$REPO_ROOT"
    FIXTURE_BREW_PREFIX="$FIXTURE_ROOT"
    FIXTURE_OS="$os_name"
    FIXTURE_REAL_MV="$(command -v mv)"
    FIXTURE_REAL_PYTHON="$(command -v python3)"
    if [[ -n "$package_manager" ]]; then
        FIXTURE_PACKAGE_MANAGER="$package_manager"
    elif [[ "$os_name" == "Linux" ]]; then
        FIXTURE_PACKAGE_MANAGER="apt-get"
    else
        FIXTURE_PACKAGE_MANAGER="none"
    fi
    if [[ "$os_name" == "Linux" ]]; then
        FIXTURE_SYSTEM_PATH=""
    else
        FIXTURE_SYSTEM_PATH="/usr/bin:/bin"
    fi

    mkdir -p \
        "$FIXTURE_HOME" \
        "$FIXTURE_FAKE_BIN" \
        "$FIXTURE_STATE" \
        "$FIXTURE_CALLER_DIR" \
        "$FIXTURE_APPLICATION_DIR" \
        "$FIXTURE_FONT_DIR"
    : >"$FIXTURE_LOG"
    printf '[tools]\n"core:java" = "corretto-8"\n' >"$FIXTURE_CALLER_DIR/mise.toml"
    write_fake_commands
}

run_installer() {
    local expected_result="${1:-success}"
    local run_home="$FIXTURE_HOME"

    if (( $# > 0 )); then
        shift
    fi
    if (( $# > 0 )) && [[ "$1" != --* ]]; then
        run_home="$1"
        shift
    fi

    if (
        cd "$FIXTURE_CALLER_DIR"
        env \
            HOME="$run_home" \
            PATH="$FIXTURE_FAKE_BIN${FIXTURE_SYSTEM_PATH:+:$FIXTURE_SYSTEM_PATH}" \
            DOTFILES_BREW_PATHS="$FIXTURE_FAKE_BIN/brew" \
            DOTFILES_APPLICATION_DIRS="$FIXTURE_APPLICATION_DIR" \
            DOTFILES_FONT_DIRS="$FIXTURE_FONT_DIR" \
            DOTFILES_TEST_APPLICATION_DIR="$FIXTURE_APPLICATION_DIR" \
            DOTFILES_TEST_BREW_TEMPLATE="$FIXTURE_BREW_TEMPLATE" \
            DOTFILES_TEST_BREW_PREFIX="$FIXTURE_BREW_PREFIX" \
            DOTFILES_TEST_FAKE_BIN="$FIXTURE_FAKE_BIN" \
            DOTFILES_TEST_FONT_DIR="$FIXTURE_FONT_DIR" \
            DOTFILES_TEST_FORMULA_TEMPLATE="$FIXTURE_FORMULA_TEMPLATE" \
            DOTFILES_TEST_GENERIC_TEMPLATE="$FIXTURE_GENERIC_TEMPLATE" \
            DOTFILES_TEST_LOG="$FIXTURE_LOG" \
            DOTFILES_TEST_MISE_TEMPLATE="$FIXTURE_MISE_TEMPLATE" \
            DOTFILES_TEST_OS="$FIXTURE_OS" \
            DOTFILES_TEST_REPO_ROOT="$FIXTURE_INSTALL_REPO_ROOT" \
            DOTFILES_TEST_REAL_MV="$FIXTURE_REAL_MV" \
            DOTFILES_TEST_REAL_PYTHON="$FIXTURE_REAL_PYTHON" \
            DOTFILES_TEST_RUNTIME_TEMPLATE="$FIXTURE_RUNTIME_TEMPLATE" \
            DOTFILES_TEST_STATE="$FIXTURE_STATE" \
            DOTFILES_TEST_UV_TEMPLATE="$FIXTURE_UV_TEMPLATE" \
            "$FIXTURE_INSTALL_REPO_ROOT/install.sh" "$@"
    ) >"$FIXTURE_OUTPUT" 2>&1
    then
        if [[ "$expected_result" == "failure" ]]; then
            fail "installer unexpectedly succeeded for the $FIXTURE_OS fixture"
        fi
        return 0
    fi

    if [[ "$expected_result" == "failure" ]]; then
        return 0
    fi

    sed 's/^/  | /' "$FIXTURE_OUTPUT" >&2
    fail "installer failed for the $FIXTURE_OS fixture"
}

run_uninstaller() {
    local expected_status="$1"
    shift

    if HOME="$FIXTURE_HOME" \
        PATH="$FIXTURE_FAKE_BIN:/usr/bin:/bin" \
        DOTFILES_TEST_FAKE_BIN="$FIXTURE_FAKE_BIN" \
        DOTFILES_TEST_GENERIC_TEMPLATE="$FIXTURE_GENERIC_TEMPLATE" \
        DOTFILES_TEST_LOG="$FIXTURE_LOG" \
        DOTFILES_TEST_REAL_MV="$FIXTURE_REAL_MV" \
        DOTFILES_TEST_REAL_PYTHON="$FIXTURE_REAL_PYTHON" \
        DOTFILES_TEST_REPO_ROOT="$REPO_ROOT" \
        DOTFILES_TEST_STATE="$FIXTURE_STATE" \
        "$REPO_ROOT/uninstall.sh" "$@" >"$FIXTURE_ROOT/uninstall.out" 2>&1
    then
        actual_status=0
    else
        actual_status=$?
    fi

    assert_eq "$expected_status" "$actual_status" "unexpected uninstall exit status"
}

count_zsh_backups() {
    local backup count=0
    for backup in "$FIXTURE_HOME"/.zshrc.bak.*; do
        [[ -e "$backup" || -L "$backup" ]] || continue
        count=$((count + 1))
        ZSH_BACKUP="$backup"
    done
    printf '%s\n' "$count"
}

assert_non_mise_links() {
    assert_symlink "$FIXTURE_HOME/.config/fish" "$REPO_ROOT/fish"
    assert_symlink "$FIXTURE_HOME/.config/herdr/config.toml" "$REPO_ROOT/herdr/config.toml"
    assert_symlink "$FIXTURE_HOME/.config/hunk/config.toml" "$REPO_ROOT/hunk/config.toml"
    assert_symlink "$FIXTURE_HOME/.config/lazygit" "$REPO_ROOT/lazygit"
    assert_symlink "$FIXTURE_HOME/.config/nvim" "$REPO_ROOT/nvim"
    assert_symlink "$FIXTURE_HOME/.config/tmux" "$REPO_ROOT/tmux"
    assert_symlink "$FIXTURE_HOME/.zshrc" "$REPO_ROOT/zsh/.zshrc"
    assert_exists "$FIXTURE_HOME/.local/share/dotfiles/local.fish"
    assert_exists "$FIXTURE_HOME/.local/share/dotfiles/local.zsh"
}

assert_common_links() {
    assert_non_mise_links
    assert_symlink "$FIXTURE_HOME/.config/mise/conf.d/00-dotfiles.toml" "$REPO_ROOT/mise/conf.d/00-dotfiles.toml"
}

assert_common_links_removed() {
    assert_not_exists "$FIXTURE_HOME/.config/fish"
    assert_not_exists "$FIXTURE_HOME/.config/herdr/config.toml"
    assert_not_exists "$FIXTURE_HOME/.config/hunk/config.toml"
    assert_not_exists "$FIXTURE_HOME/.config/mise/conf.d/00-dotfiles.toml"
    assert_not_exists "$FIXTURE_HOME/.config/nvim"
    assert_not_exists "$FIXTURE_HOME/.config/tmux"
    assert_not_exists "$FIXTURE_HOME/.zshrc"
}

assert_devflow_installed() {
    local executable
    local tool_environment="$FIXTURE_HOME/.local/share/dotfiles/uv-tools/dotfiles-devflow"
    local receipt="$FIXTURE_HOME/.local/share/dotfiles/devflow-tool.receipt"
    local expected_uv_receipt="$FIXTURE_STATE/expected-uv-receipt.toml"

    assert_exists "$tool_environment"
    for executable in devflow devflow-reference-transaction devflow-pre-push; do
        assert_symlink \
            "$FIXTURE_HOME/.local/bin/$executable" \
            "$tool_environment/bin/$executable"
    done
    grep -Fxq 'dotfiles-devflow-v1' "$receipt" ||
        fail "Workflow Engine receipt has an unexpected format"
    grep -Fxq "$REPO_ROOT/devflow" "$receipt" ||
        fail "Workflow Engine receipt did not record its editable source"
    grep -Fxq "$FIXTURE_FAKE_BIN/python" "$receipt" ||
        fail "Workflow Engine receipt did not record Mise's exact Python"
    assert_symlink \
        "$tool_environment/bin/python" \
        "$FIXTURE_FAKE_BIN/python"
    grep -Fxq "$REPO_ROOT/devflow/src" \
        "$tool_environment/lib/python3.14/site-packages/dotfiles_devflow.pth" ||
        fail "Workflow Engine environment did not record its editable source"
    write_devflow_uv_receipt_fixture "$expected_uv_receipt"
    assert_file_bytes_equal \
        "$expected_uv_receipt" "$tool_environment/uv-receipt.toml" \
        "Workflow Engine uv receipt did not match the exact owned inventory"
}

assert_devflow_not_installed() {
    local executable

    assert_not_exists \
        "$FIXTURE_HOME/.local/share/dotfiles/uv-tools/dotfiles-devflow"
    assert_not_exists \
        "$FIXTURE_HOME/.local/share/dotfiles/devflow-tool.receipt"
    for executable in devflow devflow-reference-transaction devflow-pre-push; do
        assert_not_exists "$FIXTURE_HOME/.local/bin/$executable"
    done
}

assert_devflow_receipt_status() {
    local expected="$1" actual

    IFS= read -r actual \
        <"$FIXTURE_HOME/.local/share/dotfiles/devflow-tool.receipt"
    assert_eq "$expected" "$actual" "unexpected Workflow Engine receipt status"
}

write_devflow_uv_receipt_fixture() {
    local destination="$1" inventory="${2:-exact}"
    local receipt_python="$FIXTURE_FAKE_BIN/python"
    local requirement_source="$REPO_ROOT/devflow"

    if [[ "$inventory" == "reformatted" ]]; then
        printf '%s\n' \
            '# Equivalent uv metadata with deliberately different TOML syntax.' \
            '[tool]' \
            "python = '$FIXTURE_FAKE_BIN/python' # pinned interpreter" \
            'entrypoints = [' \
            "  { from = 'dotfiles-devflow', name = 'devflow-reference-transaction', install-path = '$FIXTURE_HOME/.local/bin/devflow-reference-transaction' }," \
            "  { install-path = '$FIXTURE_HOME/.local/bin/devflow', from = 'dotfiles-devflow', name = 'devflow' }," \
            "  { name = 'devflow-pre-push', from = 'dotfiles-devflow', install-path = '$FIXTURE_HOME/.local/bin/devflow-pre-push' }," \
            ']' \
            'requirements = [' \
            "  { editable = '$REPO_ROOT/devflow', name = 'dotfiles-devflow' }," \
            ']' \
            >"$destination"
        return
    fi

    if [[ "$inventory" == "wrong-python" ]]; then
        receipt_python="$FIXTURE_ROOT/another-python"
    fi
    if [[ "$inventory" == "wrong-source" ]]; then
        requirement_source="$FIXTURE_ROOT/another-source"
    fi

    printf '%s\n' '[tool]' >"$destination"
    case "$inventory" in
        exact|extra-entrypoint|duplicate-entrypoint|wrong-python|wrong-source)
            printf '%s\n' \
                "requirements = [{ name = \"dotfiles-devflow\", editable = \"$requirement_source\" }]" \
                >>"$destination"
            ;;
        extra-requirement)
            printf '%s\n' \
                'requirements = [' \
                "    { name = \"dotfiles-devflow\", editable = \"$REPO_ROOT/devflow\" }," \
                '    { name = "injected-package" },' \
                ']' \
                >>"$destination"
            ;;
        duplicate-requirement)
            printf '%s\n' \
                'requirements = [' \
                "    { name = \"dotfiles-devflow\", editable = \"$REPO_ROOT/devflow\" }," \
                "    { name = \"dotfiles-devflow\", editable = \"$REPO_ROOT/devflow\" }," \
                ']' \
                >>"$destination"
            ;;
        *)
            fail "unknown uv receipt inventory fixture: $inventory"
            ;;
    esac
    printf '%s\n' \
        "python = \"$receipt_python\"" \
        'entrypoints = [' \
        "    { name = \"devflow\", install-path = \"$FIXTURE_HOME/.local/bin/devflow\", from = \"dotfiles-devflow\" }," \
        "    { name = \"devflow-pre-push\", install-path = \"$FIXTURE_HOME/.local/bin/devflow-pre-push\", from = \"dotfiles-devflow\" }," \
        "    { name = \"devflow-reference-transaction\", install-path = \"$FIXTURE_HOME/.local/bin/devflow-reference-transaction\", from = \"dotfiles-devflow\" }," \
        >>"$destination"
    if [[ "$inventory" == "extra-entrypoint" ]]; then
        printf '%s\n' \
            "    { name = \"unexpected-devflow-command\", install-path = \"$FIXTURE_HOME/.local/bin/unexpected-devflow-command\", from = \"dotfiles-devflow\" }," \
            >>"$destination"
    fi
    if [[ "$inventory" == "duplicate-entrypoint" ]]; then
        printf '%s\n' \
            "    { name = \"devflow\", install-path = \"$FIXTURE_HOME/.local/bin/devflow\", from = \"dotfiles-devflow\" }," \
            >>"$destination"
    fi
    printf '%s\n' ']' >>"$destination"
}

assert_file_bytes_equal() {
    local expected="$1" actual="$2" message="$3"

    cmp -s "$expected" "$actual" || fail "$message"
}

add_injected_devflow_inventory_artifact() {
    local inventory="$1" tool_environment="$2"

    case "$inventory" in
        extra-requirement)
            mkdir -p \
                "$tool_environment/lib/python3.14/site-packages/injected_package"
            printf 'injected package data\nwith exact bytes\n' \
                >"$tool_environment/lib/python3.14/site-packages/injected_package/marker"
            ;;
        extra-entrypoint)
            cp "$FIXTURE_GENERIC_TEMPLATE" \
                "$tool_environment/bin/unexpected-devflow-command"
            chmod +x "$tool_environment/bin/unexpected-devflow-command"
            ln -s "$tool_environment/bin/unexpected-devflow-command" \
                "$FIXTURE_HOME/.local/bin/unexpected-devflow-command"
            ;;
    esac
}

assert_injected_devflow_inventory_artifact() {
    local inventory="$1" tool_environment="$2"

    case "$inventory" in
        extra-requirement)
            grep -Fxq 'injected package data' \
                "$tool_environment/lib/python3.14/site-packages/injected_package/marker" ||
                fail "ambiguous injected package data was changed"
            grep -Fxq 'with exact bytes' \
                "$tool_environment/lib/python3.14/site-packages/injected_package/marker" ||
                fail "ambiguous injected package bytes were changed"
            ;;
        extra-entrypoint)
            assert_symlink \
                "$FIXTURE_HOME/.local/bin/unexpected-devflow-command" \
                "$tool_environment/bin/unexpected-devflow-command"
            cmp -s \
                "$FIXTURE_GENERIC_TEMPLATE" \
                "$tool_environment/bin/unexpected-devflow-command" ||
                fail "ambiguous extra entrypoint bytes were changed"
            ;;
    esac
}

test_macos_fresh_and_second_run() {
    new_fixture macos Darwin
    printf 'original zsh config\n' >"$FIXTURE_HOME/.zshrc"

    run_installer

    assert_common_links
    assert_devflow_installed
    assert_not_exists "$FIXTURE_HOME/.codex"
    assert_not_exists "$FIXTURE_HOME/.claude"
    assert_symlink "$FIXTURE_HOME/.config/ghostty" "$REPO_ROOT/ghostty"
    assert_eq "1" "$(count_zsh_backups)" "the original zsh config should be backed up exactly once"
    for ZSH_BACKUP in "$FIXTURE_HOME"/.zshrc.bak.*; do
        [[ -e "$ZSH_BACKUP" || -L "$ZSH_BACKUP" ]] && break
    done
    grep -Fxq 'original zsh config' "$ZSH_BACKUP" || fail "zsh backup did not preserve its original content"
    assert_log_count 1 "brew bootstrap" "$FIXTURE_LOG"
    assert_log_count 1 "brew bundle install" "$FIXTURE_LOG"
    assert_log_count 1 "brew cask install ghostty" "$FIXTURE_LOG"
    assert_log_count 1 "brew cask install font-jetbrains-mono" "$FIXTURE_LOG"
    assert_log_count 1 "mise install" "$FIXTURE_LOG"
    assert_log_prefix_count 1 "uv tool install|" "$FIXTURE_LOG"
    assert_log_count 0 "apt-get update" "$FIXTURE_LOG"

    run_installer

    assert_log_count 1 "brew bootstrap" "$FIXTURE_LOG"
    assert_log_count 1 "brew bundle install" "$FIXTURE_LOG"
    assert_log_count 1 "brew cask install ghostty" "$FIXTURE_LOG"
    assert_log_count 1 "brew cask install font-jetbrains-mono" "$FIXTURE_LOG"
    assert_log_count 1 "mise install" "$FIXTURE_LOG"
    assert_log_prefix_count 1 "uv tool install|" "$FIXTURE_LOG"
    assert_log_prefix_count 0 "apt-get " "$FIXTURE_LOG"
    assert_eq "1" "$(count_zsh_backups)" "a second run should not create another zsh backup"
    assert_common_links
    assert_devflow_installed
    pass "fresh macOS provisioning, non-destructive linking, and second-run no-op"
}

assert_linux_native_install_once() {
    local manager="$1"

    case "$manager" in
        apt-get)
            assert_log_count 1 "apt-get update" "$FIXTURE_LOG"
            assert_log_count 1 \
                "apt-get install -y build-essential procps curl file git tar gzip unzip diffutils ca-certificates" \
                "$FIXTURE_LOG"
            ;;
        dnf)
            assert_log_count 1 "dnf group install -y development-tools" "$FIXTURE_LOG"
            assert_log_count 1 "dnf group install -y Development Tools" "$FIXTURE_LOG"
            assert_log_count 1 \
                "dnf install -y procps-ng curl file git tar gzip unzip diffutils ca-certificates" \
                "$FIXTURE_LOG"
            ;;
        yum)
            assert_log_count 1 "yum groupinstall -y Development Tools" "$FIXTURE_LOG"
            assert_log_count 1 \
                "yum install -y procps-ng curl file git tar gzip unzip diffutils ca-certificates" \
                "$FIXTURE_LOG"
            ;;
        pacman)
            assert_log_count 1 \
                "pacman -S --needed --noconfirm base-devel procps-ng curl file git tar gzip unzip diffutils ca-certificates" \
                "$FIXTURE_LOG"
            ;;
    esac
}

test_linux_manager_fresh_and_second_run() {
    local manager="$1"
    new_fixture "linux-$manager" Linux "$manager"

    run_installer

    assert_common_links
    assert_not_exists "$FIXTURE_HOME/.config/ghostty"
    assert_linux_native_install_once "$manager"
    assert_log_count 1 "brew bootstrap" "$FIXTURE_LOG"
    assert_log_count 1 "brew bundle install" "$FIXTURE_LOG"
    assert_log_count 1 "mise install" "$FIXTURE_LOG"
    assert_log_count 0 "brew cask install ghostty" "$FIXTURE_LOG"
    assert_log_count 0 "brew cask install font-jetbrains-mono" "$FIXTURE_LOG"
    assert_exists "$FIXTURE_FAKE_BIN/wl-copy"
    assert_exists "$FIXTURE_FAKE_BIN/xclip"
    grep -Fq "exec \"$FIXTURE_FAKE_BIN/fish\" -l" "$FIXTURE_OUTPUT" ||
        fail "Linux install did not print an executable Fish handoff"
    HOME="$FIXTURE_HOME" DOTFILES_TEST_LOG="$FIXTURE_LOG" \
        "$FIXTURE_FAKE_BIN/fish" -l
    assert_log_count 1 "fish login environment ready" "$FIXTURE_LOG"

    run_installer

    assert_linux_native_install_once "$manager"
    assert_log_count 1 "brew bootstrap" "$FIXTURE_LOG"
    assert_log_count 1 "brew bundle install" "$FIXTURE_LOG"
    assert_log_count 1 "mise install" "$FIXTURE_LOG"
    assert_log_count 1 "fish login environment ready" "$FIXTURE_LOG"
    assert_log_count 0 "brew cask install ghostty" "$FIXTURE_LOG"
    assert_log_count 0 "brew cask install font-jetbrains-mono" "$FIXTURE_LOG"
    assert_common_links
    pass "fresh Linux/$manager provisioning and second-run no-op"
}

test_unsupported_linux_package_manager() {
    new_fixture unsupported-linux Linux
    mv "$FIXTURE_FAKE_BIN/apt-get" "$FIXTURE_STATE/apt-get.disabled"

    run_installer failure

    grep -Fq 'unsupported Linux package manager' "$FIXTURE_OUTPUT" ||
        fail "unsupported Linux manager failure was not actionable"
    assert_log_count 0 "brew bootstrap" "$FIXTURE_LOG"
    assert_not_exists "$FIXTURE_HOME/.config"
    pass "unsupported Linux package managers fail before mutations"
}

test_linux_handoff_is_validated_before_linking() {
    new_fixture invalid-linux-handoff Linux apt-get
    FIXTURE_BREW_PREFIX="$FIXTURE_ROOT/unusable-brew"
    printf 'original zsh config\n' >"$FIXTURE_HOME/.zshrc"

    run_installer failure

    grep -Fq 'Fish is installed, but its executable was not found' "$FIXTURE_OUTPUT" ||
        fail "invalid Linux Fish handoff failure was not actionable"
    grep -Fxq 'original zsh config' "$FIXTURE_HOME/.zshrc" ||
        fail "Fish handoff validation changed zsh config"
    assert_not_exists "$FIXTURE_HOME/.config"
    assert_not_exists "$FIXTURE_HOME/.local"
    pass "Linux Fish handoff is validated before configuration mutations"
}

test_non_corretto_jdk_is_rejected_before_linking() {
    new_fixture non-corretto-jdk Darwin
    : >"$FIXTURE_STATE/non-corretto-java"

    run_installer failure

    grep -Fq 'Amazon Corretto JDK 21 is required' "$FIXTURE_OUTPUT" ||
        fail "non-Corretto JDK failure was not actionable"
    assert_not_exists "$FIXTURE_HOME/.config"
    pass "non-Corretto JDKs are rejected before configuration mutations"
}

test_incompatible_git_tool_versions_are_rejected_before_linking() {
    new_fixture incompatible-git-tool-versions Darwin
    : >"$FIXTURE_STATE/old-lazygit"
    : >"$FIXTURE_STATE/old-hunk"

    run_installer failure

    grep -Fq 'LazyGit 0.56+ is required' "$FIXTURE_OUTPUT" ||
        fail "old LazyGit failure was not actionable"
    grep -Fq 'Hunk 0.18.1+ is required' "$FIXTURE_OUTPUT" ||
        fail "old Hunk failure was not actionable"
    assert_not_exists "$FIXTURE_HOME/.config"
    pass "Git tools below the configured integration floors are rejected before linking"
}

test_incompatible_neovim_versions_are_rejected_before_linking() {
    local found fixture_name

    for found in 'NVIM v0.12.4' 'NVIM v0.12.6' 'NVIM v0.12.5-dev'; do
        fixture_name="incompatible-neovim-${found#NVIM v}"
        new_fixture "$fixture_name" Darwin
        printf '%s\n' "$found" >"$FIXTURE_STATE/nvim-version"

        run_installer failure

        grep -Fq "stable Neovim 0.12.5 is required (found '$found')" "$FIXTURE_OUTPUT" ||
            fail "unsupported Neovim version failure was not actionable: $found"
        assert_not_exists "$FIXTURE_HOME/.config"
    done

    pass "Neovim versions outside the exact stable pin are rejected before linking"
}

test_user_mise_config_does_not_override_bootstrap_manifest() {
    new_fixture mise-user-override Darwin
    mkdir -p "$FIXTURE_HOME/.config/mise"
    printf '[tools]\njava = "21"\n' >"$FIXTURE_HOME/.config/mise/config.toml"

    run_installer

    grep -Fxq 'java = "21"' "$FIXTURE_HOME/.config/mise/config.toml" ||
        fail "installer changed the user's main Mise config"
    assert_symlink \
        "$FIXTURE_HOME/.config/mise/conf.d/00-dotfiles.toml" \
        "$REPO_ROOT/mise/conf.d/00-dotfiles.toml"
    pass "user Mise config cannot override bootstrap runtime provisioning"
}

test_mise_environment_cannot_override_bootstrap_manifest() {
    new_fixture mise-environment-override Darwin

    (
        export MISE_CONFIG_FILE="$FIXTURE_ROOT/foreign-config.toml"
        export MISE_GLOBAL_CONFIG_FILE="$FIXTURE_ROOT/foreign-global.toml"
        export MISE_GLOBAL_CONFIG_ROOT="$FIXTURE_ROOT/foreign-root"
        export MISE_IGNORED_CONFIG_PATHS="$REPO_ROOT/mise/conf.d/00-dotfiles.toml"
        export MISE_NO_CONFIG=1
        export MISE_DISABLE_TOOLS=java
        export MISE_NODE_VERSION=18
        export MISE_PYTHON_VERSION=3.10
        export MISE_RUST_VERSION=1.93.0
        export MISE_JAVA_VERSION=21
        run_installer
    )

    assert_common_links
    pass "Mise environment cannot override bootstrap runtime provisioning"
}

test_non_mise_runtime_command_is_rejected_before_linking() {
    new_fixture non-mise-runtime-command Darwin
    : >"$FIXTURE_STATE/mise-which-mismatch"

    run_installer failure

    grep -Fq 'Mise activation did not select configured runtime commands' "$FIXTURE_OUTPUT" ||
        fail "runtime command mismatch failure was not actionable"
    assert_not_exists "$FIXTURE_HOME/.config"
    pass "runtime commands outside the configured Mise toolset are rejected before linking"
}

test_mise_runtime_version_mismatch_is_rejected_before_linking() {
    new_fixture mise-runtime-version-mismatch Darwin
    : >"$FIXTURE_STATE/mise-version-mismatch"

    run_installer failure

    grep -Fq 'Mise runtime versions do not match the tracked manifest' "$FIXTURE_OUTPUT" ||
        fail "runtime version mismatch failure was not actionable"
    assert_not_exists "$FIXTURE_HOME/.config"
    pass "runtime versions outside the tracked Mise manifest are rejected before linking"
}

test_install_cli_is_safe() {
    new_fixture install-cli Darwin

    run_installer success --help
    grep -Fq 'Usage:' "$FIXTURE_OUTPUT" ||
        fail "install help did not print usage"
    assert_log_count 0 "brew bootstrap" "$FIXTURE_LOG"
    assert_not_exists "$FIXTURE_HOME/.config"

    run_installer failure --definitely-not-an-option
    grep -Fq 'Usage:' "$FIXTURE_OUTPUT" ||
        fail "invalid install option did not print usage"
    assert_log_count 0 "brew bootstrap" "$FIXTURE_LOG"
    assert_not_exists "$FIXTURE_HOME/.config"
    pass "install help and invalid options do not mutate configuration"
}

test_skip_mise_runtimes_completes_yum_setup() {
    new_fixture skip-mise-yum Linux yum
    mkdir -p "$FIXTURE_HOME/.config/mise"
    printf 'user mise config\n' >"$FIXTURE_HOME/.config/mise/config.toml"

    run_installer success --skip-mise-runtimes

    assert_non_mise_links
    assert_devflow_not_installed
    assert_not_exists "$FIXTURE_HOME/.config/mise/conf.d/00-dotfiles.toml"
    grep -Fxq 'user mise config' "$FIXTURE_HOME/.config/mise/config.toml" ||
        fail "skip mode changed the user's main Mise config"
    assert_linux_native_install_once yum
    assert_log_count 0 "mise dry-run" "$FIXTURE_LOG"
    assert_log_count 0 "mise install" "$FIXTURE_LOG"
    assert_log_count 0 "mise activate" "$FIXTURE_LOG"
    assert_log_prefix_count 0 "uv tool install|" "$FIXTURE_LOG"
    grep -Fq 'Mise runtime installation and validation skipped by request.' "$FIXTURE_OUTPUT" ||
        fail "skip mode did not report its degraded runtime state"
    grep -Fq 'Dotfiles installation complete with Mise runtime provisioning skipped.' "$FIXTURE_OUTPUT" ||
        fail "skip mode did not report degraded completion"

    run_installer success --skip-mise-runtimes

    assert_non_mise_links
    assert_devflow_not_installed
    assert_not_exists "$FIXTURE_HOME/.config/mise/conf.d/00-dotfiles.toml"
    assert_linux_native_install_once yum
    assert_log_count 0 "mise dry-run" "$FIXTURE_LOG"
    assert_log_count 0 "mise install" "$FIXTURE_LOG"
    assert_log_count 0 "mise activate" "$FIXTURE_LOG"
    assert_log_prefix_count 0 "uv tool install|" "$FIXTURE_LOG"
    pass "yum setup can skip Mise runtimes and remains idempotent"
}

test_skip_mise_runtimes_retains_existing_manifest() {
    new_fixture skip-mise-existing Darwin
    run_installer

    run_installer success --skip-mise-runtimes

    assert_common_links
    assert_devflow_installed
    assert_log_count 1 "mise install" "$FIXTURE_LOG"
    assert_log_prefix_count 1 "uv tool install|" "$FIXTURE_LOG"
    pass "skip mode retains an existing managed Mise fragment"
}

test_skip_mise_runtimes_preserves_foreign_devflow_state() {
    local executable marker receipt

    new_fixture skip-mise-foreign-devflow Darwin
    marker="$FIXTURE_HOME/.local/share/dotfiles/uv-tools/dotfiles-devflow/marker"
    receipt="$FIXTURE_HOME/.local/share/dotfiles/devflow-tool.receipt"
    mkdir -p \
        "$FIXTURE_HOME/.local/bin" \
        "$(dirname "$marker")"
    printf 'foreign private environment\nwith exact bytes\n' >"$marker"
    printf 'not a dotfiles receipt\n' >"$receipt"
    for executable in devflow devflow-reference-transaction devflow-pre-push; do
        printf 'foreign %s\nwith exact bytes\n' "$executable" \
            >"$FIXTURE_HOME/.local/bin/$executable"
    done

    run_installer success --skip-mise-runtimes

    assert_non_mise_links
    grep -Fxq 'foreign private environment' "$marker" ||
        fail "skip mode changed a foreign Workflow Engine environment"
    grep -Fxq 'with exact bytes' "$marker" ||
        fail "skip mode changed bytes in a foreign Workflow Engine environment"
    grep -Fxq 'not a dotfiles receipt' "$receipt" ||
        fail "skip mode changed a foreign Workflow Engine receipt"
    for executable in devflow devflow-reference-transaction devflow-pre-push; do
        grep -Fxq "foreign $executable" \
            "$FIXTURE_HOME/.local/bin/$executable" ||
            fail "skip mode changed a foreign Workflow Engine executable"
        grep -Fxq 'with exact bytes' "$FIXTURE_HOME/.local/bin/$executable" ||
            fail "skip mode changed bytes in a foreign Workflow Engine executable"
    done
    assert_log_prefix_count 0 "uv tool install|" "$FIXTURE_LOG"
    assert_log_prefix_count 0 "uv tool uninstall|" "$FIXTURE_LOG"
    pass "skip mode preserves foreign Workflow Engine state without validation"
}

test_devflow_install_failure_precedes_configuration_links() {
    new_fixture devflow-install-failure Darwin
    : >"$FIXTURE_STATE/uv-install-failure"

    run_installer failure

    assert_log_prefix_count 1 "uv tool install|" "$FIXTURE_LOG"
    assert_devflow_receipt_status 'dotfiles-devflow-pending-v1'
    assert_not_exists \
        "$FIXTURE_HOME/.local/share/dotfiles/uv-tools/dotfiles-devflow"
    assert_not_exists "$FIXTURE_HOME/.config"
    grep -Fq 'Installing Workflow Engine' "$FIXTURE_OUTPUT" ||
        fail "Workflow Engine install failure did not identify its phase"

    mv "$FIXTURE_STATE/uv-install-failure" \
        "$FIXTURE_STATE/uv-install-failure.consumed"
    run_installer

    assert_devflow_installed
    assert_common_links
    assert_log_prefix_count 2 "uv tool install|" "$FIXTURE_LOG"
    pass "empty pending Workflow Engine installation retries before linking"
}

test_devflow_resumes_after_uv_interruption() {
    new_fixture devflow-uv-interruption Darwin
    : >"$FIXTURE_STATE/uv-interrupt-after-install"

    run_installer failure

    assert_devflow_receipt_status 'dotfiles-devflow-pending-v1'
    assert_exists \
        "$FIXTURE_HOME/.local/share/dotfiles/uv-tools/dotfiles-devflow"
    assert_not_exists "$FIXTURE_HOME/.config"
    assert_log_prefix_count 1 "uv tool install|" "$FIXTURE_LOG"

    run_installer

    assert_devflow_installed
    assert_common_links
    assert_log_prefix_count 1 "uv tool install|" "$FIXTURE_LOG"
    pass "complete pending Workflow Engine install resumes without reinstalling"
}

test_devflow_resumes_after_finalization_interruption() {
    new_fixture devflow-finalization-interruption Darwin
    printf 'interrupt\n' \
        >"$FIXTURE_STATE/receipt-finalize-interruption"

    run_installer failure

    assert_devflow_receipt_status 'dotfiles-devflow-pending-v1'
    assert_exists \
        "$FIXTURE_HOME/.local/share/dotfiles/uv-tools/dotfiles-devflow"
    assert_not_exists "$FIXTURE_HOME/.config"
    assert_log_prefix_count 1 "uv tool install|" "$FIXTURE_LOG"

    run_installer

    assert_devflow_installed
    assert_common_links
    assert_log_prefix_count 1 "uv tool install|" "$FIXTURE_LOG"
    pass "post-validation interruption finalizes without reinstalling"
}

test_devflow_preflight_preserves_foreign_state() {
    new_fixture foreign-devflow-executable Darwin
    mkdir -p "$FIXTURE_HOME/.local/bin"
    printf 'user-owned devflow\n' >"$FIXTURE_HOME/.local/bin/devflow"

    run_installer failure

    grep -Fxq 'user-owned devflow' "$FIXTURE_HOME/.local/bin/devflow" ||
        fail "installer changed a foreign devflow executable"
    grep -Fq 'no dotfiles ownership receipt' "$FIXTURE_OUTPUT" ||
        fail "foreign devflow executable failure was not actionable"
    assert_log_count 0 "brew bootstrap" "$FIXTURE_LOG"
    assert_not_exists "$FIXTURE_HOME/.config"

    new_fixture foreign-devflow-environment Darwin
    mkdir -p \
        "$FIXTURE_HOME/.local/share/dotfiles/uv-tools/dotfiles-devflow"
    printf 'user-owned environment\n' \
        >"$FIXTURE_HOME/.local/share/dotfiles/uv-tools/dotfiles-devflow/marker"

    run_installer failure

    grep -Fxq 'user-owned environment' \
        "$FIXTURE_HOME/.local/share/dotfiles/uv-tools/dotfiles-devflow/marker" ||
        fail "installer changed a foreign private tool environment"
    assert_log_count 0 "brew bootstrap" "$FIXTURE_LOG"
    assert_not_exists "$FIXTURE_HOME/.config"

    new_fixture foreign-devflow-receipt Darwin
    mkdir -p "$FIXTURE_HOME/.local/share/dotfiles"
    printf '%s\n%s\n%s\n' \
        'dotfiles-devflow-v1' \
        "$FIXTURE_ROOT/another-repository/devflow" \
        "$FIXTURE_FAKE_BIN/python" \
        >"$FIXTURE_HOME/.local/share/dotfiles/devflow-tool.receipt"

    run_installer failure

    grep -Fq 'belongs to a different source' "$FIXTURE_OUTPUT" ||
        fail "foreign Workflow Engine receipt failure was not actionable"
    assert_log_count 0 "brew bootstrap" "$FIXTURE_LOG"
    assert_not_exists "$FIXTURE_HOME/.config"

    new_fixture partial-pending-devflow Darwin
    mkdir -p \
        "$FIXTURE_HOME/.local/bin" \
        "$FIXTURE_HOME/.local/share/dotfiles"
    printf '%s\n%s\n%s\n' \
        'dotfiles-devflow-pending-v1' \
        "$REPO_ROOT/devflow" \
        "$FIXTURE_FAKE_BIN/python" \
        >"$FIXTURE_HOME/.local/share/dotfiles/devflow-tool.receipt"
    printf 'partial pending executable\n' \
        >"$FIXTURE_HOME/.local/bin/devflow"

    run_installer failure

    grep -Fxq 'partial pending executable' \
        "$FIXTURE_HOME/.local/bin/devflow" ||
        fail "installer changed a partial pending Workflow Engine install"
    assert_devflow_receipt_status 'dotfiles-devflow-pending-v1'
    assert_log_count 0 "brew bootstrap" "$FIXTURE_LOG"
    assert_log_prefix_count 0 "uv tool install|" "$FIXTURE_LOG"
    assert_not_exists "$FIXTURE_HOME/.config"
    pass "Workflow Engine preflight preserves foreign executables and environments"
}

test_devflow_receipt_requires_the_exact_python() {
    new_fixture devflow-python-receipt Darwin
    run_installer
    printf '%s\n%s\n%s\n' \
        'dotfiles-devflow-v1' \
        "$REPO_ROOT/devflow" \
        "$FIXTURE_ROOT/another-python" \
        >"$FIXTURE_HOME/.local/share/dotfiles/devflow-tool.receipt"

    run_installer failure

    grep -Fq 'environment does not match its ownership receipt' \
        "$FIXTURE_OUTPUT" ||
        fail "Workflow Engine Python receipt mismatch was not actionable"
    assert_log_prefix_count 1 "uv tool install|" "$FIXTURE_LOG"
    assert_exists \
        "$FIXTURE_HOME/.local/share/dotfiles/uv-tools/dotfiles-devflow"
    pass "Workflow Engine idempotence requires the exact receipted Python"
}

test_devflow_noop_rejects_a_replaced_environment() {
    local tool_environment

    new_fixture devflow-replaced-environment Darwin
    run_installer
    tool_environment="$FIXTURE_HOME/.local/share/dotfiles/uv-tools/dotfiles-devflow"
    mv "$tool_environment/bin/python" "$FIXTURE_STATE/owned-python-link"
    cp "$FIXTURE_GENERIC_TEMPLATE" "$FIXTURE_STATE/replacement-python"
    chmod +x "$FIXTURE_STATE/replacement-python"
    ln -s "$FIXTURE_STATE/replacement-python" "$tool_environment/bin/python"
    printf '%s\n' "$FIXTURE_ROOT/replacement-source" \
        >"$tool_environment/lib/python3.14/site-packages/dotfiles_devflow.pth"

    run_installer failure

    grep -Fq 'environment does not match its ownership receipt' \
        "$FIXTURE_OUTPUT" ||
        fail "replaced Workflow Engine environment failure was not actionable"
    assert_log_prefix_count 1 "uv tool install|" "$FIXTURE_LOG"
    assert_exists "$tool_environment"
    pass "Workflow Engine no-op rejects a replaced environment"
}

test_devflow_accepts_uvs_unterminated_editable_source_marker() {
    local expected_source_marker source_marker tool_environment

    new_fixture devflow-unterminated-source-marker Darwin
    run_installer
    tool_environment="$FIXTURE_HOME/.local/share/dotfiles/uv-tools/dotfiles-devflow"
    source_marker="$tool_environment/lib/python3.14/site-packages/dotfiles_devflow.pth"
    expected_source_marker="$FIXTURE_STATE/expected-dotfiles-devflow.pth"
    printf '%s' "$REPO_ROOT/devflow/src" >"$expected_source_marker"
    assert_file_bytes_equal \
        "$expected_source_marker" "$source_marker" \
        "fake uv did not mirror its unterminated editable source marker"

    run_installer

    assert_log_prefix_count 1 "uv tool install|" "$FIXTURE_LOG"
    run_uninstaller 0
    assert_devflow_not_installed
    assert_log_prefix_count 1 "uv tool uninstall|" "$FIXTURE_LOG"
    pass "uv's unterminated editable source marker remains owned"
}

test_devflow_rejects_an_ambiguous_editable_source_marker() {
    local snapshot source_marker tool_environment

    new_fixture devflow-ambiguous-source-marker Darwin
    run_installer
    tool_environment="$FIXTURE_HOME/.local/share/dotfiles/uv-tools/dotfiles-devflow"
    source_marker="$tool_environment/lib/python3.14/site-packages/dotfiles_devflow.pth"
    snapshot="$FIXTURE_STATE/ambiguous-dotfiles-devflow.pth"
    printf '%s\n%s' \
        "$REPO_ROOT/devflow/src" \
        "$FIXTURE_ROOT/injected-source" \
        >"$source_marker"
    cp "$source_marker" "$snapshot"

    run_installer failure

    grep -Fq 'environment does not match its ownership receipt' \
        "$FIXTURE_OUTPUT" ||
        fail "ambiguous editable source marker failure was not actionable"
    assert_file_bytes_equal \
        "$snapshot" "$source_marker" \
        "installer changed an ambiguous editable source marker"
    assert_log_prefix_count 1 "uv tool install|" "$FIXTURE_LOG"

    run_uninstaller 0

    grep -Fq 'ownership unclear: dotfiles-devflow (preserving)' \
        "$FIXTURE_ROOT/uninstall.out" ||
        fail "uninstall did not report an ambiguous editable source marker"
    assert_file_bytes_equal \
        "$snapshot" "$source_marker" \
        "uninstaller changed an ambiguous editable source marker"
    assert_exists "$tool_environment"
    assert_exists \
        "$FIXTURE_HOME/.local/share/dotfiles/devflow-tool.receipt"
    assert_log_prefix_count 0 "uv tool uninstall|" "$FIXTURE_LOG"
    pass "ambiguous editable source markers remain preserved"
}

test_devflow_uv_receipt_inventory_is_exact() {
    local executable inventory snapshot tool_environment uv_receipt

    for inventory in \
        extra-requirement \
        extra-entrypoint \
        duplicate-requirement \
        duplicate-entrypoint \
        wrong-python \
        wrong-source
    do
        new_fixture "devflow-uv-receipt-$inventory" Darwin
        run_installer
        tool_environment="$FIXTURE_HOME/.local/share/dotfiles/uv-tools/dotfiles-devflow"
        uv_receipt="$tool_environment/uv-receipt.toml"
        snapshot="$FIXTURE_STATE/injected-uv-receipt.toml"
        write_devflow_uv_receipt_fixture "$uv_receipt" "$inventory"
        add_injected_devflow_inventory_artifact "$inventory" "$tool_environment"
        cp "$uv_receipt" "$snapshot"

        run_installer failure

        grep -Fq 'environment does not match its ownership receipt' \
            "$FIXTURE_OUTPUT" ||
            fail "$inventory uv receipt failure was not actionable"
        assert_file_bytes_equal \
            "$snapshot" "$uv_receipt" \
            "installer changed an ambiguous $inventory uv receipt"
        assert_exists "$tool_environment"
        assert_exists \
            "$FIXTURE_HOME/.local/share/dotfiles/devflow-tool.receipt"
        assert_injected_devflow_inventory_artifact \
            "$inventory" "$tool_environment"
        for executable in \
            devflow devflow-reference-transaction devflow-pre-push
        do
            assert_symlink \
                "$FIXTURE_HOME/.local/bin/$executable" \
                "$tool_environment/bin/$executable"
        done
        assert_log_prefix_count 1 "uv tool install|" "$FIXTURE_LOG"
        assert_log_prefix_count 0 "uv tool uninstall|" "$FIXTURE_LOG"

        run_uninstaller 0

        grep -Fq 'ownership unclear: dotfiles-devflow (preserving)' \
            "$FIXTURE_ROOT/uninstall.out" ||
            fail "uninstall did not report ambiguous $inventory inventory"
        assert_file_bytes_equal \
            "$snapshot" "$uv_receipt" \
            "uninstaller changed an ambiguous $inventory uv receipt"
        assert_exists "$tool_environment"
        assert_exists \
            "$FIXTURE_HOME/.local/share/dotfiles/devflow-tool.receipt"
        assert_injected_devflow_inventory_artifact \
            "$inventory" "$tool_environment"
        for executable in \
            devflow devflow-reference-transaction devflow-pre-push
        do
            assert_symlink \
                "$FIXTURE_HOME/.local/bin/$executable" \
                "$tool_environment/bin/$executable"
        done
        assert_log_prefix_count 1 "uv tool install|" "$FIXTURE_LOG"
        assert_log_prefix_count 0 "uv tool uninstall|" "$FIXTURE_LOG"
    done
    pass "exact uv inventory gates installer no-ops and owned uninstall"
}

test_devflow_uv_receipt_accepts_equivalent_toml() {
    local tool_environment uv_receipt

    new_fixture devflow-uv-receipt-reformatted Darwin
    run_installer
    tool_environment="$FIXTURE_HOME/.local/share/dotfiles/uv-tools/dotfiles-devflow"
    uv_receipt="$tool_environment/uv-receipt.toml"
    write_devflow_uv_receipt_fixture "$uv_receipt" reformatted

    run_installer

    assert_log_prefix_count 1 "uv tool install|" "$FIXTURE_LOG"
    assert_exists "$tool_environment"

    run_uninstaller 0

    assert_devflow_not_installed
    assert_log_prefix_count 1 "uv tool uninstall|" "$FIXTURE_LOG"
    pass "equivalent uv receipt TOML remains owned across install and uninstall"
}

test_devflow_uv_invocations_are_hermetic() {
    local hostile_config

    new_fixture devflow-uv-isolation Darwin
    hostile_config="$FIXTURE_HOME/.config/uv/uv.toml"
    mkdir -p "$(dirname "$hostile_config")"
    printf '%s\n' \
        'tool-dir = "/tmp/hostile-uv-tools"' \
        'tool-bin-dir = "/tmp/hostile-uv-bin"' \
        >"$hostile_config"
    printf 'test CA\n' >"$FIXTURE_STATE/test-ca.pem"
    : >"$FIXTURE_STATE/expect-uv-isolation"

    (
        export UV_CONFIG_FILE="$hostile_config"
        export UV_TOOL_DIR="$FIXTURE_ROOT/hostile-tools"
        export UV_TOOL_BIN_DIR="$FIXTURE_ROOT/hostile-bin"
        export UV_PROJECT_ENVIRONMENT="$FIXTURE_ROOT/hostile-project"
        export PYTHONHOME="$FIXTURE_ROOT/hostile-python-home"
        export PYTHONPATH="$FIXTURE_ROOT/hostile-python-path"
        export VIRTUAL_ENV="$FIXTURE_ROOT/hostile-venv"
        export CONDA_PREFIX="$FIXTURE_ROOT/hostile-conda"
        export PIP_INDEX_URL="https://packages.example/simple"
        export HTTP_PROXY="http://proxy.example:8080"
        export HTTPS_PROXY="https://proxy.example:8443"
        export NO_PROXY="localhost,127.0.0.1"
        export SSL_CERT_FILE="$FIXTURE_STATE/test-ca.pem"
        run_installer
    )

    assert_devflow_installed
    assert_not_exists "$FIXTURE_ROOT/hostile-tools"
    assert_not_exists "$FIXTURE_ROOT/hostile-bin"

    (
        export UV_CONFIG_FILE="$hostile_config"
        export UV_TOOL_DIR="$FIXTURE_ROOT/hostile-tools"
        export UV_TOOL_BIN_DIR="$FIXTURE_ROOT/hostile-bin"
        export UV_PROJECT_ENVIRONMENT="$FIXTURE_ROOT/hostile-project"
        export PYTHONHOME="$FIXTURE_ROOT/hostile-python-home"
        export PYTHONPATH="$FIXTURE_ROOT/hostile-python-path"
        export VIRTUAL_ENV="$FIXTURE_ROOT/hostile-venv"
        export CONDA_PREFIX="$FIXTURE_ROOT/hostile-conda"
        export PIP_INDEX_URL="https://packages.example/simple"
        export HTTP_PROXY="http://proxy.example:8080"
        export HTTPS_PROXY="https://proxy.example:8443"
        export NO_PROXY="localhost,127.0.0.1"
        export SSL_CERT_FILE="$FIXTURE_STATE/test-ca.pem"
        run_uninstaller 0
    )

    assert_devflow_not_installed
    assert_log_prefix_count 1 "uv tool install|" "$FIXTURE_LOG"
    assert_log_prefix_count 1 "uv tool uninstall|" "$FIXTURE_LOG"
    pass "uv tool changes ignore inherited resolver state but preserve networking"
}

test_generic_install_preserves_harness_configuration() {
    new_fixture preserve-harness-configuration Darwin
    mkdir -p "$FIXTURE_HOME/.codex" "$FIXTURE_HOME/.claude"
    printf 'user Codex guidance\n' >"$FIXTURE_HOME/.codex/AGENTS.md"
    printf 'user Claude guidance\n' >"$FIXTURE_HOME/.claude/CLAUDE.md"

    run_installer

    grep -Fxq 'user Codex guidance' "$FIXTURE_HOME/.codex/AGENTS.md" ||
        fail "generic install changed Codex harness guidance"
    grep -Fxq 'user Claude guidance' "$FIXTURE_HOME/.claude/CLAUDE.md" ||
        fail "generic install changed Claude harness guidance"

    run_installer success --skip-mise-runtimes

    grep -Fxq 'user Codex guidance' "$FIXTURE_HOME/.codex/AGENTS.md" ||
        fail "skip mode changed Codex harness guidance"
    grep -Fxq 'user Claude guidance' "$FIXTURE_HOME/.claude/CLAUDE.md" ||
        fail "skip mode changed Claude harness guidance"
    pass "generic installs leave harness-global configuration explicit"
}

test_uninstall_removes_only_owned_devflow() {
    local executable tool_environment

    new_fixture uninstall-owned-devflow Darwin
    run_installer
    run_uninstaller 0

    assert_devflow_not_installed
    assert_log_prefix_count 1 "uv tool uninstall|" "$FIXTURE_LOG"
    assert_exists "$FIXTURE_FAKE_BIN/uv"

    new_fixture uninstall-foreign-devflow Darwin
    mkdir -p \
        "$FIXTURE_HOME/.local/bin" \
        "$FIXTURE_HOME/.local/share/dotfiles/uv-tools/dotfiles-devflow"
    printf 'user-owned environment\n' \
        >"$FIXTURE_HOME/.local/share/dotfiles/uv-tools/dotfiles-devflow/marker"
    for executable in devflow devflow-reference-transaction devflow-pre-push; do
        printf 'user-owned executable\n' >"$FIXTURE_HOME/.local/bin/$executable"
    done

    run_uninstaller 0

    grep -Fxq 'user-owned environment' \
        "$FIXTURE_HOME/.local/share/dotfiles/uv-tools/dotfiles-devflow/marker" ||
        fail "uninstaller changed an unreceipted private tool environment"
    for executable in devflow devflow-reference-transaction devflow-pre-push; do
        grep -Fxq 'user-owned executable' "$FIXTURE_HOME/.local/bin/$executable" ||
            fail "uninstaller changed a foreign Workflow Engine executable"
    done
    assert_log_prefix_count 0 "uv tool uninstall|" "$FIXTURE_LOG"

    new_fixture uninstall-ambiguous-devflow Darwin
    run_installer
    mv "$FIXTURE_HOME/.local/bin/devflow" \
        "$FIXTURE_STATE/owned-devflow-link"
    printf 'replacement executable\n' >"$FIXTURE_HOME/.local/bin/devflow"

    run_uninstaller 0

    grep -Fxq 'replacement executable' "$FIXTURE_HOME/.local/bin/devflow" ||
        fail "uninstaller changed a replacement Workflow Engine executable"
    assert_exists \
        "$FIXTURE_HOME/.local/share/dotfiles/uv-tools/dotfiles-devflow"
    assert_exists \
        "$FIXTURE_HOME/.local/share/dotfiles/devflow-tool.receipt"
    assert_log_prefix_count 0 "uv tool uninstall|" "$FIXTURE_LOG"

    new_fixture uninstall-replaced-devflow-environment Darwin
    run_installer
    tool_environment="$FIXTURE_HOME/.local/share/dotfiles/uv-tools/dotfiles-devflow"
    mv "$tool_environment/bin/python" "$FIXTURE_STATE/owned-python-link"
    cp "$FIXTURE_GENERIC_TEMPLATE" "$FIXTURE_STATE/replacement-python"
    chmod +x "$FIXTURE_STATE/replacement-python"
    ln -s "$FIXTURE_STATE/replacement-python" "$tool_environment/bin/python"
    printf '%s\n' "$FIXTURE_ROOT/replacement-source" \
        >"$tool_environment/lib/python3.14/site-packages/dotfiles_devflow.pth"

    run_uninstaller 0

    assert_exists "$tool_environment"
    assert_exists \
        "$FIXTURE_HOME/.local/share/dotfiles/devflow-tool.receipt"
    assert_log_prefix_count 0 "uv tool uninstall|" "$FIXTURE_LOG"
    pass "uninstall removes only a receipted Workflow Engine installation"
}

test_uninstall_cli_is_safe() {
    new_fixture uninstall-cli Darwin
    run_installer

    run_uninstaller 0 --help
    grep -Fq 'Usage:' "$FIXTURE_ROOT/uninstall.out" ||
        fail "uninstall help did not print usage"
    assert_common_links

    run_uninstaller 2 --definitely-not-an-option
    assert_common_links
    pass "uninstall help and invalid options do not mutate configuration"
}

test_install_and_uninstall_reject_unsafe_homes() {
    local actual_status

    new_fixture unsafe-home Darwin
    run_installer
    ln -s / "$FIXTURE_ROOT/root-home-alias"

    if (
        unset HOME
        PATH="$FIXTURE_FAKE_BIN:/usr/bin:/bin" "$REPO_ROOT/uninstall.sh" --help
    ) >"$FIXTURE_ROOT/uninstall-help.out" 2>&1
    then
        actual_status=0
    else
        actual_status=$?
    fi
    assert_eq "0" "$actual_status" "uninstall help should not require HOME"

    for unsafe_home in \
        "" \
        relative-home \
        / \
        /./ \
        "$FIXTURE_ROOT/root-home-alias" \
        "$FIXTURE_ROOT/missing-home"
    do
        if HOME="$unsafe_home" PATH="$FIXTURE_FAKE_BIN:/usr/bin:/bin" \
            "$REPO_ROOT/uninstall.sh" >"$FIXTURE_ROOT/uninstall-unsafe.out" 2>&1
        then
            actual_status=0
        else
            actual_status=$?
        fi
        assert_eq "1" "$actual_status" "uninstall accepted unsafe HOME '$unsafe_home'"
        assert_common_links

        run_installer failure "$unsafe_home"
        assert_common_links
    done

    pass "install and uninstall reject unsafe HOME values before mutation"
}

test_uninstall_removes_only_owned_links() {
    local mise_parent_backup

    new_fixture uninstall-remove Darwin
    printf 'original zsh config\n' >"$FIXTURE_HOME/.zshrc"
    mkdir -p "$FIXTURE_HOME/.config/mise" "$FIXTURE_HOME/user-mise" "$FIXTURE_HOME/user-lazygit"
    printf 'user mise config\n' >"$FIXTURE_HOME/user-mise/99-user.toml"
    ln -s "$FIXTURE_HOME/user-mise" "$FIXTURE_HOME/.config/mise/conf.d"
    run_installer

    mv "$FIXTURE_HOME/.config/lazygit" "$FIXTURE_STATE/installed-lazygit-link"
    ln -s "$FIXTURE_HOME/user-lazygit" "$FIXTURE_HOME/.config/lazygit"
    run_uninstaller 0

    assert_common_links_removed
    assert_not_exists "$FIXTURE_HOME/.config/ghostty"
    assert_symlink "$FIXTURE_HOME/.config/lazygit" "$FIXTURE_HOME/user-lazygit"
    assert_exists "$FIXTURE_HOME/.local/share/dotfiles/local.fish"
    assert_exists "$FIXTURE_HOME/.local/share/dotfiles/local.zsh"
    assert_exists "$FIXTURE_FAKE_BIN/fish"

    mise_parent_backup=""
    for candidate in "$FIXTURE_HOME"/.config/mise/conf.d.bak.*; do
        if [[ -e "$candidate" || -L "$candidate" ]]; then
            mise_parent_backup="$candidate"
            break
        fi
    done
    [[ -n "$mise_parent_backup" ]] || fail "Mise parent backup was not preserved"
    grep -Fq "$mise_parent_backup" "$FIXTURE_ROOT/uninstall.out" ||
        fail "uninstall did not report the Mise parent backup"

    run_uninstaller 0
    assert_symlink "$FIXTURE_HOME/.config/lazygit" "$FIXTURE_HOME/user-lazygit"
    pass "uninstall removes only owned links and reports retained backups"
}

test_uninstall_restores_latest_backups() {
    new_fixture uninstall-restore Darwin
    mkdir -p \
        "$FIXTURE_HOME/.config/fish" \
        "$FIXTURE_HOME/.config/herdr" \
        "$FIXTURE_HOME/.config/mise" \
        "$FIXTURE_HOME/user-mise"
    printf 'original fish config\n' >"$FIXTURE_HOME/.config/fish/user.fish"
    printf 'original herdr config\n' >"$FIXTURE_HOME/.config/herdr/config.toml"
    printf 'original zsh config\n' >"$FIXTURE_HOME/.zshrc"
    printf 'older zsh config\n' >"$FIXTURE_HOME/.zshrc.bak.1"
    printf 'older lazygit config\n' >"$FIXTURE_HOME/.config/lazygit.bak.0007"
    printf 'newer lazygit config\n' >"$FIXTURE_HOME/.config/lazygit.bak.0008"
    printf 'user mise fragment\n' >"$FIXTURE_HOME/user-mise/99-user.toml"
    ln -s "$FIXTURE_HOME/user-mise" "$FIXTURE_HOME/.config/mise/conf.d"
    run_installer

    run_uninstaller 0 --restore

    [[ -d "$FIXTURE_HOME/.config/fish" && ! -L "$FIXTURE_HOME/.config/fish" ]] ||
        fail "Fish directory backup was not restored"
    grep -Fxq 'original fish config' "$FIXTURE_HOME/.config/fish/user.fish" ||
        fail "restored Fish directory lost its content"
    grep -Fxq 'original herdr config' "$FIXTURE_HOME/.config/herdr/config.toml" ||
        fail "Herdr config backup was not restored"
    grep -Fxq 'original zsh config' "$FIXTURE_HOME/.zshrc" ||
        fail "newest zsh backup was not restored"
    grep -Fxq 'older zsh config' "$FIXTURE_HOME/.zshrc.bak.1" ||
        fail "older zsh backup should remain available"
    grep -Fxq 'newer lazygit config' "$FIXTURE_HOME/.config/lazygit" ||
        fail "numeric backup ordering did not treat leading zeroes as decimal"
    grep -Fxq 'older lazygit config' "$FIXTURE_HOME/.config/lazygit.bak.0007" ||
        fail "older lazygit backup should remain available"
    assert_symlink "$FIXTURE_HOME/.config/mise/conf.d" "$FIXTURE_HOME/user-mise"
    grep -Fxq 'user mise fragment' "$FIXTURE_HOME/.config/mise/conf.d/99-user.toml" ||
        fail "restored Mise parent lost its content"

    ln -s "$REPO_ROOT/mise/conf.d/00-dotfiles.toml" \
        "$FIXTURE_HOME/user-mise/00-dotfiles.toml"
    run_uninstaller 0 --restore
    grep -Fxq 'original zsh config' "$FIXTURE_HOME/.zshrc" ||
        fail "second restore changed restored user configuration"
    assert_symlink "$FIXTURE_HOME/.config/mise/conf.d" "$FIXTURE_HOME/user-mise"
    assert_symlink \
        "$FIXTURE_HOME/user-mise/00-dotfiles.toml" \
        "$REPO_ROOT/mise/conf.d/00-dotfiles.toml"

    run_uninstaller 0
    assert_symlink "$FIXTURE_HOME/.config/mise/conf.d" "$FIXTURE_HOME/user-mise"
    assert_symlink \
        "$FIXTURE_HOME/user-mise/00-dotfiles.toml" \
        "$REPO_ROOT/mise/conf.d/00-dotfiles.toml"
    pass "uninstall restores the newest safe backups without clobbering user state"
}

test_uninstall_blocks_unsafe_or_ambiguous_restores() {
    local parent_backup

    new_fixture uninstall-blocked-restore Darwin
    mkdir -p "$FIXTURE_HOME/.config/mise" "$FIXTURE_HOME/user-mise"
    printf 'original mise fragment\n' >"$FIXTURE_HOME/user-mise/99-user.toml"
    ln -s "$FIXTURE_HOME/user-mise" "$FIXTURE_HOME/.config/mise/conf.d"
    run_installer

    printf 'new local fragment\n' >"$FIXTURE_HOME/.config/mise/conf.d/50-local.toml"
    ln -s "$REPO_ROOT/fish" "$FIXTURE_HOME/.config/fish.bak.1"
    printf 'first equal-timestamp backup\n' \
        >"$FIXTURE_HOME/.config/lazygit.bak.8"
    printf 'second equal-timestamp backup\n' \
        >"$FIXTURE_HOME/.config/lazygit.bak.0008"
    run_uninstaller 1 --restore

    assert_symlink "$FIXTURE_HOME/.config/fish" "$REPO_ROOT/fish"
    assert_symlink "$FIXTURE_HOME/.config/fish.bak.1" "$REPO_ROOT/fish"
    assert_symlink "$FIXTURE_HOME/.config/lazygit" "$REPO_ROOT/lazygit"
    assert_exists "$FIXTURE_HOME/.config/lazygit.bak.8"
    assert_exists "$FIXTURE_HOME/.config/lazygit.bak.0008"
    assert_symlink \
        "$FIXTURE_HOME/.config/mise/conf.d/00-dotfiles.toml" \
        "$REPO_ROOT/mise/conf.d/00-dotfiles.toml"
    grep -Fxq 'new local fragment' "$FIXTURE_HOME/.config/mise/conf.d/50-local.toml" ||
        fail "blocked restore changed a user-owned sibling"
    grep -Fq 'restore blocked:' "$FIXTURE_ROOT/uninstall.out" ||
        fail "blocked restore did not explain why it stopped"
    parent_backup=""
    for candidate in "$FIXTURE_HOME"/.config/mise/conf.d.bak.*; do
        if [[ -e "$candidate" || -L "$candidate" ]]; then
            parent_backup="$candidate"
            break
        fi
    done
    [[ -n "$parent_backup" ]] || fail "blocked restore consumed the parent backup"

    printf 'older leaf config\n' \
        >"$FIXTURE_HOME/.config/mise/conf.d/00-dotfiles.toml.bak.1"
    run_uninstaller 1 --restore
    assert_symlink \
        "$FIXTURE_HOME/.config/mise/conf.d/00-dotfiles.toml" \
        "$REPO_ROOT/mise/conf.d/00-dotfiles.toml"
    assert_exists "$parent_backup"
    assert_exists "$FIXTURE_HOME/.config/mise/conf.d/00-dotfiles.toml.bak.1"

    pass "unsafe and ambiguous restores preserve the active group"
}

test_equivalent_relative_links_are_idempotent() {
    new_fixture relative-link Darwin
    mkdir -p "$FIXTURE_HOME/.config"
    ln -s "$REPO_ROOT" "$FIXTURE_ROOT/repo-alias"
    ln -s ../../repo-alias/fish "$FIXTURE_HOME/.config/fish"
    ln -s "$REPO_ROOT/zsh/.zshrc" "$FIXTURE_ROOT/zsh-source-alias"
    ln -s ../zsh-source-alias "$FIXTURE_HOME/.zshrc"
    mkdir -p "$FIXTURE_HOME/user-herdr"
    ln -s "$REPO_ROOT/herdr/config.toml" "$FIXTURE_HOME/user-herdr/config.toml"
    ln -s "$FIXTURE_HOME/user-herdr" "$FIXTURE_HOME/.config/herdr"

    run_installer

    assert_eq "../../repo-alias/fish" "$(readlink "$FIXTURE_HOME/.config/fish")" \
        "installer replaced an equivalent relative link"
    assert_eq "../zsh-source-alias" "$(readlink "$FIXTURE_HOME/.zshrc")" \
        "installer replaced an equivalent file-source alias chain"
    assert_symlink "$FIXTURE_HOME/.config/herdr" "$FIXTURE_HOME/user-herdr"
    assert_symlink \
        "$FIXTURE_HOME/.config/herdr/config.toml" \
        "$REPO_ROOT/herdr/config.toml"
    for candidate in "$FIXTURE_HOME"/.config/fish.bak.*; do
        [[ ! -e "$candidate" && ! -L "$candidate" ]] ||
            fail "installer backed up an equivalent relative link"
    done
    for candidate in "$FIXTURE_HOME"/.zshrc.bak.*; do
        [[ ! -e "$candidate" && ! -L "$candidate" ]] ||
            fail "installer backed up an equivalent file-source alias chain"
    done
    for candidate in "$FIXTURE_HOME"/.config/herdr.bak.*; do
        [[ ! -e "$candidate" && ! -L "$candidate" ]] ||
            fail "installer backed up a parent containing an equivalent nested link"
    done

    run_uninstaller 0
    assert_not_exists "$FIXTURE_HOME/.config/fish"
    assert_not_exists "$FIXTURE_HOME/.zshrc"
    assert_symlink "$FIXTURE_HOME/.config/herdr" "$FIXTURE_HOME/user-herdr"
    assert_symlink \
        "$FIXTURE_HOME/.config/herdr/config.toml" \
        "$REPO_ROOT/herdr/config.toml"
    pass "equivalent direct and nested links remain untouched"
}

test_link_preflight_prevents_partial_configuration() {
    local fixture_repo source_name

    new_fixture missing-source Darwin
    fixture_repo="$FIXTURE_ROOT/repo"
    mkdir -p "$fixture_repo/mise/conf.d" "$fixture_repo/templates"
    cp "$REPO_ROOT/install.sh" "$REPO_ROOT/Brewfile" "$fixture_repo/"
    cp "$REPO_ROOT/templates/local.fish" "$REPO_ROOT/templates/local.zsh" \
        "$fixture_repo/templates/"
    for source_name in devflow fish ghostty herdr hunk lazygit nvim tmux zsh; do
        ln -s "$REPO_ROOT/$source_name" "$fixture_repo/$source_name"
    done
    FIXTURE_INSTALL_REPO_ROOT="$(cd "$fixture_repo" && pwd -P)"
    printf 'original zsh config\n' >"$FIXTURE_HOME/.zshrc"

    run_installer failure --skip-mise-runtimes

    grep -Fq \
        "missing or invalid tracked configuration file: $FIXTURE_INSTALL_REPO_ROOT/mise/conf.d/00-dotfiles.toml" \
        "$FIXTURE_OUTPUT" ||
        fail "skip mode did not preflight the tracked Mise manifest"
    grep -Fxq 'original zsh config' "$FIXTURE_HOME/.zshrc" ||
        fail "missing source preflight changed zsh config"
    for candidate in "$FIXTURE_HOME"/.zshrc.bak.*; do
        [[ ! -e "$candidate" && ! -L "$candidate" ]] ||
            fail "missing source preflight created a zsh backup"
    done
    assert_not_exists "$FIXTURE_HOME/.config"
    assert_log_count 0 "brew bootstrap" "$FIXTURE_LOG"
    assert_log_count 0 "brew bundle install" "$FIXTURE_LOG"
    assert_log_count 0 "mise install" "$FIXTURE_LOG"

    new_fixture blocked-parent Darwin
    mkdir -p "$FIXTURE_HOME/.config"
    printf 'user-owned mise path\n' >"$FIXTURE_HOME/.config/mise"
    printf 'original zsh config\n' >"$FIXTURE_HOME/.zshrc"

    run_installer failure

    grep -Fq 'blocks required configuration directory' "$FIXTURE_OUTPUT" ||
        fail "blocking parent failure was not actionable"
    grep -Fxq 'user-owned mise path' "$FIXTURE_HOME/.config/mise" ||
        fail "blocking parent was changed"
    grep -Fxq 'original zsh config' "$FIXTURE_HOME/.zshrc" ||
        fail "blocking parent preflight changed zsh config"
    assert_not_exists "$FIXTURE_HOME/.config/fish"

    new_fixture missing-devflow-package Darwin
    fixture_repo="$FIXTURE_ROOT/repo"
    mkdir -p \
        "$fixture_repo/devflow" \
        "$fixture_repo/mise/conf.d" \
        "$fixture_repo/templates"
    cp "$REPO_ROOT/install.sh" "$REPO_ROOT/Brewfile" "$fixture_repo/"
    cp "$REPO_ROOT/devflow/pyproject.toml" "$fixture_repo/devflow/"
    ln -s "$REPO_ROOT/devflow/src" "$fixture_repo/devflow/src"
    cp "$REPO_ROOT/mise/conf.d/00-dotfiles.toml" \
        "$fixture_repo/mise/conf.d/"
    cp "$REPO_ROOT/templates/local.fish" "$REPO_ROOT/templates/local.zsh" \
        "$fixture_repo/templates/"
    for source_name in fish ghostty herdr hunk lazygit nvim tmux zsh; do
        ln -s "$REPO_ROOT/$source_name" "$fixture_repo/$source_name"
    done
    FIXTURE_INSTALL_REPO_ROOT="$(cd "$fixture_repo" && pwd -P)"

    run_installer failure --skip-mise-runtimes

    grep -Fq \
        "missing or invalid tracked configuration file: $FIXTURE_INSTALL_REPO_ROOT/devflow/uv.lock" \
        "$FIXTURE_OUTPUT" ||
        fail "installer did not preflight the Workflow Engine package sources"
    assert_log_count 0 "brew bootstrap" "$FIXTURE_LOG"
    assert_not_exists "$FIXTURE_HOME/.config"
    pass "link preflight fails before changing home configuration"
}

test_dependency_manifests_match_the_install_contract() {
    local expected_line
    local brew_lines mise_lines

    brew_lines=(
        'brew "git"'
        'brew "fish"'
        'brew "zsh"'
        'brew "neovim"'
        'brew "herdr"'
        'brew "tmux"'
        'brew "lazygit"'
        'brew "hunk"'
        'brew "mise"'
        'brew "atuin"'
        'brew "gh"'
        'brew "ripgrep"'
        'brew "tree-sitter-cli"'
        'brew "uv"'
        'brew "ghcup"'
        'brew "xclip" if OS.linux?'
        'brew "wl-clipboard" if OS.linux?'
    )
    for expected_line in "${brew_lines[@]}"; do
        grep -Fxq "$expected_line" "$REPO_ROOT/Brewfile" ||
            fail "Brewfile is missing: $expected_line"
    done
    assert_eq "${#brew_lines[@]}" \
        "$(grep -Evc '^[[:space:]]*(#|$)' "$REPO_ROOT/Brewfile")" \
        "Brewfile contains an unreviewed declaration"

    mise_lines=(
        '"core:node" = "24.18.0"'
        '"core:python" = "3.14.7"'
        '"core:rust" = { version = "1.97.1", profile = "minimal", components = ["clippy", "rustfmt", "rust-src"] }'
        '"core:java" = "corretto-21.0.12.8.1"'
    )
    for expected_line in "${mise_lines[@]}"; do
        grep -Fxq "$expected_line" "$REPO_ROOT/mise/conf.d/00-dotfiles.toml" ||
            fail "Mise manifest is missing: $expected_line"
    done
    assert_log_count 1 '[tools]' "$REPO_ROOT/mise/conf.d/00-dotfiles.toml"
    assert_eq "$(( ${#mise_lines[@]} + 1 ))" \
        "$(grep -Evc '^[[:space:]]*(#|$)' "$REPO_ROOT/mise/conf.d/00-dotfiles.toml")" \
        "Mise manifest contains an unreviewed declaration"
    pass "Brew and Mise manifests match the dependency ownership contract"
}

test_user_mise_config_does_not_override_bootstrap_manifest
test_mise_environment_cannot_override_bootstrap_manifest
test_non_mise_runtime_command_is_rejected_before_linking
test_mise_runtime_version_mismatch_is_rejected_before_linking
test_install_cli_is_safe
test_skip_mise_runtimes_completes_yum_setup
test_skip_mise_runtimes_retains_existing_manifest
test_skip_mise_runtimes_preserves_foreign_devflow_state
test_devflow_install_failure_precedes_configuration_links
test_devflow_resumes_after_uv_interruption
test_devflow_resumes_after_finalization_interruption
test_devflow_preflight_preserves_foreign_state
test_devflow_receipt_requires_the_exact_python
test_devflow_noop_rejects_a_replaced_environment
test_devflow_accepts_uvs_unterminated_editable_source_marker
test_devflow_rejects_an_ambiguous_editable_source_marker
test_devflow_uv_receipt_accepts_equivalent_toml
test_devflow_uv_invocations_are_hermetic
test_devflow_uv_receipt_inventory_is_exact
test_generic_install_preserves_harness_configuration
test_macos_fresh_and_second_run
test_linux_manager_fresh_and_second_run apt-get
test_linux_manager_fresh_and_second_run dnf
test_linux_manager_fresh_and_second_run yum
test_linux_manager_fresh_and_second_run pacman
test_unsupported_linux_package_manager
test_linux_handoff_is_validated_before_linking
test_non_corretto_jdk_is_rejected_before_linking
test_incompatible_git_tool_versions_are_rejected_before_linking
test_incompatible_neovim_versions_are_rejected_before_linking
test_uninstall_cli_is_safe
test_install_and_uninstall_reject_unsafe_homes
test_uninstall_removes_only_owned_links
test_uninstall_removes_only_owned_devflow
test_uninstall_restores_latest_backups
test_uninstall_blocks_unsafe_or_ambiguous_restores
test_equivalent_relative_links_are_idempotent
test_link_preflight_prevents_partial_configuration
test_dependency_manifests_match_the_install_contract
printf 'All install integration tests passed.\n'
