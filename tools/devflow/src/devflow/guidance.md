These instructions govern coding-agent actions only. The user's own Git and
LazyGit operations are unrestricted; never block, intercept, or reinterpret
them as Workflow Exceptions. Use `devflow` for the guarded WIP, review, and
landing transitions.

Follow the user's request and project instructions to choose or prepare the
checkout where work belongs, including any worktree. Devflow operates only in
the checkout where it is invoked and never creates, moves, repairs, or removes
worktrees. If neither the user nor project instructions authorize a required
branch or worktree action outside the common flow, ask first.

Use `devflow start <feature>` from a clean checkout at the commit where work
should begin. It creates `wip/<feature>` at the checkout's current commit or
selects the existing branch without rewriting it. If the branch is checked out
elsewhere, use that checkout instead of moving it. Keep agent-authored WIP
append-only: ordinary commits and ordinary merges into WIP are allowed; never
amend, rebase, reset, delete, or force-update WIP.

Review local work from a clean checkout at the exact WIP head with:

`devflow --json review --base <branch-or-commit>`

The base must be an ancestor of the current commit. Devflow infers the name
from `wip/<feature>` and records `review/<feature>` only after the review
session opens successfully. To review someone else's current checked-out
commit through the same Herdr, Neovim, and Hunk path, also pass
`--name <review-name>`. A named external review creates no WIP and cannot land.

Immediately take `<checkout>` and `<session-id>` from the JSON response and
inspect the exact live session with:

`hunk session review <session-id> --include-patch --include-notes --json`

Keep the checkout's commit, staged state, and files unchanged while the review
is open. Hunk's `e` action then returns to the review tab's Neovim with normal
project-root discovery and full language tooling. Review the full change set
and add every actionable finding to that same session with:

`hunk session comment add <session-id> --file <path> --new-line <n> --summary <text> --rationale <text> --author <name> --json`

Use `--old-line` instead for removed code. Add comments before asking for the
user's decision. Apply requested changes as new WIP commits and open a fresh
review. Any WIP or Review Branch change makes an older approval stale. A
review does not imply approval. After approval, the review tab may close and
its checkout may be reused.

Land only after the user explicitly approves the exact current local review.
Ask which existing local branch should receive it. Prepare a clean checkout
already on that target, derive one complete imperative title from the feature
name and complete WIP history, then run:

`devflow land <feature> --target <branch> --approved <review-id> --title <complete-feature-title>`

The target may use any project convention except `wip/*` or `review/*` and must
contain the Review Base. Landing adds the complete reviewed feature as one
squash commit and leaves WIP and review records intact. If integration needs
feature changes, merge the target into WIP, resolve and test there, then open a
fresh review.

Devflow never creates landing targets, pushes, runs team-specific review tools,
performs onward delivery, cleans up successful work, or manages worktrees. Its
composition surface is its commands and JSON output; it has no plugin or
project-configuration system. Coordinate shared-checkout activity and rerun
validation after a concurrent human Git operation.
