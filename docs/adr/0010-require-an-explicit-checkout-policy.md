---
status: superseded by ADR-0011
---

# Require an explicit checkout policy

Every participating clone records exactly one Checkout Policy as `devflow.worktree-mode` in its common local Git configuration. The value is either `in-place`, which confines the Workflow Engine to the invoking checkout and forbids worktree lifecycle operations, or `managed`, which permits only deterministic workflow-owned worktrees and leaves every user-owned worktree untouched. The setting is never stored per worktree, inferred from repository topology, or remembered only in an agent conversation. An unset or invalid value blocks the affected flow and requires the agent to ask the user; a fresh clone therefore asks again, while continued and fresh chats in an existing clone remain faithful to the recorded answer. Changing the value is a Workflow Exception and requires explicit user approval.

The Review Flow remains independent of this choice: In-place Checkout presents the exact Change Set from the invoking checkout without creating a worktree, while Managed Worktrees may present it in a workflow-owned review checkout. Global agent adapters require the Workflow Engine's policy check and prohibit direct worktree lifecycle commands without explicit approval. Git provides no hook that comprehensively intercepts those commands, so this is a deterministic accident rail for conforming agents rather than a security boundary against deliberate bypass.
