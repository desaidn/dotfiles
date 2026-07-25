#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_DIR="$HOME/.local/share/dotfiles"
OS_NAME="$(uname -s)"

missing=()
require() {
    command -v "$1" >/dev/null || missing+=("$1: $2")
}

require git          https://git-scm.com
require fish         https://fishshell.com
require zsh          https://www.zsh.org
require nvim         https://neovim.io
require herdr        https://herdr.dev/docs/install/
require tmux         https://github.com/tmux/tmux
require lazygit      https://github.com/jesseduffield/lazygit
require mise         https://mise.jdx.dev
require atuin        https://atuin.sh
require rg           https://github.com/BurntSushi/ripgrep
require tree-sitter  https://tree-sitter.github.io
require hunk         https://github.com/modem-dev/hunk

has_ghostty() {
    command -v ghostty >/dev/null && return 0
    [[ "$OS_NAME" == "Darwin" ]] && {
        [[ -d "/Applications/Ghostty.app" || -d "$HOME/Applications/Ghostty.app" ]]
    }
}

if [[ "$OS_NAME" == "Darwin" ]] && ! has_ghostty; then
    missing+=("ghostty: https://ghostty.org")
fi

if (( ${#missing[@]} > 0 )); then
    echo "Missing prerequisites:"
    printf '  %s\n' "${missing[@]}"
    exit 1
fi

backup_existing() {
    local target="$1"
    if [[ -e "$target" || -L "$target" ]]; then
        mv "$target" "${target}.bak.$(date +%s)"
        echo "  backed up:      $target"
    fi
}

link() {
    local src="$REPO_ROOT/$1" dst="$HOME/$2"
    if [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then
        echo "  already linked: $dst"
        return
    fi
    backup_existing "$dst"
    ln -s "$src" "$dst"
    echo "  linked:         $dst"
}

link fish        .config/fish
if [[ "$OS_NAME" == "Darwin" ]]; then
    link ghostty     .config/ghostty
else
    echo "  skipped:        $HOME/.config/ghostty (macOS-only)"
fi
herdr_config_dir="$HOME/.config/herdr"
if [[ ! -d "$herdr_config_dir" || -L "$herdr_config_dir" ]]; then
    backup_existing "$herdr_config_dir"
    mkdir -p "$herdr_config_dir"
fi
link herdr/config.toml .config/herdr/config.toml
mkdir -p "$HOME/.config/hunk"
link hunk/config.toml .config/hunk/config.toml
link lazygit     .config/lazygit
link nvim        .config/nvim
link tmux        .config/tmux
link zsh/.zshrc  .zshrc

mkdir -p "$LOCAL_DIR"
for template in local.fish local.zsh; do
    if [[ ! -e "$LOCAL_DIR/$template" && ! -L "$LOCAL_DIR/$template" ]]; then
        cp "$REPO_ROOT/templates/$template" "$LOCAL_DIR/"
    fi
done
