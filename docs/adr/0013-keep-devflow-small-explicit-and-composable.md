---
status: accepted
---

# Keep devflow small, explicit, and composable

Devflow is a small general-purpose CLI for one common coding-agent flow: `start` creates `wip/<feature>` from the Invoking Checkout's current commit or resumes it without rewriting, `review` presents an exact Change Set through Herdr, Neovim, and Hunk and records `review/<name>`, and `land` squash-merges one explicitly approved local review into an explicit existing local target. WIP remains append-only, local review points to the exact WIP head, and externally authored code uses the same Review Flow without creating WIP or becoming landable.

Direct user and project instructions own checkout and worktree preparation, the explicit Review Base, the Landing Target, publishing, team review, and onward delivery. Devflow operates in the checkout where it is invoked and does not infer team branch conventions, manage worktrees, create landing targets, push, clean up successful work, embed project configuration, or provide a plugin system; its Composition Surface is the command line and JSON results.

Devflow lives under `tools/devflow/` in a top-level Tool Workspace for small utilities used by agent instructions, skills, scripts, people, and other tools. `tools/` is an organizational source directory, not an umbrella executable or framework; each sibling remains independently named and focused, and shared infrastructure is introduced only after multiple tools need it.

The Review Base is explicit, approval belongs to one exact local WIP snapshot, and any WIP change requires a fresh review. The Landing Target may be any existing local branch except `wip/*` or `review/*`; the agent derives one cohesive Landing Title from the feature name and WIP changes. When integration requires feature changes, the agent appends them on WIP and repeats review before landing again.

This ADR amends the mainline-specific approval and landing rules in ADR 0006, the user-only worktree preparation and live-review-checkout landing requirements in ADR 0011, and the three-name landing target plus per-action worktree approval rules in ADR 0012. It retains exact snapshot approval, in-place command execution, and unrestricted human Git. Source layout, installer ownership records, code, tests, executable guidance, `AGENTS.md`, `README.md`, and the operational workflow document must change together before agents use this contract.
