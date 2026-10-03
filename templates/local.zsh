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
    _dotfiles_inherited_path=("${path[@]}")
    eval "$("$_dotfiles_brew" shellenv zsh)"
    # shellenv emits nothing when Homebrew's bin and sbin already lead PATH.
    # Fish can provide that PATH without the Zsh completion path or exports.
    if [[ -z "$HOMEBREW_PREFIX" ]]; then
        export HOMEBREW_PREFIX="$("$_dotfiles_brew" --prefix)"
    fi
    if (( ! ${fpath[(Ie)$HOMEBREW_PREFIX/share/zsh/site-functions]} )); then
        fpath=("$HOMEBREW_PREFIX/share/zsh/site-functions" "${fpath[@]}")
    fi
    if (( ${_dotfiles_inherited_path[(Ie)$HOMEBREW_PREFIX/bin]} )); then
        path=("${_dotfiles_inherited_path[@]}")
        if (( ! ${path[(Ie)$HOMEBREW_PREFIX/sbin]} )); then
            path+=("$HOMEBREW_PREFIX/sbin")
        fi
    fi
fi
unset _dotfiles_brew _dotfiles_brew_candidate _dotfiles_inherited_path

# Optional tools are fallbacks; never displace an inherited runtime.
for _dotfiles_bin in \
    "$HOME/.atuin/bin" "$HOME/.bun/bin" "$HOME/.ghcup/bin" "$HOME/.cabal/bin" \
    "$HOME/.lmstudio/bin" "$HOME/.claude/local" \
    "$HOME/Library/Application Support/JetBrains/Toolbox/scripts"; do
    if [[ -d "$_dotfiles_bin" ]] && (( ! ${path[(Ie)$_dotfiles_bin]} )); then
        path+=("$_dotfiles_bin")
    fi
done
unset _dotfiles_bin

# Keep explicit zsh commands and the Fish-unavailable fallback fully usable.
if [[ -o interactive ]] && { [[ -v ZSH_EXECUTION_STRING ]] || ! command -v fish >/dev/null; }; then
    autoload -Uz compinit && compinit
    if command -v mise >/dev/null 2>&1; then
        eval "$(mise activate zsh)"
        eval "$(mise completion zsh)"
    fi
    if command -v atuin >/dev/null 2>&1; then
        eval "$(atuin init zsh)"
    fi
fi
