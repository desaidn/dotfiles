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
    for command_name in bash cat chmod cp date dirname env ln mkdir mv readlink; do
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
if [[ "${MISE_GLOBAL_CONFIG_FILE:-}" != "$DOTFILES_TEST_REPO_ROOT/mise/conf.d/00-dotfiles.toml" ]]; then
    printf 'mise received unexpected global config: %s\n' "${MISE_GLOBAL_CONFIG_FILE:-unset}" >&2
    exit 4
fi

write_runtime_commands() {
    local command_name
    for command_name in node npm python python3 rustc cargo clippy rustfmt go java javac; do
        cp "$DOTFILES_TEST_RUNTIME_TEMPLATE" "$DOTFILES_TEST_FAKE_BIN/$command_name"
        chmod +x "$DOTFILES_TEST_FAKE_BIN/$command_name"
    done
}

case "${1:-}" in
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
    *)
        exit 0
        ;;
esac
SCRIPT

    cat >"$FIXTURE_RUNTIME_TEMPLATE" <<'SCRIPT'
#!/usr/bin/env bash
case "${0##*/}" in
    java)
        printf 'openjdk version "21.0.8"\n' >&2
        ;;
    node)
        printf 'v24.4.1\n'
        ;;
    npm)
        printf '11.4.2\n'
        ;;
    python|python3)
        printf 'Python 3.13.5\n'
        ;;
    rustc)
        printf 'rustc 1.88.0\n'
        ;;
    cargo)
        printf 'cargo 1.88.0\n'
        ;;
    clippy)
        printf 'clippy 0.1.88\n'
        ;;
    rustfmt)
        printf 'rustfmt 1.8.0-stable\n'
        ;;
    go)
        printf 'go version go1.24.5 linux/amd64\n'
        ;;
    javac)
        printf 'javac 21.0.8\n'
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
        printf 'NVIM v0.12.4\n'
        ;;
    tmux)
        printf 'tmux 3.7b\n'
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
    for command_name in git fish zsh nvim herdr tmux lazygit atuin gh rg tree-sitter hunk uv ghcup wl-copy wl-paste xclip; do
        cp "$DOTFILES_TEST_FORMULA_TEMPLATE" "$DOTFILES_TEST_FAKE_BIN/$command_name"
        chmod +x "$DOTFILES_TEST_FAKE_BIN/$command_name"
    done
    cp "$DOTFILES_TEST_MISE_TEMPLATE" "$DOTFILES_TEST_FAKE_BIN/mise"
    chmod +x "$DOTFILES_TEST_FAKE_BIN/mise"
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
    printf '[tools]\n"core:java" = "temurin-8"\n' >"$FIXTURE_CALLER_DIR/mise.toml"
    write_fake_commands
}

run_installer() {
    local expected_result="${1:-success}"
    local run_home="$FIXTURE_HOME"
    if (( $# > 1 )); then
        run_home="$2"
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
            DOTFILES_TEST_RUNTIME_TEMPLATE="$FIXTURE_RUNTIME_TEMPLATE" \
            DOTFILES_TEST_STATE="$FIXTURE_STATE" \
            "$FIXTURE_INSTALL_REPO_ROOT/install.sh"
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

    if HOME="$FIXTURE_HOME" PATH="$FIXTURE_FAKE_BIN:/usr/bin:/bin" \
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

assert_common_links() {
    assert_symlink "$FIXTURE_HOME/.config/fish" "$REPO_ROOT/fish"
    assert_symlink "$FIXTURE_HOME/.config/herdr/config.toml" "$REPO_ROOT/herdr/config.toml"
    assert_symlink "$FIXTURE_HOME/.config/hunk/config.toml" "$REPO_ROOT/hunk/config.toml"
    assert_symlink "$FIXTURE_HOME/.config/lazygit" "$REPO_ROOT/lazygit"
    assert_symlink "$FIXTURE_HOME/.config/mise/conf.d/00-dotfiles.toml" "$REPO_ROOT/mise/conf.d/00-dotfiles.toml"
    assert_symlink "$FIXTURE_HOME/.config/nvim" "$REPO_ROOT/nvim"
    assert_symlink "$FIXTURE_HOME/.config/tmux" "$REPO_ROOT/tmux"
    assert_symlink "$FIXTURE_HOME/.zshrc" "$REPO_ROOT/zsh/.zshrc"
    assert_exists "$FIXTURE_HOME/.local/share/dotfiles/local.fish"
    assert_exists "$FIXTURE_HOME/.local/share/dotfiles/local.zsh"
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
                "dnf install -y procps-ng curl file git tar gzip unzip diffutils ca-certificates" \
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
    cp "$REPO_ROOT/mise/conf.d/00-dotfiles.toml" "$fixture_repo/mise/conf.d/"
    cp "$REPO_ROOT/templates/local.fish" "$REPO_ROOT/templates/local.zsh" \
        "$fixture_repo/templates/"
    for source_name in fish ghostty herdr hunk lazygit tmux zsh; do
        ln -s "$REPO_ROOT/$source_name" "$fixture_repo/$source_name"
    done
    FIXTURE_INSTALL_REPO_ROOT="$(cd "$fixture_repo" && pwd -P)"
    printf 'original zsh config\n' >"$FIXTURE_HOME/.zshrc"

    run_installer failure

    grep -Fq 'missing or invalid tracked configuration' "$FIXTURE_OUTPUT" ||
        fail "missing source failure was not actionable"
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
        '"core:python" = "3.14.6"'
        '"core:rust" = { version = "1.97.1", profile = "minimal", components = ["clippy", "rustfmt"] }'
        '"core:go" = "1.26.5"'
        '"core:java" = "temurin-21.0.11+10.0.LTS"'
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

test_macos_fresh_and_second_run
test_linux_manager_fresh_and_second_run apt-get
test_linux_manager_fresh_and_second_run dnf
test_linux_manager_fresh_and_second_run pacman
test_unsupported_linux_package_manager
test_linux_handoff_is_validated_before_linking
test_uninstall_cli_is_safe
test_install_and_uninstall_reject_unsafe_homes
test_uninstall_removes_only_owned_links
test_uninstall_restores_latest_backups
test_uninstall_blocks_unsafe_or_ambiguous_restores
test_equivalent_relative_links_are_idempotent
test_link_preflight_prevents_partial_configuration
test_dependency_manifests_match_the_install_contract
printf 'All install integration tests passed.\n'
