# Use flatten.nvim for editor handoff

Terminal tools launched from Neovim should return to the host Neovim through flatten.nvim instead of bespoke editor wrappers. The shell owns the global editor contract by setting `EDITOR`, `VISUAL`, and `GIT_EDITOR` to `nvim`; Hunk, lazygit, and future supporting surfaces may only tag `DOTFILES_EDITOR_HANDOFF_SOURCE` so the host can apply source-specific polish, such as hiding the originating Git surface after editor handoff.

Neovim-owned terminal flows should use the shared `nvim/lua/custom/lib/terminal_tool.lua` launcher: one persistent terminal job shown in a Neovim float in every environment, live sizing to its launching window, host tmux prefix and pane navigation kept upstream, shell-owned editor variables, and flatten.nvim handoff. New tools should be thin declarations over that helper unless they have a genuinely different job.
