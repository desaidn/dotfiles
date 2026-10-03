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
    for command_name in bash cat chmod cp date dirname env ln readlink mkdir mktemp mv rmdir unlink; do
        command_path="$(command -v "$command_name")"
        ln -s "$command_path" "$FIXTURE_FAKE_BIN/$command_name"
    done

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
    for command_name in cc c++ make ps file git tar gzip unzip diff; do
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
case "${0##*/}" in
    cc|c++)
        compiler="${0##*/}"
        language=c
        [[ "$compiler" == "cc" ]] || language=c++
        [[ "$*" == "-x $language -o /dev/null -" ]] || exit 2
        source="$(cat)"
        [[ "$source" == *'#include <'* ]] || exit 2
        printf '%s compile and link\n' "$compiler" >>"$DOTFILES_TEST_LOG"
        [[ ! -e "$DOTFILES_TEST_STATE/broken-$compiler" ]] || exit 1
        ;;
esac
exit 0
SCRIPT

    if [[ "$FIXTURE_OS" == "Darwin" ]]; then
        for command_name in cc c++; do
            cp "$FIXTURE_GENERIC_TEMPLATE" "$FIXTURE_FAKE_BIN/$command_name"
            chmod +x "$FIXTURE_FAKE_BIN/$command_name"
        done
    fi

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
if [[ "${MISE_CEILING_PATHS:-}" != "$DOTFILES_TEST_REPO_ROOT" ||
    "${MISE_SYSTEM_CONFIG_DIR:-}" != "$DOTFILES_TEST_REPO_ROOT/mise" ]]
then
    printf 'mise discovery is not bounded to the bootstrap manifest\n' >&2
    exit 4
fi
if [[ -n "${MISE_CONFIG_FILE:-}" ||
    -n "${MISE_GLOBAL_CONFIG_FILE:-}" ||
    -n "${MISE_GLOBAL_CONFIG_ROOT:-}" ||
    -n "${MISE_IGNORED_CONFIG_PATHS:-}" ||
    -n "${MISE_NO_CONFIG:-}" ||
    -n "${MISE_DISABLE_TOOLS:-}" ||
    -n "${MISE_ENV:-}" ||
    -n "${MISE_ENV_FILE:-}" ||
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
        if [[ "${2:-}" == ls && "${3:-}" == --json ]]; then
            if [[ -f "$DOTFILES_TEST_STATE/mise-sources.json" ]]; then
                cat "$DOTFILES_TEST_STATE/mise-sources.json"
            else
                printf '[{"path":"%s/mise/conf.d/00-dotfiles.toml"}]\n' "$DOTFILES_TEST_REPO_ROOT"
            fi
            exit 0
        fi
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
        if [[ -e "$DOTFILES_TEST_STATE/mise-parent-activation" &&
            -n "${__MISE_ORIG_PATH:-}" ]]
        then
            printf "export PATH=\"%s:\$PATH\"\n" \
                "$DOTFILES_TEST_STATE/mise-shims"
        else
            printf "export PATH=\"%s:\$PATH\"\n" "$DOTFILES_TEST_FAKE_BIN"
        fi
        ;;
    env)
        [[ "${2:-}" == "--shell" && "${3:-}" == "bash" ]] || exit 2
        printf 'mise env\n' >>"$DOTFILES_TEST_LOG"
        printf "export PATH=\"%s:\$PATH\"\n" "$DOTFILES_TEST_FAKE_BIN"
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
        java_version=21.0.12
        if [[ -f "$DOTFILES_TEST_STATE/java-version" ]]; then
            IFS= read -r java_version <"$DOTFILES_TEST_STATE/java-version"
        fi
        printf 'openjdk version "%s"\n' "$java_version" >&2
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
        javac_version=21.0.12
        if [[ -f "$DOTFILES_TEST_STATE/javac-version" ]]; then
            IFS= read -r javac_version <"$DOTFILES_TEST_STATE/javac-version"
        fi
        printf 'javac %s\n' "$javac_version"
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
        nvim_version='NVIM v0.12.5'
        if [[ -f "$DOTFILES_TEST_STATE/nvim-version" ]]; then
            IFS= read -r nvim_version <"$DOTFILES_TEST_STATE/nvim-version"
        fi
        if [[ "${1:-}" == "--version" ]]; then
            printf '%s\n' "$nvim_version"
        else
            DOTFILES_TEST_NVIM_VERSION="${nvim_version#NVIM v}" \
                exec "$DOTFILES_TEST_REAL_NVIM" --cmd 'lua
                    local original = vim.version
                    vim.version = setmetatable({}, {
                        __index = original,
                        __call = function()
                            return original.parse(vim.env.DOTFILES_TEST_NVIM_VERSION)
                        end,
                    })
                ' "$@"
        fi
        ;;
    tmux)
        if [[ -e "$DOTFILES_TEST_STATE/old-tmux" ]]; then
            printf 'tmux 3.4\n'
        else
            printf 'tmux 3.5\n'
        fi
        ;;
    lazygit)
        if [[ -e "$DOTFILES_TEST_STATE/old-lazygit" ]]; then
            printf 'commit=, build date=, build source=Homebrew, version=0.63.1, os=darwin, arch=arm64\n'
        else
            printf 'commit=, build date=, build source=Homebrew, version=0.64.0, os=darwin, arch=arm64\n'
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
    for command_name in git fish zsh nvim herdr tmux lazygit atuin gh rg tree-sitter cmake ctest ninja hunk wl-copy wl-paste xclip; do
        cp "$DOTFILES_TEST_FORMULA_TEMPLATE" "$DOTFILES_TEST_FAKE_BIN/$command_name"
        chmod +x "$DOTFILES_TEST_FAKE_BIN/$command_name"
    done
    cp "$DOTFILES_TEST_MISE_TEMPLATE" "$DOTFILES_TEST_FAKE_BIN/mise"
    chmod +x "$DOTFILES_TEST_FAKE_BIN/mise"
    cp "$DOTFILES_TEST_GENERIC_TEMPLATE" "$DOTFILES_TEST_FAKE_BIN/uv"
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
        printf "export PATH=\"%s:\$PATH\"\n" "$DOTFILES_TEST_FAKE_BIN"
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
            *" --file=$DOTFILES_TEST_REPO_ROOT/Brewfile "*)
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
        "$FIXTURE_PACKAGE_TEMPLATE" \
        "$FIXTURE_RUNTIME_TEMPLATE"
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
    FIXTURE_PACKAGE_TEMPLATE="$FIXTURE_ROOT/package-template"
    FIXTURE_CALLER_DIR="$FIXTURE_ROOT/caller"
    FIXTURE_INSTALL_REPO_ROOT="$REPO_ROOT"
    FIXTURE_BREW_PREFIX="$FIXTURE_ROOT"
    FIXTURE_OS="$os_name"
    FIXTURE_CODEX_DIRECTORY="$FIXTURE_HOME/.codex"
    FIXTURE_PI_DIRECTORY="$FIXTURE_HOME/.pi/agent"
    FIXTURE_REAL_NVIM="$(command -v nvim)"
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
            CODEX_HOME="$FIXTURE_CODEX_DIRECTORY" \
            PI_CODING_AGENT_DIR="$FIXTURE_PI_DIRECTORY" \
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
            DOTFILES_TEST_REAL_NVIM="$FIXTURE_REAL_NVIM" \
            DOTFILES_TEST_RUNTIME_TEMPLATE="$FIXTURE_RUNTIME_TEMPLATE" \
            DOTFILES_TEST_STATE="$FIXTURE_STATE" \
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
        CODEX_HOME="$FIXTURE_CODEX_DIRECTORY" \
        PI_CODING_AGENT_DIR="$FIXTURE_PI_DIRECTORY" \
        PATH="$FIXTURE_FAKE_BIN:/usr/bin:/bin" \
        DOTFILES_TEST_FAKE_BIN="$FIXTURE_FAKE_BIN" \
        DOTFILES_TEST_GENERIC_TEMPLATE="$FIXTURE_GENERIC_TEMPLATE" \
        DOTFILES_TEST_LOG="$FIXTURE_LOG" \
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

assert_workflow_links() {
    assert_symlink "$FIXTURE_CODEX_DIRECTORY/AGENTS.md" "$REPO_ROOT/docs/agents/development-workflow.md"
    assert_symlink "$FIXTURE_PI_DIRECTORY/AGENTS.md" "$REPO_ROOT/docs/agents/development-workflow.md"
    assert_symlink "$FIXTURE_HOME/.claude/rules/development-workflow.md" "$REPO_ROOT/docs/agents/development-workflow.md"
}

assert_non_mise_links() {
    assert_workflow_links
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
    assert_not_exists "$FIXTURE_CODEX_DIRECTORY/AGENTS.md"
    assert_not_exists "$FIXTURE_PI_DIRECTORY/AGENTS.md"
    assert_not_exists "$FIXTURE_HOME/.claude/rules/development-workflow.md"
    assert_not_exists "$FIXTURE_HOME/.config/fish"
    assert_not_exists "$FIXTURE_HOME/.config/herdr/config.toml"
    assert_not_exists "$FIXTURE_HOME/.config/hunk/config.toml"
    assert_not_exists "$FIXTURE_HOME/.config/mise/conf.d/00-dotfiles.toml"
    assert_not_exists "$FIXTURE_HOME/.config/nvim"
    assert_not_exists "$FIXTURE_HOME/.config/tmux"
    assert_not_exists "$FIXTURE_HOME/.zshrc"
}

test_macos_fresh_and_second_run() {
    new_fixture macos Darwin
    printf 'original zsh config\n' >"$FIXTURE_HOME/.zshrc"

    run_installer

    assert_common_links
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
    assert_log_count 0 "apt-get update" "$FIXTURE_LOG"

    run_installer

    assert_log_count 1 "brew bootstrap" "$FIXTURE_LOG"
    assert_log_count 1 "brew bundle install" "$FIXTURE_LOG"
    assert_log_count 1 "brew cask install ghostty" "$FIXTURE_LOG"
    assert_log_count 1 "brew cask install font-jetbrains-mono" "$FIXTURE_LOG"
    assert_log_count 1 "mise install" "$FIXTURE_LOG"
    assert_log_prefix_count 0 "apt-get " "$FIXTURE_LOG"
    assert_eq "1" "$(count_zsh_backups)" "a second run should not create another zsh backup"
    assert_common_links
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
                "dnf install -y gcc-c++ procps-ng curl file git tar gzip unzip diffutils ca-certificates" \
                "$FIXTURE_LOG"
            ;;
        yum)
            assert_log_count 1 "yum groupinstall -y Development Tools" "$FIXTURE_LOG"
            assert_log_count 1 \
                "yum install -y gcc-c++ procps-ng curl file git tar gzip unzip diffutils ca-certificates" \
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

test_missing_cpp_compiler_installs_native_tools() {
    local command_name
    new_fixture missing-cpp-compiler Linux apt-get
    for command_name in cc make ps file git tar gzip unzip diff; do
        cp "$FIXTURE_GENERIC_TEMPLATE" "$FIXTURE_FAKE_BIN/$command_name"
        chmod +x "$FIXTURE_FAKE_BIN/$command_name"
    done

    run_installer

    assert_linux_native_install_once apt-get
    assert_log_count 1 'cc compile and link' "$FIXTURE_LOG"
    assert_log_count 1 'c++ compile and link' "$FIXTURE_LOG"
    assert_common_links
    pass "missing C++ compiler installs native development tools even when C is available"
}

test_broken_compilers_fail_before_provisioning() {
    local os_name compiler message
    for os_name in Darwin Linux; do
        for compiler in cc c++; do
            new_fixture "broken-$os_name-$compiler" "$os_name"
            : >"$FIXTURE_STATE/broken-$compiler"
            printf 'original zsh config\n' >"$FIXTURE_HOME/.zshrc"

            run_installer failure

            if [[ "$compiler" == "cc" ]]; then
                message='the C compiler cannot compile and link a program'
            else
                message='the C++ compiler cannot compile and link the standard library'
            fi
            grep -Fq "$message" "$FIXTURE_OUTPUT" ||
                fail "broken $compiler failure on $os_name was not actionable"
            assert_log_count 1 "$compiler compile and link" "$FIXTURE_LOG"
            assert_log_count 0 'brew bootstrap' "$FIXTURE_LOG"
            assert_log_count 0 'brew bundle install' "$FIXTURE_LOG"
            assert_not_exists "$FIXTURE_HOME/.config"
            assert_not_exists "$FIXTURE_HOME/.local"
            grep -Fxq 'original zsh config' "$FIXTURE_HOME/.zshrc" ||
                fail "compiler validation changed zsh config"
        done
    done
    pass "C and C++ compile/link failures stop macOS and Linux provisioning before configuration changes"
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

test_compatible_jdk_vendor_is_accepted() {
    new_fixture non-corretto-jdk Darwin
    : >"$FIXTURE_STATE/non-corretto-java"

    run_installer

    assert_common_links
    pass "compatible JDKs are accepted independently of their vendor banner"
}

test_incompatible_java_versions_are_rejected_before_linking() {
    local command_name
    for command_name in java javac; do
        new_fixture "old-$command_name" Darwin
        printf '20.0.2\n' >"$FIXTURE_STATE/$command_name-version"

        run_installer failure

        grep -Fq '21+ is required' "$FIXTURE_OUTPUT" ||
            fail "old $command_name failure was not actionable"
        assert_not_exists "$FIXTURE_HOME/.config"
    done
    pass "Java runtimes and compilers below 21 are rejected before linking"
}

test_incompatible_tmux_is_rejected_before_linking() {
    new_fixture old-tmux Darwin
    : >"$FIXTURE_STATE/old-tmux"

    run_installer failure

    grep -Fq 'tmux 3.5+ is required' "$FIXTURE_OUTPUT" ||
        fail "old tmux failure was not actionable"
    assert_not_exists "$FIXTURE_HOME/.config"
    pass "tmux below the extended-keys-format floor is rejected before linking"
}

test_incompatible_git_tool_versions_are_rejected_before_linking() {
    new_fixture incompatible-git-tool-versions Darwin
    : >"$FIXTURE_STATE/old-lazygit"
    : >"$FIXTURE_STATE/old-hunk"

    run_installer failure

    grep -Fq 'LazyGit 0.64+ is required' "$FIXTURE_OUTPUT" ||
        fail "old LazyGit failure was not actionable"
    grep -Fq 'Hunk 0.18.1+ is required' "$FIXTURE_OUTPUT" ||
        fail "old Hunk failure was not actionable"
    assert_not_exists "$FIXTURE_HOME/.config"
    pass "Git tools below the configured integration floors are rejected before linking"
}

test_incompatible_neovim_versions_are_rejected_before_linking() {
    local found fixture_name

    for found in 'NVIM v0.12.4' 'NVIM v0.12.5-dev' 'invalid'; do
        fixture_name="incompatible-neovim-${found#NVIM v}"
        new_fixture "$fixture_name" Darwin
        printf '%s\n' "$found" >"$FIXTURE_STATE/nvim-version"

        run_installer failure

        grep -Fq 'Neovim compatibility check failed: Neovim' "$FIXTURE_OUTPUT" ||
            fail "unsupported Neovim version failure was not actionable: $found"
        assert_not_exists "$FIXTURE_HOME/.config"
    done

    pass "Neovim versions below the shared minimum are rejected before linking"
}

test_newer_neovim_versions_are_accepted() {
    local found
    for found in 'NVIM v0.12.6' 'NVIM v0.13.0' 'NVIM v0.13.0-dev'; do
        new_fixture "compatible-neovim-${found#NVIM v}" Darwin
        printf '%s\n' "$found" >"$FIXTURE_STATE/nvim-version"

        run_installer

        assert_common_links
    done
    pass "newer Neovim releases pass the shared compatibility check"
}

test_neovim_check_failures_precede_configuration_links() {
    local condition fixture_repo source_name
    for condition in missing broken; do
        new_fixture "neovim-check-$condition" Darwin
        fixture_repo="$FIXTURE_ROOT/repo"
        mkdir -p "$fixture_repo/nvim/lua/custom/lib"
        cp "$REPO_ROOT/install.sh" "$REPO_ROOT/Brewfile" "$fixture_repo/"
        for source_name in fish ghostty herdr hunk lazygit mise templates tmux docs zsh; do
            ln -s "$REPO_ROOT/$source_name" "$fixture_repo/$source_name"
        done
        FIXTURE_INSTALL_REPO_ROOT="$(cd "$fixture_repo" && pwd -P)"
        if [[ "$condition" == broken ]]; then
            printf "error('fixture compatibility failure')\n" \
                >"$fixture_repo/nvim/lua/custom/lib/neovim.lua"
        fi

        run_installer failure

        if [[ "$condition" == missing ]]; then
            grep -Fq 'missing or invalid tracked configuration file:' "$FIXTURE_OUTPUT" ||
                fail "missing Neovim check was not caught during preflight"
            assert_log_count 0 "brew bootstrap" "$FIXTURE_LOG"
            assert_log_count 0 "brew bundle install" "$FIXTURE_LOG"
        else
            grep -Fq 'fixture compatibility failure' "$FIXTURE_OUTPUT" ||
                fail "broken Neovim check did not propagate its error"
        fi
        assert_not_exists "$FIXTURE_HOME/.config"
        assert_not_exists "$FIXTURE_HOME/.local"
    done
    pass "missing or broken Neovim checks fail before configuration links"
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
        export MISE_CEILING_PATHS=/
        export MISE_SYSTEM_CONFIG_DIR="$FIXTURE_ROOT/foreign-system"
        export MISE_ENV=foreign
        export MISE_ENV_FILE=foreign.env
        export MISE_NODE_VERSION=18
        export MISE_PYTHON_VERSION=3.10
        export MISE_RUST_VERSION=1.93.0
        export MISE_JAVA_VERSION=21
        run_installer
    )

    assert_common_links
    pass "Mise environment cannot override bootstrap runtime provisioning"
}

test_parent_mise_activation_does_not_override_bootstrap_environment() {
    local command_name

    new_fixture mise-parent-activation Darwin
    mkdir -p "$FIXTURE_STATE/mise-shims"
    for command_name in rustc cargo rustfmt; do
        ln -s "$FIXTURE_FAKE_BIN/mise" \
            "$FIXTURE_STATE/mise-shims/$command_name"
    done
    : >"$FIXTURE_STATE/mise-parent-activation"

    (
        export MISE_SHELL=fish
        export __MISE_ORIG_PATH="$FIXTURE_STATE/parent-path"
        run_installer
    )

    assert_common_links
    assert_log_count 1 "mise env" "$FIXTURE_LOG"
    assert_log_count 0 "mise activate" "$FIXTURE_LOG"
    pass "parent Mise activation cannot override bootstrap runtime selection"
}

test_unexpected_mise_sources_are_rejected_before_installing() {
    new_fixture mise-foreign-source Darwin
    printf '[{"path":"%s/mise/conf.d/00-dotfiles.toml"},{"path":"/foreign/mise.toml"}]\n' \
        "$REPO_ROOT" >"$FIXTURE_STATE/mise-sources.json"
    run_installer failure
    grep -Fq 'Mise must load only the tracked runtime manifest' "$FIXTURE_OUTPUT" ||
        fail "foreign Mise source did not produce a useful diagnostic"
    assert_log_count 0 'mise install' "$FIXTURE_LOG"
    assert_not_exists "$FIXTURE_HOME/.config"
    pass "unexpected Mise sources are rejected before installing runtimes or linking"
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
    assert_not_exists "$FIXTURE_HOME/.config/mise/conf.d/00-dotfiles.toml"
    grep -Fxq 'user mise config' "$FIXTURE_HOME/.config/mise/config.toml" ||
        fail "skip mode changed the user's main Mise config"
    assert_linux_native_install_once yum
    assert_log_count 0 "mise dry-run" "$FIXTURE_LOG"
    assert_log_count 0 "mise install" "$FIXTURE_LOG"
    assert_log_count 0 "mise activate" "$FIXTURE_LOG"
    grep -Fq 'Mise runtime installation and validation skipped by request.' "$FIXTURE_OUTPUT" ||
        fail "skip mode did not report its degraded runtime state"
    grep -Fq 'Dotfiles installation complete with Mise runtime provisioning skipped.' "$FIXTURE_OUTPUT" ||
        fail "skip mode did not report degraded completion"

    run_installer success --skip-mise-runtimes

    assert_non_mise_links
    assert_not_exists "$FIXTURE_HOME/.config/mise/conf.d/00-dotfiles.toml"
    assert_linux_native_install_once yum
    assert_log_count 0 "mise dry-run" "$FIXTURE_LOG"
    assert_log_count 0 "mise install" "$FIXTURE_LOG"
    assert_log_count 0 "mise activate" "$FIXTURE_LOG"
    pass "yum setup can skip Mise runtimes and remains idempotent"
}

test_skip_mise_runtimes_retains_existing_manifest() {
    new_fixture skip-mise-existing Darwin
    run_installer

    run_installer success --skip-mise-runtimes

    assert_common_links
    assert_log_count 1 "mise install" "$FIXTURE_LOG"
    pass "skip mode retains an existing managed Mise fragment"
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
    for source_name in fish ghostty herdr hunk lazygit nvim tmux docs zsh; do
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

    new_fixture missing-workflow Darwin
    fixture_repo="$FIXTURE_ROOT/repo"
    mkdir -p "$fixture_repo"
    cp "$REPO_ROOT/install.sh" "$REPO_ROOT/Brewfile" "$fixture_repo/"
    for source_name in fish ghostty herdr hunk lazygit mise nvim tmux templates zsh; do
        ln -s "$REPO_ROOT/$source_name" "$fixture_repo/$source_name"
    done
    FIXTURE_INSTALL_REPO_ROOT="$(cd "$fixture_repo" && pwd -P)"

    run_installer failure --skip-mise-runtimes

    grep -Fq \
        "missing or invalid tracked configuration file: $FIXTURE_INSTALL_REPO_ROOT/docs/agents/development-workflow.md" \
        "$FIXTURE_OUTPUT" ||
        fail "installer did not preflight the shared workflow source"
    assert_log_count 0 "brew bootstrap" "$FIXTURE_LOG"
    assert_not_exists "$FIXTURE_HOME/.config"
    pass "link preflight fails before changing home configuration"
}

test_checkout_overlap_is_rejected_before_provisioning() {
    local placement source_name fixture_repo
    for placement in .config .config/fish/dotfiles; do
        new_fixture "checkout-overlap-${placement//\//-}" Darwin
        fixture_repo="$FIXTURE_HOME/$placement"
        mkdir -p "$fixture_repo"
        cp "$REPO_ROOT/install.sh" "$REPO_ROOT/Brewfile" "$fixture_repo/"
        for source_name in fish ghostty herdr hunk lazygit mise nvim tmux docs templates zsh; do
            cp -R "$REPO_ROOT/$source_name" "$fixture_repo/$source_name"
        done
        FIXTURE_INSTALL_REPO_ROOT="$(cd -P "$fixture_repo" && pwd -P)"
        run_installer failure
        grep -Fq 'overlaps an installation target' "$FIXTURE_OUTPUT" ||
            fail "source/destination overlap did not produce a useful diagnostic"
        [[ -d "$fixture_repo/fish" && ! -L "$fixture_repo/fish" ]] ||
            fail "overlap preflight changed its source"
        assert_log_count 0 'brew bootstrap' "$FIXTURE_LOG"
        assert_not_exists "$FIXTURE_HOME/.zshrc"
    done

    new_fixture workflow-home-alias-overlap Darwin
    ln -s "$FIXTURE_HOME" "$FIXTURE_ROOT/home-alias"
    FIXTURE_CODEX_DIRECTORY="$FIXTURE_HOME/.config/nvim/agent"
    run_installer failure "$FIXTURE_ROOT/home-alias"
    grep -Fq 'agent configuration directory overlaps a managed link' "$FIXTURE_OUTPUT" ||
        fail "physical HOME alias bypassed overlap preflight"
    assert_log_count 0 'brew bootstrap' "$FIXTURE_LOG"
    assert_not_exists "$FIXTURE_HOME/.config"
    pass "checkout and HOME-alias overlaps fail before provisioning or link changes"
}

test_local_templates_are_published_complete_without_overwriting() {
    local target template
    new_fixture template-copy-failure Darwin
    # Interrupt only a template copy, after writing a partial staging file.
    unlink "$FIXTURE_FAKE_BIN/cp"
    cat >"$FIXTURE_FAKE_BIN/cp" <<'SCRIPT'
#!/usr/bin/env bash
if [[ "$1" == */templates/local.fish ]]; then
    printf 'partial template\n' >"$2"
    exit 1
fi
exec /bin/cp "$@"
SCRIPT
    chmod +x "$FIXTURE_FAKE_BIN/cp"
    run_installer failure --skip-mise-runtimes
    assert_not_exists "$FIXTURE_HOME/.local/share/dotfiles/local.fish"
    assert_not_exists "$FIXTURE_HOME/.local/share/dotfiles/local.zsh"
    for target in "$FIXTURE_HOME/.local/share/dotfiles"/.template.*; do
        assert_not_exists "$target"
    done
    unlink "$FIXTURE_FAKE_BIN/cp"
    ln -s /bin/cp "$FIXTURE_FAKE_BIN/cp"
    run_installer success --skip-mise-runtimes
    for template in local.fish local.zsh; do
        cmp "$REPO_ROOT/templates/$template" "$FIXTURE_HOME/.local/share/dotfiles/$template" ||
            fail "retry did not publish the complete template"
    done

    new_fixture template-concurrent-user-file Darwin
    unlink "$FIXTURE_FAKE_BIN/cp"
    cat >"$FIXTURE_FAKE_BIN/cp" <<'SCRIPT'
#!/usr/bin/env bash
/bin/cp "$@" || exit
if [[ "$1" == */templates/local.fish ]]; then
    printf 'concurrent user content\n' >"$HOME/.local/share/dotfiles/local.fish"
fi
SCRIPT
    chmod +x "$FIXTURE_FAKE_BIN/cp"
    run_installer success --skip-mise-runtimes
    grep -Fxq 'concurrent user content' "$FIXTURE_HOME/.local/share/dotfiles/local.fish" ||
        fail "publishing the template overwrote a concurrent user file"
    run_installer success --skip-mise-runtimes
    grep -Fxq 'concurrent user content' "$FIXTURE_HOME/.local/share/dotfiles/local.fish" ||
        fail "second run changed a user template"
    pass "local template publication is complete, retryable, and preserves user files"
}

test_broken_font_links_do_not_count_as_installed() {
    new_fixture missing-font-link Darwin
    ln -s "$FIXTURE_ROOT/missing-font.ttf" "$FIXTURE_FONT_DIR/JetBrainsMono-Broken.ttf"
    run_installer
    assert_log_count 1 'brew cask install font-jetbrains-mono' "$FIXTURE_LOG"
    assert_symlink "$FIXTURE_FONT_DIR/JetBrainsMono-Broken.ttf" "$FIXTURE_ROOT/missing-font.ttf"

    new_fixture missing-recorded-font Darwin
    : >"$FIXTURE_STATE/cask-font-jetbrains-mono"
    ln -s "$FIXTURE_ROOT/missing-font.ttf" "$FIXTURE_FONT_DIR/JetBrainsMono-Broken.ttf"
    run_installer failure
    grep -Fq 'its font files are missing; repair the cask' "$FIXTURE_OUTPUT" ||
        fail "broken recorded font was not rejected with a repair diagnostic"
    assert_not_exists "$FIXTURE_HOME/.config"
    pass "broken font links trigger installation or an explicit cask repair"
}

test_workflow_links_preserve_personal_guidance() {
    new_fixture workflow-personal-guidance Darwin
    mkdir -p "$FIXTURE_HOME/.claude/skills/personal" "$FIXTURE_HOME/.agents/skills/personal"
    printf 'personal Claude instructions\n' >"$FIXTURE_HOME/.claude/CLAUDE.md"
    printf 'personal skill\n' >"$FIXTURE_HOME/.claude/skills/personal/SKILL.md"
    printf 'shared personal skill\n' >"$FIXTURE_HOME/.agents/skills/personal/SKILL.md"

    run_installer success --skip-mise-runtimes
    assert_workflow_links
    grep -Fxq 'personal Claude instructions' "$FIXTURE_HOME/.claude/CLAUDE.md" ||
        fail "installation changed personal Claude guidance"
    grep -Fxq 'personal skill' "$FIXTURE_HOME/.claude/skills/personal/SKILL.md" ||
        fail "installation changed Claude skills"
    grep -Fxq 'shared personal skill' "$FIXTURE_HOME/.agents/skills/personal/SKILL.md" ||
        fail "installation changed shared skills"
    run_installer success --skip-mise-runtimes
    if grep -Eq 'linked:|backed up:' "$FIXTURE_OUTPUT"; then
        fail "unchanged workflow links were not a no-op"
    fi
    run_uninstaller 0
    assert_common_links_removed
    grep -Fxq 'personal Claude instructions' "$FIXTURE_HOME/.claude/CLAUDE.md" ||
        fail "uninstallation changed personal Claude guidance"
    assert_exists "$FIXTURE_HOME/.claude/skills/personal/SKILL.md"
    assert_exists "$FIXTURE_HOME/.agents/skills/personal/SKILL.md"
    pass "shared workflow links preserve personal guidance and skill directories"
}

test_workflow_preflight_preserves_active_instructions() {
    local target
    for target in .codex/AGENTS.md .pi/agent/AGENTS.md .claude/rules/development-workflow.md; do
        new_fixture "workflow-conflict-${target//\//-}" Darwin
        mkdir -p "$(dirname "$FIXTURE_HOME/$target")"
        printf 'personal active instructions\n' >"$FIXTURE_HOME/$target"
        run_installer failure --skip-mise-runtimes
        grep -Fq 'existing global instructions must remain active' "$FIXTURE_OUTPUT" ||
            fail "global instruction conflict was not actionable"
        grep -Fxq 'personal active instructions' "$FIXTURE_HOME/$target" ||
            fail "existing active instructions were changed"
        assert_not_exists "$FIXTURE_HOME/.config"
        assert_log_count 0 "brew bootstrap" "$FIXTURE_LOG"
    done

    new_fixture workflow-legacy-claude Darwin
    mkdir -p "$FIXTURE_HOME/.claude"
    printf '%s\n' 'personal instructions' '<!-- dotfiles-devflow:begin v1 -->' 'old workflow' \
        >"$FIXTURE_HOME/.claude/CLAUDE.md"
    run_installer failure
    grep -Fq 'retire the legacy dotfiles-devflow block' "$FIXTURE_OUTPUT" ||
        fail "legacy workflow instructions did not produce a migration diagnostic"
    grep -Fxq 'personal instructions' "$FIXTURE_HOME/.claude/CLAUDE.md" ||
        fail "legacy workflow preflight changed personal content"
    assert_not_exists "$FIXTURE_HOME/.config"
    assert_log_count 0 "brew bootstrap" "$FIXTURE_LOG"

    new_fixture workflow-codex-override Darwin
    mkdir -p "$FIXTURE_HOME/.codex"
    printf 'override instructions\n' >"$FIXTURE_HOME/.codex/AGENTS.override.md"
    run_installer failure
    grep -Fq 'AGENTS.override.md shadows the shared workflow' "$FIXTURE_OUTPUT" ||
        fail "Codex override shadowing did not produce an actionable diagnostic"
    assert_not_exists "$FIXTURE_HOME/.config"
    assert_log_count 0 "brew bootstrap" "$FIXTURE_LOG"
    pass "conflicting active and legacy guidance is preserved before installation"
}

test_workflow_custom_roots_and_equivalent_links() {
    new_fixture workflow-custom-roots Darwin
    FIXTURE_CODEX_DIRECTORY="$FIXTURE_ROOT/custom/codex/"
    FIXTURE_PI_DIRECTORY="$FIXTURE_ROOT/custom/pi/"
    printf 'unrelated default pi path\n' >"$FIXTURE_HOME/.pi"
    run_installer success --skip-mise-runtimes
    assert_workflow_links
    assert_not_exists "$FIXTURE_HOME/.codex"
    grep -Fxq 'unrelated default pi path' "$FIXTURE_HOME/.pi" ||
        fail "configured pi root did not leave the default path alone"
    run_installer success --skip-mise-runtimes
    if grep -Eq 'linked:|backed up:' "$FIXTURE_OUTPUT"; then
        fail "custom global roots were not idempotent"
    fi
    run_uninstaller 0
    assert_common_links_removed

    new_fixture workflow-relative-link Darwin
    mkdir -p "$FIXTURE_HOME/.codex"
    ln -s "$REPO_ROOT" "$FIXTURE_ROOT/repo-alias"
    ln -s ../../repo-alias/docs/agents/development-workflow.md \
        "$FIXTURE_HOME/.codex/AGENTS.md"
    run_installer success --skip-mise-runtimes
    assert_eq '../../repo-alias/docs/agents/development-workflow.md' \
        "$(readlink "$FIXTURE_HOME/.codex/AGENTS.md")" \
        "equivalent global instruction link was replaced"
    run_uninstaller 0
    assert_not_exists "$FIXTURE_HOME/.codex/AGENTS.md"
    pass "configured harness roots and path-equivalent instruction links are supported"
}

test_workflow_roots_are_validated_before_writes() {
    local target setting unsafe_root
    for target in .codex .pi .pi/agent .claude .claude/rules; do
        new_fixture "workflow-blocked-${target//\//-}" Darwin
        mkdir -p "$(dirname "$FIXTURE_HOME/$target")"
        printf 'blocking user file\n' >"$FIXTURE_HOME/$target"
        run_installer failure --skip-mise-runtimes
        grep -Fq 'blocks required configuration directory' "$FIXTURE_OUTPUT" ||
            fail "blocked workflow parent did not produce a useful diagnostic"
        grep -Fxq 'blocking user file' "$FIXTURE_HOME/$target" ||
            fail "blocked parent was changed"
        assert_not_exists "$FIXTURE_HOME/.config"
        assert_log_count 0 "brew bootstrap" "$FIXTURE_LOG"
    done
    for setting in codex pi; do
        for unsafe_root in '' / relative /tmp/../unsafe /./; do
            new_fixture "workflow-unsafe-$setting-${unsafe_root//\//-}" Darwin
            if [[ "$setting" == codex ]]; then
                FIXTURE_CODEX_DIRECTORY="$unsafe_root"
            else
                FIXTURE_PI_DIRECTORY="$unsafe_root"
            fi
            run_installer failure
            assert_not_exists "$FIXTURE_HOME/.config"
            assert_log_count 0 "brew bootstrap" "$FIXTURE_LOG"
            run_uninstaller 1
        done
    done
    new_fixture workflow-custom-blocked-parent Darwin
    printf 'blocking ancestor\n' >"$FIXTURE_ROOT/blocked"
    FIXTURE_CODEX_DIRECTORY="$FIXTURE_ROOT/blocked/codex"
    run_installer failure
    assert_not_exists "$FIXTURE_HOME/.config"
    assert_log_count 0 "brew bootstrap" "$FIXTURE_LOG"
    new_fixture workflow-redirected-root Darwin
    mkdir -p "$FIXTURE_HOME/redirected"
    ln -s "$FIXTURE_HOME/redirected" "$FIXTURE_HOME/.codex"
    FIXTURE_CODEX_DIRECTORY="$FIXTURE_HOME/.codex/"
    run_installer failure
    grep -Fq 'agent configuration directory is a symlink' "$FIXTURE_OUTPUT" ||
        fail "trailing slash bypassed the redirected harness root check"
    assert_not_exists "$FIXTURE_HOME/redirected/AGENTS.md"
    assert_log_count 0 "brew bootstrap" "$FIXTURE_LOG"
    new_fixture workflow-custom-redirected-parent Darwin
    mkdir -p "$FIXTURE_HOME/another-profile/codex"
    ln -s "$FIXTURE_HOME/another-profile" "$FIXTURE_HOME/profiles"
    FIXTURE_CODEX_DIRECTORY="$FIXTURE_HOME/profiles/codex"
    run_installer failure
    grep -Fq 'agent configuration directory is a symlink' "$FIXTURE_OUTPUT" ||
        fail "custom root ancestor redirect was not rejected"
    assert_not_exists "$FIXTURE_HOME/another-profile/codex/AGENTS.md"
    assert_log_count 0 "brew bootstrap" "$FIXTURE_LOG"

    for target in .config/nvim .config/fish/nested .zshrc .claude/rules/development-workflow.md; do
        new_fixture "workflow-overlap-${target//\//-}" Darwin
        FIXTURE_CODEX_DIRECTORY="$FIXTURE_HOME//$target/"
        run_installer failure
        grep -Fq 'agent configuration directory overlaps a managed link' "$FIXTURE_OUTPUT" ||
            fail "custom root overlapping a managed destination was not rejected"
        assert_not_exists "$FIXTURE_HOME/.config"
        assert_log_count 0 "brew bootstrap" "$FIXTURE_LOG"
    done
    new_fixture workflow-overlap-instruction-file Darwin
    FIXTURE_CODEX_DIRECTORY="$FIXTURE_PI_DIRECTORY/AGENTS.md"
    run_installer failure
    grep -Fq 'agent configuration directories overlap an instruction file' "$FIXTURE_OUTPUT" ||
        fail "custom root overlapping another instruction file was not rejected"
    assert_not_exists "$FIXTURE_HOME/.pi"
    assert_log_count 0 "brew bootstrap" "$FIXTURE_LOG"
    pass "workflow roots and all required parents are checked before any writes"
}

test_workflow_uninstall_preserves_foreign_and_redirected_state() {
    local target mode
    new_fixture workflow-uninstall-foreign Darwin
    run_installer success --skip-mise-runtimes
    mv "$FIXTURE_HOME/.codex/AGENTS.md" "$FIXTURE_STATE/codex-link"
    printf 'replacement personal instructions\n' >"$FIXTURE_HOME/.codex/AGENTS.md"
    printf 'older personal instructions\n' >"$FIXTURE_HOME/.codex/AGENTS.md.bak.1"
    run_uninstaller 0 --restore
    grep -Fxq 'replacement personal instructions' "$FIXTURE_HOME/.codex/AGENTS.md" ||
        fail "uninstall replaced active personal instructions"
    assert_exists "$FIXTURE_HOME/.codex/AGENTS.md.bak.1"

    for target in .codex .pi/agent .claude/rules; do
        for mode in remove restore; do
            new_fixture "workflow-redirect-${target//\//-}-$mode" Darwin
            run_installer success --skip-mise-runtimes
            mv "$FIXTURE_HOME/$target" "$FIXTURE_HOME/redirected"
            ln -s "$FIXTURE_HOME/redirected" "$FIXTURE_HOME/$target"
            if [[ "$mode" == restore ]]; then
                run_uninstaller 0 --restore
            else
                run_uninstaller 0
            fi
            if [[ "$target" == .claude/rules ]]; then
                assert_symlink "$FIXTURE_HOME/redirected/development-workflow.md" \
                    "$REPO_ROOT/docs/agents/development-workflow.md"
            else
                assert_symlink "$FIXTURE_HOME/redirected/AGENTS.md" \
                    "$REPO_ROOT/docs/agents/development-workflow.md"
            fi
        done
    done
    for mode in remove restore; do
        new_fixture "workflow-uninstall-custom-redirect-$mode" Darwin
        FIXTURE_CODEX_DIRECTORY="$FIXTURE_HOME/profiles/codex"
        mkdir -p "$FIXTURE_HOME/another-profile/codex"
        ln -s "$FIXTURE_HOME/another-profile" "$FIXTURE_HOME/profiles"
        ln -s "$REPO_ROOT/docs/agents/development-workflow.md" \
            "$FIXTURE_HOME/another-profile/codex/AGENTS.md"
        if [[ "$mode" == restore ]]; then
            run_uninstaller 0 --restore
        else
            run_uninstaller 0
        fi
        assert_symlink "$FIXTURE_HOME/another-profile/codex/AGENTS.md" \
            "$REPO_ROOT/docs/agents/development-workflow.md"
    done
    pass "uninstall preserves foreign guidance and does not follow redirected harness containers"
}

test_workflow_restore_uses_only_latest_unambiguous_backups() {
    local target
    new_fixture workflow-restore Darwin
    run_installer success --skip-mise-runtimes
    for target in "$FIXTURE_HOME/.codex/AGENTS.md" "$FIXTURE_HOME/.pi/agent/AGENTS.md" \
        "$FIXTURE_HOME/.claude/rules/development-workflow.md"
    do
        printf 'older personal instructions\n' >"$target.bak.1"
        printf 'newest personal instructions\n' >"$target.bak.2"
    done
    run_uninstaller 0 --restore
    for target in "$FIXTURE_HOME/.codex/AGENTS.md" "$FIXTURE_HOME/.pi/agent/AGENTS.md" \
        "$FIXTURE_HOME/.claude/rules/development-workflow.md"
    do
        grep -Fxq 'newest personal instructions' "$target" ||
            fail "newest instruction backup was not restored"
        assert_exists "$target.bak.1"
        assert_not_exists "$target.bak.2"
    done
    run_uninstaller 0 --restore
    grep -Fxq 'newest personal instructions' "$FIXTURE_HOME/.codex/AGENTS.md" ||
        fail "second restore changed user instructions"
    pass "workflow uninstallation restores only the newest safe leaf backup"
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
        'brew "cmake"'
        'brew "ninja"'
        'brew "uv"'
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

test_workflow_links_preserve_personal_guidance
test_workflow_preflight_preserves_active_instructions
test_workflow_custom_roots_and_equivalent_links
test_workflow_roots_are_validated_before_writes
test_workflow_uninstall_preserves_foreign_and_redirected_state
test_workflow_restore_uses_only_latest_unambiguous_backups
test_user_mise_config_does_not_override_bootstrap_manifest
test_mise_environment_cannot_override_bootstrap_manifest
test_parent_mise_activation_does_not_override_bootstrap_environment
test_unexpected_mise_sources_are_rejected_before_installing
test_non_mise_runtime_command_is_rejected_before_linking
test_mise_runtime_version_mismatch_is_rejected_before_linking
test_install_cli_is_safe
test_skip_mise_runtimes_completes_yum_setup
test_skip_mise_runtimes_retains_existing_manifest
test_macos_fresh_and_second_run
test_broken_font_links_do_not_count_as_installed
test_local_templates_are_published_complete_without_overwriting
test_linux_manager_fresh_and_second_run apt-get
test_linux_manager_fresh_and_second_run dnf
test_linux_manager_fresh_and_second_run yum
test_linux_manager_fresh_and_second_run pacman
test_unsupported_linux_package_manager
test_missing_cpp_compiler_installs_native_tools
test_broken_compilers_fail_before_provisioning
test_linux_handoff_is_validated_before_linking
test_compatible_jdk_vendor_is_accepted
test_incompatible_java_versions_are_rejected_before_linking
test_incompatible_tmux_is_rejected_before_linking
test_incompatible_git_tool_versions_are_rejected_before_linking
test_incompatible_neovim_versions_are_rejected_before_linking
test_newer_neovim_versions_are_accepted
test_neovim_check_failures_precede_configuration_links
test_uninstall_cli_is_safe
test_install_and_uninstall_reject_unsafe_homes
test_uninstall_removes_only_owned_links
test_uninstall_restores_latest_backups
test_uninstall_blocks_unsafe_or_ambiguous_restores
test_equivalent_relative_links_are_idempotent
test_link_preflight_prevents_partial_configuration
test_checkout_overlap_is_rejected_before_provisioning
test_dependency_manifests_match_the_install_contract
printf 'All install integration tests passed.\n'
