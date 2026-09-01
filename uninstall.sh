#!/usr/bin/env bash
set -euo pipefail

usage() {
    printf 'Usage: %s [--restore]\n' "${0##*/}"
    printf '       %s --help\n' "${0##*/}"
}

RESTORE_BACKUPS=0
case "$#" in
    0)
        ;;
    1)
        case "$1" in
            --restore)
                RESTORE_BACKUPS=1
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

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

[[ -n "${HOME:-}" ]] || die "HOME is not set"
[[ "$HOME" == /* && -d "$HOME" ]] ||
    die "HOME must be an absolute user directory"
HOME_DIRECTORY="$(cd -P -- "$HOME" 2>/dev/null && pwd -P)" ||
    die "HOME must be an accessible user directory"
[[ "$HOME_DIRECTORY" != "/" ]] ||
    die "HOME must not resolve to the filesystem root"
(( EUID != 0 )) ||
    die "do not run this uninstaller as root; run it as the user whose dotfiles are being removed"

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_DIR="$HOME/.local/share/dotfiles"
DEVFLOW_SOURCE="$REPO_ROOT/tools/devflow"
DEVFLOW_DISTRIBUTION="dotfiles-devflow"
DEVFLOW_TOOL_DIR="$LOCAL_DIR/uv-tools"
DEVFLOW_TOOL_ENV="$DEVFLOW_TOOL_DIR/$DEVFLOW_DISTRIBUTION"
DEVFLOW_BIN_DIR="$HOME/.local/bin"
DEVFLOW_RECEIPT="$LOCAL_DIR/devflow-tool.receipt"
DEVFLOW_RECEIPT_SOURCE=""
DEVFLOW_RECEIPT_PYTHON=""

symlink_points_to() {
    [[ -L "$1" && "$1" -ef "$2" ]]
}

remove_owned() {
    local src="$REPO_ROOT/$1" dst="$HOME/$2" container="${3:-}"

    if [[ -n "$container" && -L "$HOME/$container" ]]; then
        echo "  parent is a symlink: $HOME/$container (skipping)"
        return
    fi
    if [[ ! -L "$dst" ]]; then
        echo "  not a symlink:    $dst (skipping)"
        return
    fi
    if ! symlink_points_to "$dst" "$src"; then
        echo "  points elsewhere: $dst (skipping)"
        return
    fi
    rm "$dst"
    echo "  removed:          $dst"
}

load_devflow_receipt() {
    local line
    local lines=()

    [[ -f "$DEVFLOW_RECEIPT" && ! -L "$DEVFLOW_RECEIPT" ]] || return 1
    while IFS= read -r line; do
        lines+=("$line")
    done <"$DEVFLOW_RECEIPT"
    [[ ${#lines[@]} == 3 ]] || return 1
    [[ "${lines[0]}" == "dotfiles-devflow-v2" ]] || return 1
    [[ "${lines[1]}" == "$DEVFLOW_SOURCE" && -n "${lines[2]}" ]] ||
        return 1
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

devflow_state_exists() {
    if [[ -e "$DEVFLOW_RECEIPT" || -L "$DEVFLOW_RECEIPT" ||
        -e "$DEVFLOW_TOOL_ENV" || -L "$DEVFLOW_TOOL_ENV" ]]
    then
        return 0
    fi
    [[ -e "$DEVFLOW_BIN_DIR/devflow" || -L "$DEVFLOW_BIN_DIR/devflow" ]]
}

devflow_state_is_owned() {
    load_devflow_receipt || return 1
    [[ -d "$DEVFLOW_TOOL_ENV" && ! -L "$DEVFLOW_TOOL_ENV" ]] || return 1
    devflow_environment_matches \
        "$DEVFLOW_RECEIPT_PYTHON" \
        "$DEVFLOW_RECEIPT_SOURCE" || return 1
    symlink_points_to \
        "$DEVFLOW_BIN_DIR/devflow" \
        "$DEVFLOW_TOOL_ENV/bin/devflow"
}

run_devflow_uv() (
    clear_devflow_resolver_environment
    export UV_TOOL_DIR="$DEVFLOW_TOOL_DIR"
    export UV_TOOL_BIN_DIR="$DEVFLOW_BIN_DIR"
    uv --no-config "$@"
)

remove_owned_devflow() {
    if ! devflow_state_exists; then
        echo "  not installed:    $DEVFLOW_DISTRIBUTION"
        return 0
    fi
    if ! devflow_state_is_owned; then
        echo "  ownership unclear: $DEVFLOW_DISTRIBUTION (preserving)"
        return 0
    fi
    if ! command -v uv >/dev/null 2>&1; then
        echo "  removal blocked:  uv is unavailable; preserving $DEVFLOW_DISTRIBUTION"
        RESTORE_STATUS=1
        return 0
    fi

    if ! run_devflow_uv tool uninstall "$DEVFLOW_DISTRIBUTION"
    then
        echo "  removal blocked:  uv could not uninstall $DEVFLOW_DISTRIBUTION"
        RESTORE_STATUS=1
        return 0
    fi

    if [[ -e "$DEVFLOW_TOOL_ENV" || -L "$DEVFLOW_TOOL_ENV" ]]; then
        echo "  removal blocked:  Workflow Engine environment remains after uv completed"
        RESTORE_STATUS=1
        return 0
    fi
    if [[ -e "$DEVFLOW_BIN_DIR/devflow" ||
        -L "$DEVFLOW_BIN_DIR/devflow" ]]
    then
        echo "  removal blocked:  Workflow Engine executable remains: $DEVFLOW_BIN_DIR/devflow"
        RESTORE_STATUS=1
        return 0
    fi

    rm "$DEVFLOW_RECEIPT"
    echo "  removed:          $DEVFLOW_DISTRIBUTION"
}

find_latest_backup() {
    local original="$1" candidate timestamp
    LATEST_BACKUP=""
    LATEST_BACKUP_AMBIGUOUS=0
    LATEST_TIMESTAMP=0

    for candidate in "$original".bak.*; do
        [[ -e "$candidate" || -L "$candidate" ]] || continue
        timestamp="${candidate##*.bak.}"
        case "$timestamp" in
            ''|*[!0-9]*)
                continue
                ;;
        esac
        while [[ ${#timestamp} -gt 1 && "${timestamp:0:1}" == "0" ]]; do
            timestamp="${timestamp#0}"
        done
        if [[ -z "$LATEST_BACKUP" ]] || (( timestamp > LATEST_TIMESTAMP )); then
            LATEST_BACKUP="$candidate"
            LATEST_TIMESTAMP="$timestamp"
            LATEST_BACKUP_AMBIGUOUS=0
        elif (( timestamp == LATEST_TIMESTAMP )); then
            LATEST_BACKUP_AMBIGUOUS=1
        fi
    done
}

mark_restore_blocked() {
    echo "  restore blocked:  $1"
    RESTORE_STATUS=1
}

move_backup() {
    local backup="$1" destination="$2"

    if [[ -e "$destination" || -L "$destination" ]]; then
        return 1
    fi
    mkdir -p "$(dirname "$destination")" || return 1
    mv -n "$backup" "$destination" || return 1
    [[ ! -e "$backup" && ! -L "$backup" ]]
}

restore_direct() {
    local source_rel="$1" target_rel="$2"
    local source="$REPO_ROOT/$source_rel" target="$HOME/$target_rel"
    local backup="" removed_owned=0

    find_latest_backup "$target"
    backup="$LATEST_BACKUP"
    if (( LATEST_BACKUP_AMBIGUOUS == 1 )); then
        mark_restore_blocked "$target has multiple newest numeric backups"
        return
    fi

    if [[ -e "$target" || -L "$target" ]]; then
        if ! symlink_points_to "$target" "$source"; then
            echo "  restore skipped:  $target is occupied"
            return
        fi
    fi

    if [[ -z "$backup" ]]; then
        remove_owned "$source_rel" "$target_rel"
        return
    fi

    if symlink_points_to "$backup" "$source"; then
        mark_restore_blocked "$backup points to the managed repository source"
        return
    fi

    if symlink_points_to "$target" "$source"; then
        rm "$target"
        removed_owned=1
        echo "  removed:          $target"
    fi

    if move_backup "$backup" "$target"; then
        echo "  restored:         $target"
        return
    fi

    mark_restore_blocked "$backup could not be restored to $target"
    if (( removed_owned == 1 )) &&
        [[ ! -e "$target" && ! -L "$target" ]] &&
        ln -s "$source" "$target"
    then
        echo "  retained:         $target"
    fi
}

directory_has_other_entries() {
    local directory="$1" allowed="$2" entry

    for entry in "$directory"/* "$directory"/.[!.]* "$directory"/..?*; do
        [[ -e "$entry" || -L "$entry" ]] || continue
        [[ "$entry" == "$allowed" ]] || return 0
    done
    return 1
}

restore_container_backup() {
    local source="$1" target="$2" container="$3" backup="$4"
    local removed_owned=0

    if [[ -e "$container" || -L "$container" ]]; then
        if [[ -L "$container" || ! -d "$container" ]]; then
            echo "  restore skipped:  $container is occupied"
            return
        fi
        if [[ -e "$target" || -L "$target" ]] &&
            ! symlink_points_to "$target" "$source"
        then
            mark_restore_blocked "$target contains unmanaged state"
            return
        fi
        if directory_has_other_entries "$container" "$target"; then
            mark_restore_blocked "$container contains user-owned entries"
            return
        fi
    fi

    if symlink_points_to "$target" "$source"; then
        rm "$target"
        removed_owned=1
    fi
    if [[ -d "$container" && ! -L "$container" ]] &&
        ! rmdir "$container" 2>/dev/null
    then
        if (( removed_owned == 1 )); then
            ln -s "$source" "$target"
        fi
        mark_restore_blocked "$container changed while restoration was prepared"
        return
    fi

    if move_backup "$backup" "$container"; then
        (( removed_owned == 0 )) || echo "  removed:          $target"
        echo "  restored:         $container"
        return
    fi

    if (( removed_owned == 1 )) &&
        [[ ! -e "$container" && ! -L "$container" ]]
    then
        mkdir -p "$container"
        ln -s "$source" "$target"
    fi
    mark_restore_blocked "$backup could not be restored to $container"
}

restore_leaf_backup() {
    local source="$1" target="$2" container="$3" backup="$4"
    local removed_owned=0 created_container=0

    if [[ -L "$container" || ( -e "$container" && ! -d "$container" ) ]]; then
        echo "  restore skipped:  $container is occupied"
        return
    fi
    if [[ -e "$target" || -L "$target" ]] &&
        ! symlink_points_to "$target" "$source"
    then
        echo "  restore skipped:  $target is occupied"
        return
    fi
    if symlink_points_to "$backup" "$source"; then
        mark_restore_blocked "$backup points to the managed repository source"
        return
    fi

    if [[ ! -d "$container" ]]; then
        mkdir -p "$container"
        created_container=1
    fi
    if symlink_points_to "$target" "$source"; then
        rm "$target"
        removed_owned=1
        echo "  removed:          $target"
    fi

    if move_backup "$backup" "$target"; then
        echo "  restored:         $target"
        return
    fi

    if (( removed_owned == 1 )) &&
        [[ ! -e "$target" && ! -L "$target" ]]
    then
        ln -s "$source" "$target"
    elif (( created_container == 1 )); then
        rmdir "$container" 2>/dev/null || true
    fi
    mark_restore_blocked "$backup could not be restored to $target"
}

restore_nested() {
    local source_rel="$1" target_rel="$2" container_rel="$3"
    local source="$REPO_ROOT/$source_rel"
    local target="$HOME/$target_rel" container="$HOME/$container_rel"
    local leaf_backup="" container_backup=""

    find_latest_backup "$container"
    container_backup="$LATEST_BACKUP"
    if (( LATEST_BACKUP_AMBIGUOUS == 1 )); then
        mark_restore_blocked "$container has multiple newest numeric backups"
        return
    fi

    if [[ -L "$container" ]]; then
        echo "  parent is a symlink: $container (skipping)"
        return
    fi

    find_latest_backup "$target"
    leaf_backup="$LATEST_BACKUP"
    if (( LATEST_BACKUP_AMBIGUOUS == 1 )); then
        mark_restore_blocked "$target has multiple newest numeric backups"
        return
    fi

    if [[ -n "$leaf_backup" && -n "$container_backup" ]]; then
        mark_restore_blocked "$target has both leaf and container backups"
        return
    fi

    if [[ -n "$container_backup" ]]; then
        restore_container_backup "$source" "$target" "$container" "$container_backup"
    elif [[ -n "$leaf_backup" ]]; then
        restore_leaf_backup "$source" "$target" "$container" "$leaf_backup"
    else
        remove_owned "$source_rel" "$target_rel" "$container_rel"
    fi
}

RESTORE_STATUS=0
remove_owned_devflow
if (( RESTORE_BACKUPS == 1 )); then
    echo "Restoring the newest unambiguous backups:"
    restore_direct fish .config/fish
    restore_direct ghostty .config/ghostty
    restore_nested herdr/config.toml .config/herdr/config.toml .config/herdr
    restore_nested hunk/config.toml .config/hunk/config.toml .config/hunk
    restore_direct lazygit .config/lazygit
    restore_nested \
        mise/conf.d/00-dotfiles.toml \
        .config/mise/conf.d/00-dotfiles.toml \
        .config/mise/conf.d
    restore_direct nvim .config/nvim
    restore_direct tmux .config/tmux
    restore_direct zsh/.zshrc .zshrc
else
    remove_owned fish .config/fish
    remove_owned ghostty .config/ghostty
    remove_owned herdr/config.toml .config/herdr/config.toml .config/herdr
    remove_owned hunk/config.toml .config/hunk/config.toml .config/hunk
    remove_owned lazygit .config/lazygit
    remove_owned \
        mise/conf.d/00-dotfiles.toml \
        .config/mise/conf.d/00-dotfiles.toml \
        .config/mise/conf.d
    remove_owned nvim .config/nvim
    remove_owned tmux .config/tmux
    remove_owned zsh/.zshrc .zshrc
fi

echo
echo "Backups (if any) remain at:"
shopt -s nullglob
backups=(
    "$HOME"/.config/*.bak.*
    "$HOME"/.config/herdr/config.toml.bak.*
    "$HOME"/.config/hunk/config.toml.bak.*
    "$HOME"/.config/mise/conf.d.bak.*
    "$HOME"/.config/mise/conf.d/00-dotfiles.toml.bak.*
    "$HOME"/.zshrc.bak.*
)
shopt -u nullglob
if (( ${#backups[@]} > 0 )); then
    printf '  %s\n' "${backups[@]}"
else
    echo "  (none)"
fi
echo
echo "Other per-machine files at \$HOME/.local/share/dotfiles/ were left untouched."
exit "$RESTORE_STATUS"
