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

    cat >"$FIXTURE_FAKE_BIN/apt-get" <<'SCRIPT'
#!/usr/bin/env bash
printf 'apt-get %s\n' "$*" >>"$DOTFILES_TEST_LOG"
case " $* " in
    *" install "*)
        for command_name in cc make ps file git tar gzip unzip diff; do
            cp "$DOTFILES_TEST_GENERIC_TEMPLATE" "$DOTFILES_TEST_FAKE_BIN/$command_name"
            chmod +x "$DOTFILES_TEST_FAKE_BIN/$command_name"
        done
        ;;
esac
SCRIPT

    cat >"$FIXTURE_GENERIC_TEMPLATE" <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT

    cat >"$FIXTURE_MISE_TEMPLATE" <<'SCRIPT'
#!/usr/bin/env bash
write_runtime_commands() {
    local command_name
    for command_name in node npm python python3 rustc cargo clippy go java javac; do
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
        printf 'fish, version 4.0.2\n'
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
            *" --file="*)
                ;;
            *)
                printf 'brew bundle did not receive a Brewfile: %s\n' "$*" >&2
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
        printf '%s\n' "$DOTFILES_TEST_FAKE_BIN/.."
        ;;
    *)
        exit 0
        ;;
esac
SCRIPT

    chmod +x \
        "$FIXTURE_FAKE_BIN/apt-get" \
        "$FIXTURE_FAKE_BIN/curl" \
        "$FIXTURE_FAKE_BIN/sudo" \
        "$FIXTURE_FAKE_BIN/uname" \
        "$FIXTURE_FAKE_BIN/xcode-select" \
        "$FIXTURE_BREW_TEMPLATE" \
        "$FIXTURE_FORMULA_TEMPLATE" \
        "$FIXTURE_GENERIC_TEMPLATE" \
        "$FIXTURE_MISE_TEMPLATE" \
        "$FIXTURE_RUNTIME_TEMPLATE"
}

new_fixture() {
    local name="$1" os_name="$2"
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
    FIXTURE_OS="$os_name"
    if [[ "$os_name" == "Linux" ]]; then
        FIXTURE_SYSTEM_PATH=""
    else
        FIXTURE_SYSTEM_PATH="/usr/bin:/bin"
    fi

    mkdir -p \
        "$FIXTURE_HOME" \
        "$FIXTURE_FAKE_BIN" \
        "$FIXTURE_STATE" \
        "$FIXTURE_APPLICATION_DIR" \
        "$FIXTURE_FONT_DIR"
    : >"$FIXTURE_LOG"
    write_fake_commands
}

run_installer() {
    if env \
        HOME="$FIXTURE_HOME" \
        PATH="$FIXTURE_FAKE_BIN${FIXTURE_SYSTEM_PATH:+:$FIXTURE_SYSTEM_PATH}" \
        DOTFILES_BREW_PATHS="$FIXTURE_FAKE_BIN/brew" \
        DOTFILES_APPLICATION_DIRS="$FIXTURE_APPLICATION_DIR" \
        DOTFILES_FONT_DIRS="$FIXTURE_FONT_DIR" \
        DOTFILES_TEST_APPLICATION_DIR="$FIXTURE_APPLICATION_DIR" \
        DOTFILES_TEST_BREW_TEMPLATE="$FIXTURE_BREW_TEMPLATE" \
        DOTFILES_TEST_FAKE_BIN="$FIXTURE_FAKE_BIN" \
        DOTFILES_TEST_FONT_DIR="$FIXTURE_FONT_DIR" \
        DOTFILES_TEST_FORMULA_TEMPLATE="$FIXTURE_FORMULA_TEMPLATE" \
        DOTFILES_TEST_GENERIC_TEMPLATE="$FIXTURE_GENERIC_TEMPLATE" \
        DOTFILES_TEST_LOG="$FIXTURE_LOG" \
        DOTFILES_TEST_MISE_TEMPLATE="$FIXTURE_MISE_TEMPLATE" \
        DOTFILES_TEST_OS="$FIXTURE_OS" \
        DOTFILES_TEST_RUNTIME_TEMPLATE="$FIXTURE_RUNTIME_TEMPLATE" \
        DOTFILES_TEST_STATE="$FIXTURE_STATE" \
        "$REPO_ROOT/install.sh" >"$FIXTURE_OUTPUT" 2>&1
    then
        return
    fi

    sed 's/^/  | /' "$FIXTURE_OUTPUT" >&2
    fail "installer failed for the $FIXTURE_OS fixture"
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

test_debian_fresh_and_second_run() {
    new_fixture debian Linux

    run_installer

    assert_common_links
    assert_not_exists "$FIXTURE_HOME/.config/ghostty"
    assert_log_count 1 "apt-get update" "$FIXTURE_LOG"
    assert_log_prefix_count 1 "apt-get install " "$FIXTURE_LOG"
    assert_log_count 1 "brew bootstrap" "$FIXTURE_LOG"
    assert_log_count 1 "brew bundle install" "$FIXTURE_LOG"
    assert_log_count 1 "mise install" "$FIXTURE_LOG"
    assert_log_count 0 "brew cask install ghostty" "$FIXTURE_LOG"
    assert_log_count 0 "brew cask install font-jetbrains-mono" "$FIXTURE_LOG"
    assert_exists "$FIXTURE_FAKE_BIN/wl-copy"
    assert_exists "$FIXTURE_FAKE_BIN/xclip"

    run_installer

    assert_log_count 1 "apt-get update" "$FIXTURE_LOG"
    assert_log_prefix_count 1 "apt-get install " "$FIXTURE_LOG"
    assert_log_count 1 "brew bootstrap" "$FIXTURE_LOG"
    assert_log_count 1 "brew bundle install" "$FIXTURE_LOG"
    assert_log_count 1 "mise install" "$FIXTURE_LOG"
    assert_log_count 0 "brew cask install ghostty" "$FIXTURE_LOG"
    assert_log_count 0 "brew cask install font-jetbrains-mono" "$FIXTURE_LOG"
    assert_common_links
    pass "fresh Debian/apt provisioning and second-run no-op"
}

test_macos_fresh_and_second_run
test_debian_fresh_and_second_run
printf 'All install integration tests passed.\n'
