# Per-machine zsh init. Created by dotfiles install.sh; safe to edit.

# Homebrew: support the standard Apple silicon, Intel macOS, and Linux prefixes.
_dotfiles_brew="$(command -v brew 2>/dev/null || true)"
if [ -z "$_dotfiles_brew" ]; then
    for _dotfiles_brew_candidate in \
        /opt/homebrew/bin/brew \
        /usr/local/bin/brew \
        /home/linuxbrew/.linuxbrew/bin/brew
    do
        if [ -x "$_dotfiles_brew_candidate" ]; then
            _dotfiles_brew="$_dotfiles_brew_candidate"
            break
        fi
    done
fi
if [ -n "$_dotfiles_brew" ]; then
    eval "$("$_dotfiles_brew" shellenv zsh)"
fi
unset _dotfiles_brew _dotfiles_brew_candidate

# Put atuin on PATH if installed via the official installer
[ -f "$HOME/.atuin/bin/env" ] && . "$HOME/.atuin/bin/env"

# Optional tool PATHs (no-op if the tool isn't installed)
[ -d "$HOME/.bun/bin" ]      && export PATH="$HOME/.bun/bin:$PATH"
[ -f "$HOME/.ghcup/env" ]    && . "$HOME/.ghcup/env"
[ -d "$HOME/.lmstudio/bin" ] && export PATH="$PATH:$HOME/.lmstudio/bin"
[ -d "$HOME/.claude/local" ] && export PATH="$PATH:$HOME/.claude/local"
[ -d "$HOME/Library/Application Support/JetBrains/Toolbox/scripts" ] && export PATH="$PATH:$HOME/Library/Application Support/JetBrains/Toolbox/scripts"

# Initialize zsh completion before activating tools that register completions
autoload -Uz compinit && compinit

if command -v mise >/dev/null 2>&1; then
    eval "$(mise activate zsh)"
    eval "$(mise completion zsh)"
fi

if command -v atuin >/dev/null 2>&1; then
    eval "$(atuin init zsh)"
fi
