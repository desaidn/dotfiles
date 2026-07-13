# Use Tool Tabs for persistent terminal tools

Neovim-owned terminal tools use one persistent Tool Tab per tool instead of floats. Tool Tabs match Neovim's workspace-oriented tab-page model, let lazygit and Hunk coexist without visual or focus stacking, resize natively, and preserve a direct return to the latest non-tool Host Window; this supersedes the float and live-sizing portion of ADR 0003 while retaining its shared launcher, shell-owned editor contract, host-tmux, and flatten.nvim decisions.
