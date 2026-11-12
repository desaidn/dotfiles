# Per-machine fish init. Created by dotfiles install.sh; safe to edit.

# Homebrew: support the standard Apple silicon, Intel macOS, and Linux prefixes.
begin
    for dotfiles_brew in (command -s brew) /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew
        if test -x $dotfiles_brew
            set -l inherited_path $PATH
            $dotfiles_brew shellenv fish | source
            # shellenv can emit nothing when Brew's bin and sbin already lead PATH.
            if test -z "$HOMEBREW_PREFIX"
                set -gx HOMEBREW_PREFIX ($dotfiles_brew --prefix)
            end
            if contains -- "$HOMEBREW_PREFIX/bin" $inherited_path
                set -gx PATH $inherited_path
                fish_add_path --path --append "$HOMEBREW_PREFIX/sbin"
            else
                # Keep inherited runtime/custom paths ahead of newly added Brew paths.
                set -l before_system
                for directory in $inherited_path
                    contains -- $directory /usr/bin /bin /usr/sbin /sbin; and break
                    set -a before_system $directory
                end
                set -l merged_path $before_system
                for directory in $PATH
                    contains -- $directory $merged_path; or set -a merged_path $directory
                end
                set -gx PATH $merged_path
            end
            # Homebrew owns Mise; its dedicated bin leaves inherited runtimes in place.
            if test -x "$HOMEBREW_PREFIX/opt/mise/bin/mise"
                fish_add_path --path --move "$HOMEBREW_PREFIX/opt/mise/bin"
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
        command mise activate fish | source
        command mise completion fish | source
    end
    if command -v atuin >/dev/null
        atuin init fish | source
    end
end
