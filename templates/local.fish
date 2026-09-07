# Per-machine fish init. Created by dotfiles install.sh; safe to edit.

# Homebrew: support the standard Apple silicon, Intel macOS, and Linux prefixes.
begin
    for dotfiles_brew in (command -s brew) /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew
        if test -x $dotfiles_brew
            $dotfiles_brew shellenv fish | source
            break
        end
    end
end

# Put atuin on PATH if installed via the official installer
test -f $HOME/.atuin/bin/env.fish; and source $HOME/.atuin/bin/env.fish

# Optional tool PATHs (no-op if the tool isn't installed)
test -d $HOME/.bun/bin;      and fish_add_path -g $HOME/.bun/bin
test -f $HOME/.ghcup/env;    and set -gx PATH $HOME/.ghcup/bin $PATH
test -d $HOME/.lmstudio/bin; and fish_add_path -ga $HOME/.lmstudio/bin
test -d $HOME/.claude/local; and fish_add_path -ga $HOME/.claude/local
test -d "$HOME/Library/Application Support/JetBrains/Toolbox/scripts"; and fish_add_path -ga "$HOME/Library/Application Support/JetBrains/Toolbox/scripts"

if status is-interactive
    if command -v mise >/dev/null
        mise activate fish | source
        mise completion fish | source
    end
    if command -v atuin >/dev/null
        atuin init fish | source
    end
end
