# Add Pi Integration

## Outcome

Let Pi participate in the existing Agent Review Loop without creating a Pi-specific development or review surface. A Pi agent should be able to inspect and annotate the same live Hunk session the developer is viewing.

## Context / current state

The repo defines the **Agent Review Loop** as a local agent inspecting and annotating a shared Hunk session; see [`CONTEXT.md`](../../CONTEXT.md). Hunk already owns the Review Surface, and Neovim launches it through [`hunk.lua`](../../nvim/lua/custom/plugins/hunk.lua).

Pi is installed on the machine and reads repository `AGENTS.md` files. The tmux configuration includes the extended-key settings Pi recommends, and the generic AI dock does not assume a particular Agent Harness.

The shared [development workflow](../agents/development-workflow.md) is now linked by `install.sh` to Pi's global `AGENTS.md`, using `PI_CODING_AGENT_DIR` when configured and `~/.pi/agent` otherwise. This supplies the same always-loaded instructions as the other harnesses, without a separate workflow skill. The remaining work is to verify that a fresh Pi session loads those instructions and can complete the Agent Review Loop against the visible Hunk session.

## Scope

- Verify Pi's supported global instruction loading, including a configured agent directory.
- Confirm the installed shared workflow is sufficient to use Hunk's live-session commands; keep any harness-specific adapter thin.
- Keep the integration optional and compatible with upgrades of the separately installed Pi and Hunk binaries.
- Preserve installer idempotency and non-destructive behavior if installation scripts participate.
- Document how to confirm that Pi loads the shared workflow and how the Agent Review Loop is started.
- Exercise the workflow against a live Hunk session, including inspection and one reversible test annotation.

## Boundaries / non-goals

- Do not add a Pi-specific Neovim launcher or a second Review Surface.
- Do not make Pi a mandatory prerequisite for using these dotfiles.
- Do not install a second copy of Hunk or add a separate workflow skill.
- Do not commit or hardcode a versioned Homebrew Cellar path.
- Do not copy bundled Hunk instructions into the repo in a way that silently drifts from the installed CLI.
- Do not change Hunk session behavior or agent-authored review semantics for one harness.

## Open decisions

- Which supported Pi inspection or diagnostic mechanism best confirms the loaded global instructions?
- Does a live Pi/Hunk exercise reveal any missing harness-specific guidance beyond the shared procedure?

## Acceptance criteria

- A fresh Pi session loads the shared workflow from its configured global instruction location.
- The instruction link does not depend on a versioned package-manager path or a separate copy of Hunk's instructions.
- With Hunk open for the current repository, Pi can inspect the session and add an inline agent note that appears in that same session.
- With no live session, Pi follows the shared review-launch procedure or explains the missing context; it does not invent session IDs or launch a competing Review Surface.
- Re-running any installation step is a no-op, and uninstall only removes paths still owned by this repo.
- Pi remains optional and the repository's Agent Harness-agnostic Code Interface remains intact.
- Relevant setup and verification steps are documented.

## Verification

Use current upstream commands rather than assuming the examples below remain exact:

1. Confirm the installed shared instruction link resolves from Pi's configured global directory.
2. Start a fresh Pi session and confirm it has loaded the shared workflow.
3. Launch Hunk through the normal Neovim workflow.
4. Use Pi to inspect `hunk session review --repo . --json` and add one disposable note.
5. Confirm the note appears in the visible Hunk session, then remove it.
6. Repeat instruction loading after any managed install step and test the no-session path.

If install/uninstall scripts change, exercise them twice under a temporary `HOME` and verify the non-destructive contract.

## Starting points / references

- [`CONTEXT.md`](../../CONTEXT.md) — Agent Review Loop and Review Surface vocabulary.
- [`README.md`](../../README.md) — Agent Harness-agnostic Code Interface.
- [`install.sh`](../../install.sh) and [`uninstall.sh`](../../uninstall.sh) — managed-path contract.
- [`tmux/tmux.conf`](../../tmux/tmux.conf) — generic agent dock and extended-key support.
- [`nvim/lua/custom/plugins/hunk.lua`](../../nvim/lua/custom/plugins/hunk.lua) — normal Hunk launch path.
- [Pi coding-agent documentation](https://github.com/earendil-works/pi/tree/main/packages/coding-agent).
- [Hunk repository](https://github.com/modem-dev/hunk).
