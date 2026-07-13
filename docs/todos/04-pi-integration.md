# Add Pi Integration

## Outcome

Let Pi participate in the existing Agent Review Loop without creating a Pi-specific development or review surface. A Pi agent should be able to inspect and annotate the same live Hunk session the developer is viewing.

## Context / current state

The repo defines the **Agent Review Loop** as a local agent inspecting and annotating a shared Hunk session; see [`CONTEXT.md`](../../CONTEXT.md). Hunk already owns the Review Surface, and Neovim launches it through [`hunk.lua`](../../nvim/lua/custom/plugins/hunk.lua).

Pi is installed on the machine and already reads repository `AGENTS.md` files. The tmux configuration includes the extended-key settings Pi recommends, and the generic AI dock does not assume a particular Agent Harness. Hunk 0.17.0 exposes a bundled `hunk-review` skill through `hunk skill path`, but Pi is not currently configured to discover that skill.

The evidence-backed interpretation of “Pi integration” is therefore a thin adapter from Pi to Hunk's live-session commands. The implementing agent should confirm that interpretation before treating it as fixed scope.

## Scope

- Re-read current Pi skill/package discovery documentation and current Hunk skill guidance.
- Choose a stable way for Pi to discover Hunk's bundled review skill without copying versioned skill contents into this repo.
- Keep the integration optional and compatible with upgrades of the separately installed Pi and Hunk binaries.
- Preserve installer idempotency and non-destructive behavior if installation scripts participate.
- Document how to confirm that Pi sees the skill and how the Agent Review Loop is started.
- Exercise the skill against a live Hunk session, including inspection and one reversible test annotation.

## Boundaries / non-goals

- Do not add a Pi-specific Neovim launcher or a second Review Surface.
- Do not make Pi a mandatory prerequisite for using these dotfiles.
- Do not install a second copy of Hunk merely to obtain its Pi package metadata unless current upstream guidance makes that the only sound option.
- Do not commit or hardcode a versioned Homebrew Cellar path.
- Do not copy the bundled skill into the repo if that would make it silently drift from the installed Hunk CLI.
- Do not change Hunk session behavior or agent-authored review semantics beyond the adapter needed for discovery.

## Open decisions

- Does “Pi integration” mean the Hunk Agent Review Loop, or is another workflow intended?
- Should skill discovery be global for Pi or project-local for this repository?
- Should `install.sh` create a stable symlink discovered via `hunk skill path`, or should Pi's own supported configuration/package mechanism own registration?
- How should uninstall behave when a user has replaced or modified the managed registration?
- What should happen when Pi invokes the skill with no live Hunk session?

## Acceptance criteria

- Pi lists the Hunk review capability using the current supported skill-discovery mechanism.
- The registration does not depend on a versioned package-manager path and continues to resolve the installed Hunk skill after an upgrade.
- With Hunk open for the current repository, Pi can inspect the session and add an inline agent note that appears in that same session.
- With no live session, the integration fails clearly and does not launch a competing Review Surface.
- Re-running any installation step is a no-op, and uninstall only removes paths still owned by this repo.
- Pi remains optional and the repository's Agent Harness-agnostic Code Interface remains intact.
- Relevant setup and verification steps are documented.

## Verification

Use current upstream commands rather than assuming the examples below remain exact:

1. Resolve and inspect `hunk skill path`.
2. Confirm Pi's skill listing includes the Hunk review skill.
3. Launch Hunk through the normal Neovim workflow.
4. Use Pi to inspect `hunk session review --repo . --json` and add one disposable note.
5. Confirm the note appears in the visible Hunk session, then remove it.
6. Repeat discovery after any managed install step and test the no-session failure path.

If install/uninstall scripts change, exercise them twice under a temporary `HOME` and verify the non-destructive contract.

## Starting points / references

- [`CONTEXT.md`](../../CONTEXT.md) — Agent Review Loop and Review Surface vocabulary.
- [`README.md`](../../README.md) — Agent Harness-agnostic Code Interface.
- [`install.sh`](../../install.sh) and [`uninstall.sh`](../../uninstall.sh) — managed-path contract.
- [`tmux/tmux.conf`](../../tmux/tmux.conf) — generic agent dock and extended-key support.
- [`nvim/lua/custom/plugins/hunk.lua`](../../nvim/lua/custom/plugins/hunk.lua) — normal Hunk launch path.
- [Pi skills documentation](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/skills.md).
- [Hunk repository](https://github.com/modem-dev/hunk) and the locally installed path printed by `hunk skill path`.
