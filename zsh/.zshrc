export XDG_CONFIG_HOME="$HOME/.config"
if (( ! ${path[(Ie)$HOME/.local/bin]} )); then
    path=("$HOME/.local/bin" "${path[@]}")
fi
export EDITOR=nvim
export VISUAL=nvim
export GIT_EDITOR=nvim

setopt PROMPT_SUBST

git_prompt() {
    local branch
    branch="$(git symbolic-ref HEAD 2>/dev/null | cut -d'/' -f3-)"
    local truncated="${branch:0:30}"
    if (( ${#branch} > ${#truncated} )); then
        branch="${truncated}..."
    fi
    [ -n "${branch}" ] && echo "[branch: ${branch}]"
}

PROMPT='%F{white}[%D %*] [%~]%f $(git_prompt)
%F{cyan}%n@%m λ%f '

alias nvim-reset='rm -rf ~/.local/share/nvim ~/.local/state/nvim ~/.cache/nvim'

if [ -f "$HOME/.local/share/dotfiles/local.zsh" ]; then
    source "$HOME/.local/share/dotfiles/local.zsh"
fi

if [[ -o interactive && ! -v ZSH_EXECUTION_STRING ]] && command -v fish >/dev/null; then
    exec fish
fi
