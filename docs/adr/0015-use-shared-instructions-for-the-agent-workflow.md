---
status: accepted
---

# Use shared instructions for the agent workflow

Retire the standalone devflow application and everything under `tools/`; express the complete agent workflow in `docs/agents/development-workflow.md` and load that same document through the native global instruction files of Codex, Claude Code, and pi. The dotfiles installer owns the links, with protected destinations and conservative uninstall. This removes a separately maintained CLI, Python environment, and harness-guidance generator; agents perform the documented checks through native Git, Herdr, Hunk, and Neovim instead of relying on deterministic workflow enforcement.

Keep the existing small Neovim `:HunkReview` adapter and its exact-revision editor handoff. This change adds neither a workflow skill nor a Herdr plugin: automatic context loading must not depend on skill selection, and a plugin can be evaluated separately if native composition proves insufficient. Preserve unrelated personal instructions, installed skills, historical review records, and Git refs during migration.

Approval belongs to the exact reviewed local snapshot and is established by available conversation evidence. A Review Branch identifies code, not approval. When a later session cannot establish the snapshot and explicit approval, it must perform fresh review and obtain fresh approval; no replacement on-disk review or approval format is introduced. Append-only agent WIP, an explicit ancestor base, clean exact-source review, an explicitly selected existing landing target, squash landing, and unrestricted human Git remain required.

This supersedes the workflow application and packaging decisions in ADRs 0009 and 0013, and amends the enforcement and review-evidence details in ADRs 0006, 0011, and 0012. ADR 0014's documentation ownership remains: the shared workflow owns the complete procedure, this repository's `AGENTS.md` owns project constraints, and the root README owns installation. A deliberate one-time migration removes an unambiguously owned legacy installation and its managed instruction blocks; ordinary installation does not silently rewrite personal guidance or manage retired package environments.
