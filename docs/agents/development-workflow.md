# Agent development workflow

`devflow` is the harness-neutral Workflow Engine for agent-authored development and review. Git remains the repository authority; `devflow` validates the transitions it owns and coordinates the existing Herdr, Neovim, and Hunk surfaces.

This contract governs coding agents only. Human Git and LazyGit operations are wholly unrestricted: devflow installs no repository hooks, changes no Git policy configuration, and never blocks or rewrites a human command. Harness guidance constrains agents; it does not turn the user's transaction surface into part of the agent workflow.

## Invoking checkout

Devflow operates only in the checkout containing the command's current working directory. That Invoking Checkout may be a repository's primary checkout or a worktree the user created; the same rules apply to both. Devflow never creates, adopts, moves, repairs, prunes, locks, unlocks, or removes a worktree, and it never chooses a different checkout on the user's behalf. If a required branch is already checked out elsewhere, the command reports that location and stops.

Worktree topology remains user-owned. An agent-initiated worktree lifecycle action is outside the guarded flow and requires explicit approval as a Workflow Exception. Even after approval, it is performed separately rather than delegated to devflow. The user may operate worktrees directly without agent approval.

Every engine-driven branch switch asks Git not to overwrite ignored files. If an ignored user artifact collides with a path tracked by the target revision, the transition fails without changing the checkout, ref, or file. Non-colliding ignored artifacts remain in place. Devflow may refuse its own transition when an observed ref is already checked out elsewhere; it never prevents or changes the human checkout.

No preflight reserves repository state. A human may change a ref, checkout, index, or working tree immediately after validation. Compare-and-swap updates protect the exact refs in a devflow transaction, but cannot serialize another worktree's files or a later agent command. Agents must coordinate shared-checkout activity and rerun devflow validation after concurrent human Git operations.

## Locally authored feature

Create or resume local WIP:

```sh
devflow start <feature>
```

The Invoking Checkout must be clean. The command creates a new `wip/<feature>` exactly at the current Mainline Branch revision or selects the existing WIP Branch in the Invoking Checkout; it never opens another checkout or rewrites an existing branch. Agents extend WIP only through append-only history. Once devflow has selected WIP, ordinary `git commit` operations and an ordinary merge of current mainline into WIP are normal append-only agent transactions. Add logically grouped commits. Agents never amend, rebase, reset, force-update, delete, or force-push WIP. If mainline advances, merge it into WIP with an ordinary merge commit and resolve and test that integration on WIP. These restrictions do not constrain the user's direct Git or LazyGit actions.

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

The agent keeps the Invoking Checkout quiescent while the review is open: it does not change `HEAD`, the index, or working-tree files. Hunk's `e` action therefore opens the selected file in the review tab's Neovim with normal project-root discovery and full language tooling, using the Invoking Checkout's dependencies, generated artifacts, and build context. Feedback is addressed with new WIP commits after the review; any checkout change requires a new Review Snapshot and invalidates prior approval. Mainline may continue moving after review; if landing integration requires a WIP change, append it and review again. A human remains free to change the checkout, but doing so crosses the coordination boundary and makes the agent obtain a fresh validated snapshot before continuing.

After the user explicitly approves the latest complete Review Snapshot, land it with its exact identifier, explicit target, and a short imperative title that describes the complete feature:

```sh
devflow land <feature> --target <main|mainline|master> --approved <review-id> --title "<complete feature title>"
```

Landing creates one single-parent squash commit on exactly the named target, leaves WIP and its Review Snapshot unchanged, and never pushes. Devflow never infers a target or falls back among `main`, `mainline`, and `master`. If the target is observed checked out in any worktree, devflow refuses its own transition without changing that checkout; the user remains free to operate it. The engine performs a ref-only landing and never aligns a user worktree. Its single atomic reference transaction verifies the exact approved WIP and Review Branch heads while compare-and-swap advancing the explicit target. A conflict, concurrent source change, concurrent target change, or stale approval stops without advancing the target. A human checkout racing after the preflight remains outside devflow's control.

## Review-only change set

Review Flow is independent of Work Flow. To review externally authored code without creating or mutating WIP, identify all three inputs explicitly:

```sh
devflow --json review --source <revision> --base <revision> --name <review-name>
```

The complete explicit triple always selects external review, even when `--source` names a `wip/*` branch. The resolved base must be an ancestor of the source so `BASE...HEAD` preserves the supplied Change Set. The Invoking Checkout must be clean and its `HEAD` must equal the resolved source revision; devflow never switches or detaches it to satisfy the request. A mismatch fails before ref, record, or UI effects.

For agent work, this creates or advances only the read-only `review/<review-name>` snapshot and opens the same in-place Herdr, Neovim, Hunk, and Agent Review Loop. Human Git remains unrestricted. Review-only snapshots cannot land through `devflow land`.

## Agent contract and exceptions

Harness guidance requires coding agents to use devflow for `start`, `review`, and `land`, to keep WIP append-only, and to request explicit approval for an agent action outside this document. Devflow validates only its own transitions. It does not deny direct human branch, ref, push, checkout, reset, rebase, or worktree operations, and the user's Git Transaction Surface remains LazyGit and ordinary Git.

Harness-global adapters are installed explicitly and non-destructively:

```sh
devflow harness install codex
devflow harness install claude
```

They manage only their marked guidance block and preserve all other user-authored harness instructions.
