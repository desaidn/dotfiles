---
status: accepted
---

# Operate devflow in the invoking checkout

Devflow uses only the Invoking Checkout for Work Flow and Review Flow, whether
that checkout is the repository's primary working tree or a worktree the user
created. It never performs a worktree lifecycle action or chooses another
checkout: WIP selection, Herdr, Neovim, Hunk, and Editor Handoff stay in the
same project context so the review Neovim performs normal project-root discovery
with full language tooling and can use that checkout's dependencies, generated
artifacts, and build state. A required branch checked out elsewhere is an error,
and every worktree lifecycle action remains a separately approved Workflow
Exception.

Review trades an isolated managed checkout for a clean, exact, and quiescent
Invoking Checkout. Local review requires the matching WIP head; the complete
explicit source, base, and name triple always denotes external code and
requires `HEAD` to equal its resolved source. Current devflow may observe legacy
workflow-owned worktree registrations during read-only conflict checks, but it
does not identify, adopt, reuse, move, or delete them as owned checkouts; cleanup
requires separate explicit approval. This supersedes ADR 0010's selectable
Checkout Policy and removes managed worktrees from the Workflow Engine.
