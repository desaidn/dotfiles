---
name: parallel-worktrees
description: Use when splitting work across several Git worktrees, running agents in parallel on separate ideas or on coordinated parts of one feature, acting as a manager that briefs workers and maintains the canonical WIP branch, or acting as a worker assigned one workstream. Also covers cutting review pieces, testing the whole feature and each piece, finding a group again after a restart, handing off a manager, and cleaning up after landing.
---

# Parallel worktrees

This skill describes how to run several lines of work at once in one
repository: each in its own worktree, usually with its own agent, either as
independent ideas or as coordinated parts of one feature under a manager.
The always-loaded development workflow still applies to every branch here.
The [`development-review` skill](../development-review/SKILL.md) still owns
review, approval, landing, and delivery, and the
[`herdr-app` skill](../herdr-app/SKILL.md) owns starting, showing, and talking
to terminals in Herdr app.

## 1. Layout

- **The root checkout is home base.** It stays on the project's mainline
  branch, clean, for the person's shell and editor or for a manager agent.
  Nobody implements there. When the project lands changes locally, the root
  checkout is usually where they land; recheck that it is clean and on the
  target first, and coordinate with any agent working in it.
- **One worktree per line of work.** Each idea or workstream gets its own
  worktree and its own `wip/` branch, created from a clean starting commit.
- **One space per worktree.** In Herdr app, each worktree's agent or shell sits
  in its own space, named after its idea or workstream, so the person can find
  and watch it. Create spaces only when the person asks or has agreed to this
  layout.

**Where worktrees live belongs to the project.** Follow the location and
naming the project's instructions give. If they say nothing, ask the person
where worktrees should go before creating the first one, and suggest
recording the answer in the project's instructions so the next session does
not have to ask. Creating a worktree or branch is a branch and worktree
action, so it needs the person's or the project's authorization.

## 2. Pick the mode

**Independent ideas.** Separate experiments or unrelated tasks. There is no
manager and no shared branch. Each idea has its own `wip/<idea>` branch and is
reviewed and landed on its own. The person checks in on each space directly,
or an agent in the root checkout does on their behalf. The rest of this skill
is about the coordinated mode, though sections 5, 6, and 11 apply to both.

**Coordinated parts.** One feature split into parts that must work together.
A manager splits the work, briefs a worker for each part, integrates the
results, and is the person's single point of contact. Use this when the
parts share interfaces, deploy together, or must be tested as a whole.

Ask which mode the person wants when the request does not make it clear.

## 3. Three kinds of branch

Keep three things separate. They often line up, but not always:

- **Workstream branches**, `wip/<feature>-<area>`: one worker's area of
  responsibility, in that worker's worktree. A workstream is long-lived and
  may take many rounds of fixes.
- **The canonical WIP branch**, `wip/<feature>`: the whole feature, in its
  own integration worktree, never the root checkout. Every workstream merges
  into it. The whole feature is tested here.
- **Review pieces**: the slices that are actually reviewed and landed. Either
  each workstream is its own review piece, or review pieces are cut from the
  canonical branch afterwards; see section 4.

Merging rules:

- **One owner per merge.** For each merge into the canonical branch, the
  manager names who does it: the manager, or the worker whose change it is.
  Whoever merges leaves the integration worktree clean, on its branch, and
  reports the merge commit.
- **Workstreams don't take the whole feature.** Never merge the canonical
  branch into a workstream; the workstream would then carry everything. When
  one workstream needs another's not-yet-landed changes, merge that specific
  workstream's branch, with the manager's agreement, and record the
  dependency.
- **Fixes go where the code is owned.** When integration shows a workstream
  needs a change, make it on that workstream's branch and merge it into the
  canonical branch again. Changes that belong only to integration go directly
  on the canonical branch: merging the moved target branch and resolving
  conflicts between workstreams.
- **Environment overlays stay off every reviewable branch.** Source changes
  needed only to deploy to one environment, such as an account added to an
  allowlist, never enter a workstream, review piece, or the canonical
  branch. Read [environment overlays](references/environment-overlays.md)
  before deploying with one.

All `wip/` branches here are append-only, like every WIP branch: ordinary
commits and merges, never amend, rebase, reset, or force-update.

## 4. Choose how review pieces are formed

Pick one strategy, tell the person which and why, and record it:

1. **Each workstream is a review piece.** Simple. Fits small parts that are
   independent and readable on their own. The workstream branch is reviewed
   as `review/<feature>-<area>` and lands on its own.
2. **Cut review pieces from the canonical branch.** Fits large features where
   reviewers need small, ordered, stacked changes that don't follow how work
   was divided. One workstream may spread across several pieces, and one
   piece may hold code from several workstreams. Read
   [review pieces](references/review-pieces.md) before cutting, re-cutting,
   or landing them.

If the person wants a single change instead, review and land the canonical
branch like any other WIP.

## 5. Test the whole feature and each piece

Before the first review piece goes to review or is submitted, both of these
must pass with the project's agreed validation:

1. **The whole feature**, on the canonical branch with every workstream
   merged in, including end-to-end or deployed checks when the project uses
   them.
2. **Each review piece as it will land**: on the target branch plus only the
   pieces it builds on (for stacked pieces, the ones below it). For deployable features, use
   a separate environment from the whole-feature one when one exists, and say
   so when one does not.

Full runs can be slow and fixes frequent. After a later change, a **scoped
rerun** of the checks that cover the changed behaviour is enough, if its
reason is recorded, for example "storage checks only: the change is confined
to the storage write". A **full run** of both kinds is still required before
the first review and before handing the feature over.

Keep test state isolated. Give each run its own state directory or namespace,
make checks judge only their own run's data, and when a deploy changes a
stored-data format, clear that environment's stored state at the point the
change requires.

Record each run: what ran, on which commit, in which environment, the result,
and the log path.

## 6. Find each other by label, not by terminal ID

Terminal IDs such as `t31` change whenever a program restarts, and a report
sent to an old ID is lost. Use labels, which can be reapplied after any
restart:

```sh
hc label "$HC_TERMINAL_ID" group="$feature" role=manager
hc ls --label group="$feature"                     # the whole group
```

- **The manager relabels itself at the start of every session**, because a
  restarted manager runs in a new terminal. The person usually opens the
  manager, and names can only be set at launch, so labels are the lookup. A
  manager started through `hc run` also gets a stable name such as
  `<feature>-manager`.
- **Workers are labeled** `group=$feature role=worker piece=$area`: at launch
  with `--label` when the manager starts them, with `--outlive-parent` so a
  manager restart does not end them, or with `hc label` when the person
  started them.
- **A worker looks the manager up every time it reports**, not once. It
  reports only when exactly one manager is found; otherwise it says so on
  screen and keeps its report file:

  ```sh
  managers=$(hc ls --label group="$feature" --label role=manager --json |
    jq -r '.terminals[].address')
  [ "$(printf '%s\n' "$managers" | grep -c .)" -eq 1 ] &&
    hc send "$managers" "done: <commit>, report at <path>"
  ```

- **Briefs written before this rule** still name an old ID. Resend the lookup
  rule to those workers.
- Workers the person started are not the manager's children, so
  `hc wait --children` does not see them. Wait on each worker by address.

Outside Herdr app, use whatever the harness or terminal provides to address
agents, and keep the same rule: address the role, not a session ID that can
change.

## 7. Roles and briefs

**The manager:**

- Splits the feature into workstreams with clear boundaries, chooses the
  review strategy, and agrees both with the person before starting workers.
- Owns the canonical branch and the integration worktree. It names who makes
  each merge, runs the whole-feature checks, and routes fixes to the owning
  worker. It does not edit workstream worktrees.
- Starts workers without model or effort flags, so each uses its harness's
  configured default and follows the person's configuration as models
  change. It passes a model only when the person names one for that task.
- Runs long jobs, such as builds, deploys, and test suites, in persistent
  background terminals (`hc run --bg --outlive-parent`), not in its own
  shell, so they survive a manager restart. Pass `PATH` as the `herdr-app`
  skill describes, have each job write its status and result to a file,
  confirm it actually started, and check whether it is waiting at an
  interactive prompt rather than leaving it blocked.
- Keeps the person's decisions, each branch's latest commit, and the latest
  test results current in the conversation; see section 10.

**A worker:**

- Works only in its own worktree, commits to its own workstream branch, and
  makes only the merges its brief assigns. It starts no agents.
- Reports when done or stuck, by role (section 6): a short message with the
  commit IDs, what ran with counts and the result, and the path of a full
  report written outside the worktree's tracked files.

**Every brief contains:**

- the worktree, branch, and file scope;
- the evidence and decision behind the task, so the worker does not reopen
  it;
- explicit limits: no pushing, deploying, submitting reviews, or touching
  shared or production environments unless the brief says so;
- any authorization the person gave, restated exactly. Permission the person
  gave the manager does not pass to a worker automatically, and a worker's
  own harness may still refuse; if it does, bring that to the person rather
  than overriding it, and expect some actions to stay with the manager;
- the exact acceptance check to run;
- the report format and the manager lookup from section 6.

## 8. After a review piece lands

Pieces often land while later ones are still in review:

1. Merge the updated target into the canonical branch, and into any
   workstream or piece that builds on the landed one.
2. If the landing gave the change a new commit ID, the later pieces' bases no
   longer match the target; refresh them as
   [review pieces](references/review-pieces.md#after-a-piece-lands)
   describes.
3. Review feedback on a piece that has already landed becomes a new change
   on top of the target, not a revision of the landed piece.
4. Rerun the scoped checks for what moved.

## 9. Recover after a restart

When a manager starts fresh, or a report seems to be missing:

1. Relabel the manager (section 6). Read the latest handoff note if there is
   one. Find the group with `hc ls --label group=$feature` and list the
   worktrees with `git worktree list`.
2. Read each worker's screen with `hc read` and check its branch head and
   status. A worker may have reported to a terminal that no longer exists;
   its screen or report file has the result.
3. Check the status files of long jobs. A job started from the old manager's
   own shell may have died with it; restart it in a persistent terminal.
4. Compare each workstream's head with what the canonical branch last
   merged, and treat earlier test results as stale for anything that moved.
5. Only then send new tasks. Do not resend a task without first reading
   whether it already arrived.

## 10. Hand off the manager

Agents compact their own context, but a restart or a cleared session loses
anything that lived only in the conversation. Before the person restarts or
clears a manager, and at major milestones, the manager writes a handoff note
outside the tracked tree and tells the person its path. The note covers the
goal, the person's decisions, the review strategy, each workstream and review
piece with its worktree, branch, and head, the latest test results, running
jobs and their status files, and the next unresolved step.

## 11. Clean up after landing

When a feature or idea has landed or been abandoned, list what could be
cleaned up and ask the person before removing any of it:

- **Documents to keep.** Plans, decisions, test notes, and procedures that
  built up in worktrees. Copy what is still useful into the project's
  lasting home on a new branch, reviewed like any change. Never move or edit
  files in a worker's worktree to do it.
- **Worktrees.** Remove one only when it is clean, holds no unlanded commits
  or unharvested documents the person still wants, and nobody has it open.
- **Deploy checkouts and their build output**, and overlay branches no
  longer needed; see [environment overlays](references/environment-overlays.md).
- **Terminals** the agent itself started, including long-job terminals, once
  their results are in. Leave terminals the person started alone.
- **Spaces**, when the person wants them gone.

Agents do not delete WIP or Review Branches. They are append-only history
and review evidence; deleting them is the person's call, done by the person.

To spot stale worktrees, list them and count each branch's commits beyond
the target. A count of zero means the work never started. Squash landing
leaves WIP history outside the target, so a nonzero count does not mean the
work is unlanded; check the target's log for its landing commit.

```sh
git worktree list --porcelain
git rev-list --count "$target..$branch"
git log --oneline "$target" | head -n 20
```

Before handing a finished feature over, consider having a fresh agent with
no context reproduce the setup and test procedure from the documentation
alone. It finds gaps that agents who did the work no longer notice.
