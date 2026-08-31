Use `devflow` as the only transaction surface for the guarded branch workflow.

`devflow` operates only in the checkout where it is invoked, including when that
checkout is a user-created worktree. It never creates, adopts, moves, repairs,
prunes, locks, unlocks, or removes a worktree. Never bypass `devflow` with direct
ref, branch, reset, rebase, force-push, review-ref, or mainline mutations. Any
worktree lifecycle action or other action outside the guarded flow is a Workflow
Exception and requires the user's explicit approval.

Use `devflow start <feature>` from a clean invoking checkout for local WIP work.
It creates a new WIP exactly at current mainline or selects the existing branch
without rewriting it. Once on `wip/<feature>`, ordinary `git commit` and an
ordinary merge of current mainline into WIP are allowed append-only transactions;
never amend, rebase, reset, delete, or force-update WIP. If the branch is checked
out elsewhere, stop instead of moving to or changing that checkout.

Use `devflow --json review` for the immutable review surface. It requires the
invoking checkout to be clean, on the matching WIP branch, and exactly at the
reviewed head. External code instead supplies the complete explicit `--source`,
`--base`, and `--name` triple; that form is always external, even when its source
is named `wip/*`, and requires the clean invoking checkout's `HEAD` to equal the
resolved source. Immediately take `<checkout>` and `<session-id>` from the JSON
response and inspect the exact live session with:

`hunk session review <session-id> --include-patch --include-notes --json`

The command returns only after Hunk's full session record proves the canonical
invoking checkout and exact full `BASE...HEAD` aggregate; do not substitute
another live session. Keep the checkout quiescent while the review is open so
neither `HEAD`, the index, nor working-tree files change and Hunk's editor
handoff opens in the review tab's Neovim with normal project-root discovery and
full language tooling, using the checkout's dependency and build context at the
reviewed head. Review the full change set and add every actionable finding to
that same session with:

`hunk session comment add <session-id> --file <path> --new-line <n> --summary <text> --rationale <text> --author <name> --json`

Use `--old-line` instead when the finding belongs to removed code. Add comments
before waiting for the user's decision. If WIP advances, start a new review; any
prior approval is stale and the older snapshot cannot land. A review does not
imply approval. Invoke `devflow land` only after the user explicitly approves the
exact returned review ID and supplies the complete-feature squash title.
