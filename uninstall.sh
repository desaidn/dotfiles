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

# Keep the user-path boundary self-contained, matching install.sh.
validate_agent_directory() {
    local directory="$1" setting="$2"
    [[ "$directory" == /* && "$directory" != / ]] ||
        die "$setting must name an absolute directory other than /"
    case "$directory/" in
        */./*|*/../*)
            die "$setting must not contain . or .. path components"
            ;;
    esac
    if [[ -d "$directory" && "$(cd -P -- "$directory" && pwd -P)" == / ]]; then
        die "$setting must not resolve to the filesystem root"
    fi
}
validate_agent_directory "$CODEX_DIRECTORY" CODEX_HOME
validate_agent_directory "$PI_DIRECTORY" PI_CODING_AGENT_DIR

symlink_points_to() {
    [[ -L "$1" && "$1" -ef "$2" ]]
}

remove_owned() {
    local src="$REPO_ROOT/$1" dst="$2" container="${3:-}"
    [[ "$dst" == /* ]] || dst="$HOME/$dst"
    if [[ -n "$container" && "$container" != /* ]]; then
        container="$HOME/$container"
    fi

    if [[ -n "$container" && -L "$container" ]]; then
        echo "  parent is a symlink: $container (skipping)"
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

RESTORE_HELPER_DIRECTORY=""

cleanup_restore_helper() {
    if [[ -n "$RESTORE_HELPER_DIRECTORY" ]]; then
        rm -f "$RESTORE_HELPER_DIRECTORY/rename-backup"
        rmdir "$RESTORE_HELPER_DIRECTORY" 2>/dev/null || true
    fi
}
trap cleanup_restore_helper EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

prepare_restore_helper() {
    command -v cc >/dev/null 2>&1 || {
        echo "  restore requires the platform C compiler (cc); backups and managed links are preserved" >&2
        return 1
    }
    RESTORE_HELPER_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-restore.XXXXXX")" || return 1

    # Portable mv can nest into a directory created after our existence check;
    # macOS mv also lacks GNU's -T. Use an atomic, exact-path, no-replace rename.
    # The platform compiler/SDK is already required by install.sh. Keep this
    # helper temporary and self-contained; never fall back to copy-and-remove.
    if ! cc -x c -o "$RESTORE_HELPER_DIRECTORY/rename-backup" - <<'C'
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>

int main(int argc, char **argv) {
    if (argc != 3) return 2;
#if defined(__APPLE__)
    int result = renamex_np(argv[1], argv[2], RENAME_EXCL);
#elif defined(__linux__)
    int result = renameat2(AT_FDCWD, argv[1], AT_FDCWD, argv[2], RENAME_NOREPLACE);
#else
#error "Backup restoration requires macOS or Linux exclusive rename support"
#endif
    if (result != 0) {
        fprintf(stderr, "exclusive backup rename failed: %s\n", strerror(errno));
        return 1;
    }
    return 0;
}
C
    then
        rm -f "$RESTORE_HELPER_DIRECTORY/rename-backup"
        echo "  could not build the exclusive-rename helper; backups and managed links are preserved" >&2
        return 1
    fi
    [[ -x "$RESTORE_HELPER_DIRECTORY/rename-backup" ]]
}

move_backup() {
    local backup="$1" destination="$2"

    if [[ -e "$destination" || -L "$destination" ]]; then
        return 1
    fi
    mkdir -p "$(dirname "$destination")" || return 1
    "$RESTORE_HELPER_DIRECTORY/rename-backup" "$backup" "$destination"
}

restore_direct() {
    local source_rel="$1" target_rel="$2"
    local source="$REPO_ROOT/$source_rel" target="$target_rel"
    [[ "$target" == /* ]] || target="$HOME/$target"
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

# Do not follow a harness container redirected after installation.
manage_workflow_link() {
    local target="$1" container="$2" redirected
    redirected="$(redirected_agent_parent "$container")"
    if [[ -n "$redirected" ]]; then
        echo "  parent is a symlink: $redirected (skipping)"
        return
    fi
    if (( RESTORE_BACKUPS == 1 )); then
        restore_direct docs/agents/development-workflow.md "$target"
    else
        remove_owned docs/agents/development-workflow.md "$target" "$container"
    fi
}

RESTORE_STATUS=0
if (( RESTORE_BACKUPS == 1 )); then
    prepare_restore_helper || die "unable to prepare backup restoration; no managed links or backups were changed"
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

manage_workflow_link "$CODEX_DIRECTORY/AGENTS.md" "$CODEX_DIRECTORY"
manage_workflow_link "$PI_DIRECTORY/AGENTS.md" "$PI_DIRECTORY"
manage_workflow_link "$HOME/.claude/rules/development-workflow.md" "$WORKFLOW_HOME/.claude/rules"

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
    "$CODEX_DIRECTORY"/AGENTS.md.bak.*
    "$PI_DIRECTORY"/AGENTS.md.bak.*
    "$HOME"/.claude/rules/development-workflow.md.bak.*
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
