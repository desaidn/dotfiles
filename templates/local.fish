# Per-machine fish init. Created by dotfiles install.sh; safe to edit.

# Homebrew: support the standard Apple silicon, Intel macOS, and Linux prefixes.
begin
    for dotfiles_brew in (command -s brew) /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew
        if test -x $dotfiles_brew
            set -l inherited_path $PATH
            $dotfiles_brew shellenv fish | source
            if contains -- "$HOMEBREW_PREFIX/bin" $inherited_path
                set -gx PATH $inherited_path
                fish_add_path --path --append "$HOMEBREW_PREFIX/sbin"
            end
            break
        end
    end
end

# Optional tools are fallbacks; never displace an inherited runtime.
fish_add_path --path --append \
    $HOME/.atuin/bin $HOME/.bun/bin $HOME/.ghcup/bin $HOME/.cabal/bin \
    $HOME/.lmstudio/bin $HOME/.claude/local \
    "$HOME/Library/Application Support/JetBrains/Toolbox/scripts"

if status is-interactive
    if command -v mise >/dev/null
        mise activate fish | source
        mise completion fish | source
    end
    if command -v atuin >/dev/null
        atuin init fish | source
    end
end
