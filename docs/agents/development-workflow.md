# Agent development workflow

`devflow` is the harness-neutral Workflow Engine for agent-authored development and review. Git remains the repository authority; `devflow` validates the agreed transitions, installs repository-local accident guards, and coordinates the existing Herdr, Neovim, and Hunk surfaces.

## Invoking checkout

Devflow operates only in the checkout containing the command's current working directory. That Invoking Checkout may be a repository's primary checkout or a worktree the user created; the same rules apply to both. Devflow never creates, adopts, moves, repairs, prunes, locks, unlocks, or removes a worktree, and it never chooses a different checkout on the user's behalf. If a required branch is already checked out elsewhere, the command reports that location and stops.

Worktree topology remains user-owned. A worktree lifecycle action is outside the guarded flow and requires explicit approval as a Workflow Exception. Even after approval, it is performed separately rather than delegated to devflow.

Every engine-driven branch switch asks Git not to overwrite ignored files. If an ignored user artifact collides with a path tracked by the target revision, the transition fails without changing the checkout, ref, or file. Non-colliding ignored artifacts remain in place. Once the guards are installed, symbolic `HEAD` may select only a valid `wip/*` branch unless an exact Workflow Exception is authorized. Detached full object IDs remain allowed; symbolic checkout of mainline, Review Branches, or unrelated branches is denied, including a concurrent checkout attempted after an engine preflight.

## Locally authored feature

Create or resume local WIP:

```sh
devflow start <feature>
```

The Invoking Checkout must be clean. The command creates a new `wip/<feature>` exactly at the current Mainline Branch revision or selects the existing WIP Branch in the Invoking Checkout; it never opens another checkout or rewrites an existing branch. The resulting WIP history is append-only. Once devflow has selected WIP, ordinary `git commit` operations and an ordinary merge of current mainline into WIP are normal append-only transactions. Add logically grouped commits. Never amend, rebase, reset, force-update, delete, or force-push WIP. If mainline advances, merge it into WIP with an ordinary merge commit and resolve and test that integration on WIP.

When the complete feature is ready, launch its Review Flow:

```sh
devflow --json review
```

The Invoking Checkout must be clean, on the matching WIP Branch, and exactly at the head being reviewed. The current Mainline Branch must already be an ancestor of that WIP head. The Review Snapshot records full base, head, source, and tree object IDs; `review/<feature>` points at the exact head but is never checked out by devflow. A Review Branch checked out elsewhere is user-owned state: the engine may reuse its ref only when it already names the requested head, and otherwise refuses before ref or UI effects.

The command creates a focused Herdr tab in the Invoking Checkout, starts Neovim there, and invokes the same Hunk action exposed by `<leader>gd` after Neovim finishes UI initialization, rendered as the immutable aggregate `base...head` change set. Waiting for `UIEnter` preserves Neovim's detected terminal color capabilities instead of changing the shared action or forcing a terminal mode. Before returning, the engine queries Hunk and requires exactly one session whose non-empty session ID, absolute canonical `cwd`, `repoRoot`, and `sourceLabel`, `vcs` input kind, and exact `<checkout-name> <full-base>...<full-head>` title bind it to this Review Snapshot. Query failure, malformed records, partial path matches, a different aggregate, or multiple matching sessions fail closed. A tab or session created by a failed invocation is closed; cleanup failures are reported alongside the initiating failure. An exact session that registered concurrently is acceptable because it proves the same immutable aggregate.

The agent must immediately take `checkout` and `session_id` from the JSON response and inspect that exact live session:

```sh
hunk session review <session-id> --include-patch --include-notes --json
```

After confirming that the session belongs to the returned checkout, the agent reviews the full change set and attaches every actionable finding to that same session with `hunk session comment add <session-id> ... --json` before waiting for the user's decision.

Keep the Invoking Checkout quiescent while the review is open: do not change `HEAD`, the index, or working-tree files. Hunk's `e` action therefore opens the selected file in the review tab's Neovim with normal project-root discovery and full language tooling, using the Invoking Checkout's dependencies, generated artifacts, and build context. Feedback is addressed with new WIP commits after the review; any checkout change requires a new Review Snapshot and invalidates prior approval. Mainline may continue moving after review; if landing integration requires a WIP change, append it and review again.

After the user explicitly approves the latest complete Review Snapshot, land it with its exact identifier and a short imperative title that describes the complete feature:

```sh
devflow land <feature> --approved <review-id> --title "<complete feature title>"
```

Landing creates one single-parent squash commit on the current Mainline Branch, leaves WIP and its Review Snapshot unchanged, and never pushes. Mainline must not be checked out in any worktree; explicitly switch or detach that checkout first. The engine performs a ref-only landing and never aligns a user worktree. Its single atomic reference transaction verifies the exact approved WIP and Review Branch heads while compare-and-swap advancing mainline. A conflict, concurrent source change, concurrent mainline change, or stale approval stops without advancing mainline.

## Review-only change set

Review Flow is independent of Work Flow. To review externally authored code without creating or mutating WIP, identify all three inputs explicitly:

```sh
devflow --json review --source <revision> --base <revision> --name <review-name>
```

The complete explicit triple always selects external review, even when `--source` names a `wip/*` branch. The resolved base must be an ancestor of the source so `BASE...HEAD` preserves the supplied Change Set. The Invoking Checkout must be clean and its `HEAD` must equal the resolved source revision; devflow never switches or detaches it to satisfy the request. A mismatch fails before ref, record, or UI effects.

This creates or advances only the read-only `review/<review-name>` snapshot and opens the same in-place Herdr, Neovim, Hunk, and Agent Review Loop. Review-only snapshots cannot land through `devflow land`.

## Legacy managed checkouts

Older devflow versions could create workflow-owned WIP and review worktrees under their state directory. Current devflow may observe those registrations during read-only conflict checks, but it does not identify, adopt, reuse, move, or delete them as workflow-owned checkouts. A legacy checkout participates only when the user explicitly invokes devflow from it. Cleanup remains separate and requires explicit approval after confirming that no active WIP or review depends on it.

The superseded clone-local `devflow.worktree-mode` value is inert: current devflow neither reads it as authorization nor rewrites it during normal commands. It may be removed together with legacy checkout state only as part of that explicitly approved cleanup.

## Guards and exceptions

The first mutating invocation installs owned `reference-transaction` and `pre-push` hook links in the repository's effective hooks directory. Local WIP creation and fast-forward movement are allowed; Review Branch and Mainline Branch movement requires the engine's exact transition authorization. Symbolic `HEAD` movement is independently restricted to WIP so ref preflights cannot be defeated by a concurrent checkout. Any other local `refs/heads/*` creation, update, deletion, or symbolic checkout requires an exact explicitly approved exception. WIP deletion and non-fast-forward pushes are rejected, Review Branch pushes are always rejected, and other remote branch targets are denied by default. An existing remote Mainline Branch accepts only a non-deleting fast-forward from the exact same-named local guarded Mainline Branch at its current OID, which prevents a WIP or arbitrary refspec from publishing directly to mainline. Foreign hooks are preserved and block registration rather than being overwritten.

These hooks and the Workflow Engine are deterministic accident rails, not a security boundary. Git has no hook that intercepts every worktree lifecycle command, and a caller with repository access can deliberately bypass the flow. Global agent adapters therefore prohibit direct worktree and branch-flow bypasses as well. Any operation outside this document requires explicit user approval before execution.

Harness-global adapters are installed explicitly and non-destructively:

```sh
devflow harness install codex
devflow harness install claude
```

They manage only their marked guidance block and preserve all other user-authored harness instructions.
