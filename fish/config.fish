if status is-interactive
    alias nvim-reset 'rm -rf ~/.local/share/nvim ~/.local/state/nvim ~/.cache/nvim'
    if set -q GHOSTTY_RESOURCES_DIR; and not functions -q __ghostty_setup; and not functions -q __ghostty_mark_prompt_start
        set -l ghostty_integration "$GHOSTTY_RESOURCES_DIR/shell-integration/fish/vendor_conf.d/ghostty-shell-integration.fish"
        test -r "$ghostty_integration"; and source "$ghostty_integration"
    end
end

set -gx XDG_CONFIG_HOME $HOME/.config
fish_add_path --path $HOME/.local/bin
set -gx EDITOR nvim
set -gx VISUAL nvim
set -gx GIT_EDITOR nvim

if test -f $HOME/.local/share/dotfiles/local.fish
    source $HOME/.local/share/dotfiles/local.fish
end
