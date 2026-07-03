if status is-interactive
    alias nvim-reset 'rm -rf ~/.local/share/nvim ~/.local/state/nvim ~/.cache/nvim'
end

set -gx XDG_CONFIG_HOME $HOME/.config
fish_add_path -g $HOME/.local/bin
set -gx EDITOR nvim
set -gx VISUAL nvim
set -gx GIT_EDITOR nvim

if test -f $HOME/.local/share/dotfiles/local.fish
    source $HOME/.local/share/dotfiles/local.fish
end
