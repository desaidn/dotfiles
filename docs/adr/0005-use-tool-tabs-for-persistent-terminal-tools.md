# Use Tool Tabs for persistent terminal tools

Neovim-owned terminal tools use one persistent Tool Tab per tool instance instead of floats. Declarations are singleton by default; Hunk selects an instance by normalized Host Window working directory so reviews in multiple repositories or worktrees can remain live together. Tool Tabs match Neovim's workspace-oriented tab-page model, let lazygit and Hunk instances coexist without visual or focus stacking, resize natively, and preserve a direct return to the latest non-tool Host Window; this supersedes the float and live-sizing portion of ADR 0003 while retaining its shared launcher, shell-owned editor contract, host-tmux, and flatten.nvim decisions.

The September 2026 stability review corrects Hunk's instance identity to the
canonical Git checkout root. Directory identity allowed multiple Hunk processes
for subdirectories of one checkout, making `hunk session --repo` ambiguous.
Separate Git worktrees still receive independent instances; the Tool Tab and
Host Window model above is unchanged.
The unused directory instance policy is retired; configured tools need only
singleton or checkout identity.
