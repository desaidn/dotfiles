# Agent development workflow

`devflow` is a small command-line tool for one common coding-agent workflow:

```text
start -> wip/<feature> -> review/<name> -> one squash commit
```

It coordinates Git, Herdr, Neovim, and Hunk. Project instructions and the user
decide where the checkout lives, whether to use a worktree, what to review
against, where to land, and what happens after landing.

These rules govern coding agents only. Human Git and LazyGit operations remain
unrestricted. Devflow installs no repository hooks and does not intercept human
commands.

## Choose the checkout

Follow the user's request and the project's instructions to prepare the checkout
where work should happen. It may be the primary checkout or a worktree. Devflow
operates only in the checkout where it is invoked and never creates, moves,
repairs, or removes worktrees.

If the user or project instructions do not already authorize a needed worktree
change, ask first. Coordinate with human activity in a shared working folder
and rerun devflow after a concurrent Git operation.

## Start local work

From a clean checkout at the commit where the feature should begin, run:

```sh
devflow start <feature>
```

For a new feature, this creates `wip/<feature>` at the checkout's current
commit. If that WIP branch already exists, devflow selects it without moving or
rewriting it. If it is checked out elsewhere, use the reported checkout instead
of moving the branch.

Agent-authored WIP is append-only. Add ordinary commits; never amend, rebase,
reset, delete, or force-update WIP. When a target branch must be incorporated,
merge it into WIP normally, resolve and test there, then review the new WIP
head.

## Review local work

From a clean checkout on the exact `wip/<feature>` commit to review, pass the
comparison point explicitly:

```sh
devflow --json review --base <branch-or-commit>
```

The base must be an ancestor of the current commit. Devflow infers the review
name from `wip/<feature>` and records `review/<feature>` at that exact WIP head.
The Review Branch is a marker for the reviewed code, not a second working
branch or a squashed commit.

Devflow opens a Herdr tab rooted in the same checkout, starts Neovim there, and
opens the complete `BASE...HEAD` change in Hunk. Hunk's `e` action returns to
that Neovim with normal project-root discovery, dependencies, and language
tooling. Devflow publishes the Review Branch and Review Record only after the
review session has opened and been verified successfully.

Take `checkout` and `session_id` from the JSON response and inspect that exact
session:

```sh
hunk session review <session-id> --include-patch --include-notes --json
```

Review the complete change and add each actionable finding to that session:

```sh
hunk session comment add <session-id> --file <path> --new-line <n> \
  --summary <text> --rationale <text> --author <name> --json
```

Use `--old-line` instead of `--new-line` for removed code. Keep the checkout's
commit, staged state, and files unchanged while the review is open so editor
handoff stays tied to the reviewed project state.

If the user requests changes, return to WIP and append commits. Then open a new
review. Any WIP or Review Branch change makes the older approval stale. A
review does not imply approval; only the user's explicit approval of the exact
returned review ID authorizes landing. After approval, the review tab may close
and its checkout may be reused; the unchanged WIP and Review Branch preserve
the approved snapshot.

## Review someone else's code

Review-only code uses the same Herdr, Neovim, Hunk, and agent-review path. From
a clean checkout at the exact commit being reviewed, run:

```sh
devflow --json review --base <branch-or-commit> --name <review-name>
```

The source is always the checkout's current commit. Supplying `--name` marks the
review as external, so devflow creates no WIP branch and cannot land it. The
base must be an ancestor of the current commit.

## Land approved local work

After the user approves the exact current local review, ask which existing
local branch should receive it. The target may follow any project convention
except the reserved `wip/*` and `review/*` names.

Prepare a clean checkout already on that target, derive one complete imperative
commit title from the feature name and complete WIP history, then run:

```sh
devflow land <feature> --target <branch> --approved <review-id> --title "<title>"
```

The target must contain the review's explicit base. It may have gained newer
compatible commits since review. Devflow verifies that WIP and Review Branch
still identify the approved commit, then adds the complete reviewed change to
the target as one squash commit. It leaves WIP, the Review Branch, and the
Review Record intact.

If the change conflicts or needs integration work, devflow stops. Return to
WIP, merge the target into it, resolve and test with append-only commits, and
open a fresh review before trying again.

Landing is the end of devflow's responsibility. It never creates the target,
pushes, opens a team review, runs team-specific tools, merges onward, or cleans
up successful work. The project workflow handles those steps.

## Composition and exceptions

Other workflows use devflow through its commands and JSON output. It has no
plugin system, callbacks, or project-specific configuration. Project
instructions and skills supply its explicit inputs and use its results.

Use devflow for the guarded `start`, `review`, and `land` transitions. An agent
branch or worktree action outside this contract is allowed when the user or
project instructions authorize it; otherwise ask first. The user's own Git and
LazyGit actions are never Workflow Exceptions.

Harness-global adapters are installed explicitly and non-destructively:

```sh
devflow harness install codex
devflow harness install claude
```

They manage only their marked guidance blocks and preserve all other
user-authored harness instructions.
