#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

remove() {
    local src="$REPO_ROOT/$1" dst="$HOME/$2"
    if [[ ! -L "$dst" ]]; then
        echo "  not a symlink:    $dst (skipping)"
        return
    fi
    if [[ "$(readlink "$dst")" != "$src" ]]; then
        echo "  points elsewhere: $dst (skipping)"
        return
    fi
    rm "$dst"
    echo "  removed:          $dst"
}

remove fish        .config/fish
remove ghostty     .config/ghostty
remove hunk/config.toml .config/hunk/config.toml
remove lazygit     .config/lazygit
remove nvim        .config/nvim
remove tmux        .config/tmux
remove zsh/.zshrc  .zshrc

echo
echo "Backups (if any) remain at:"
ls -d "$HOME"/.config/*.bak.* "$HOME"/.config/hunk/config.toml.bak.* "$HOME"/.zshrc.bak.* 2>/dev/null || echo "  (none)"
echo
echo "Per-machine files at \$HOME/.local/share/dotfiles/ were left untouched."
