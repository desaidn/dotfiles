# Prevent Lazygit and Hunk Float Stacking

## Outcome

Switching from one Neovim-owned terminal tool to another should return to the original editing window when the second tool is hidden. Lazygit and Hunk must not become a stack of visible floats that traps focus between tool buffers.

## Reproduction / current state

The problem has been reproduced against the production configuration:

1. Open lazygit with `<leader>gg`.
2. Press `<Esc><Esc>` to leave terminal mode without closing lazygit.
3. Open Hunk with `<leader>gd`.
4. Leave terminal mode and hide Hunk.
5. Neovim reveals lazygit rather than the editing window; both tools remain layered until they are separately closed.

`<Esc><Esc>` only exits terminal mode in [`init.lua`](../../nvim/init.lua). In [`terminal_tool.lua`](../../nvim/lua/custom/lib/terminal_tool.lua), a newly opened float anchors to the current window, and each tool only hides its own window. Opening Hunk while lazygit is still current therefore anchors Hunk over lazygit. The existing regression suite protects single-tool lifecycle behavior but does not open two live terminal-tool floats in sequence.

## Scope

- Add a regression that expresses the exact lazygit-to-Hunk sequence and expected return to the host editing window.
- Establish a shared-launcher invariant for how multiple registered terminal tools may be visible.
- Adjust central terminal-tool lifecycle/focus behavior rather than adding Hunk- or lazygit-specific branches.
- Preserve persistent hidden jobs, working-directory restart behavior, Editor Handoff, resize behavior, and cross-tab behavior.
- Update Neovim documentation if the visible-tool invariant becomes part of the declaration contract.

A likely direction is allowing at most one visible terminal-tool float while keeping other jobs alive, but the implementing agent should validate that invariant against tabs, handoff, and failure cases before adopting it.

## Boundaries / non-goals

- Do not make `<Esc><Esc>` terminate or hide every terminal automatically.
- Do not solve the bug by quitting lazygit or Hunk processes; persistent jobs are intentional.
- Do not add pairwise knowledge of Hunk and lazygit to the shared launcher.
- Do not change the shell-owned `EDITOR`, `VISUAL`, or `GIT_EDITOR` contract.
- Do not weaken current stale-generation, delayed-acknowledgement, resize, or host-tmux regressions.
- Do not redesign terminal-tool mappings or replace the Neovim float model.

## Open decisions

- Is “at most one visible terminal-tool float per tab” or “per Neovim instance” the correct invariant?
- When switching tools across tabs, should an existing visible float move, hide, or remain in its original tab?
- Which host window should become the anchor if the current window is itself a terminal-tool float?
- What should happen if hiding the previous tool fails while opening the next one?
- Should switching to a second tool be one launcher operation or an explicit hide-then-open sequence internally?

## Acceptance criteria

- The reported lazygit-to-Hunk sequence returns to the original editing window when Hunk is hidden.
- Opening one registered terminal tool while another is visible does not leave stacked visible tool floats.
- Hidden tool jobs remain alive and can be reopened without unnecessary restart when the working directory is unchanged.
- Both tools still restart in a changed effective working directory according to the existing contract.
- Editor Handoff hides/acknowledges only the correct tool generation.
- Existing behavior across tabs, resize events, startup failure, synchronous exit, and stale callbacks remains covered and green.
- The fix is source-agnostic and applies to future terminal-tool declarations.

## Verification

Add the multi-tool scenario to [`terminal_tool_spec.lua`](../../nvim/tests/terminal_tool_spec.lua), then run:

```sh
nvim --clean --headless -l nvim/tests/terminal_tool_spec.lua
/usr/bin/expect nvim/tests/terminal_tool_hunk_render.exp
```

Repeat the original sequence manually in production Neovim, both inside and outside tmux if available. Also test the reverse order, reopening the first hidden job, switching tabs, and changing working directory between launches.

## Starting points / references

- [`nvim/init.lua`](../../nvim/init.lua) — terminal-mode escape mapping.
- [`nvim/lua/custom/lib/terminal_tool.lua`](../../nvim/lua/custom/lib/terminal_tool.lua) — window anchoring, visibility, persistence, and tool registry.
- [`nvim/lua/custom/plugins/lazygit.lua`](../../nvim/lua/custom/plugins/lazygit.lua) and [`hunk.lua`](../../nvim/lua/custom/plugins/hunk.lua) — production declarations.
- [`nvim/tests/terminal_tool_spec.lua`](../../nvim/tests/terminal_tool_spec.lua) — fake runtime and lifecycle regressions.
- [`nvim/AGENTS.md`](../../nvim/AGENTS.md) — terminal-tool contract.
