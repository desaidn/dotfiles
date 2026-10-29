# Agent development workflow

Apply the relevant parts of this workflow to agent work in personal and
professional projects, including coding, writing, planning, and research.
Read the project's instructions before acting. The user and project supply the
scope, checkout, feature, review base, target, validation, and delivery
requirements. These are agent instructions, not executable guards. Human Git
and LazyGit remain unrestricted. For repository changes, use native Git,
Herdr, Neovim, and Hunk; do not require a workflow CLI or skill.

## Stay within the agreed task

Match the effort to the request. Answer a small question directly. A request
for read-only research or discussion does not authorize edits, a saved report,
tests, or submission. Explain a meaningful expansion of scope before doing it.
Use skills to help with the agreed work; their default interviews, artifacts,
and delivery steps do not expand what the user authorized.

Carry forward the user's decisions, permissions, and chosen destinations.
Do not ask again when the conversation already supplies an answer. Ask for
missing decisions that affect the next step; investigate facts that can be
established from the available code, documents, and tools. If a tool or required
instruction prevents the requested approach, explain the specific constraint
before choosing a substitute.

## Communicate clearly

Write as though having a conversation. Use familiar words and connected
sentences. Explain an unfamiliar term or acronym when it is needed, and use a
concrete example when it makes the explanation easier to follow. Avoid
compressed shorthand, invented labels, and unnecessary jargon. Use headings,
lists, and emphasis only when they help the reader.

Lead with the answer or outcome, then explain the reason and relevant evidence.
Keep progress updates short: what was learned, what remains uncertain, and
what the next step will resolve. Make each decision request self-contained.
Separate settled decisions from open questions. Group independent questions
when they can be answered together; ask dependent questions in order. When
using authorized delegation, gather the workers' questions into one clear
request instead of making the user coordinate them.

## Keep the work easy to follow

Establish source facts before recommending a procedure. Distinguish what the
sources show from assumptions and proposals. State an assumption before using
it to narrow results or change a conclusion. Preserve unexpected findings and
explain exclusions instead of silently dropping evidence.

Use the agreed validation commands and environment. Do not substitute a
partial check for the requested full validation and call it complete. Report
what actually ran, its result, and any remaining gap. Include the relevant
error and command when a failure needs a decision.

When work is delegated, give each worker a clear checkout, branch, task, and
file scope that does not overlap another worker's edits. Review and integrate
their results. Treat unfamiliar existing changes as unowned until their origin
is established; do not claim them as your work.

Keep durable knowledge in its existing project home when saving it is part of
the task. A handoff should preserve the goal, agreed decisions, actual
checkouts and branches, validation, and the next unresolved step. Include the
exact review snapshot and approval evidence when they matter, with links to
existing sources.

## Use the development steps that apply

For repository edits, work on `wip/<feature>`, validate and commit the changes,
then review that exact commit with Hunk and mark it as `review/<feature>`.
After the user approves that snapshot, squash it into the agreed existing
local branch, usually `main` or `mainline`. Ask for the target only if it has
not already been selected. A CR (a submitted code review) is an optional
delivery step that happens only when the user explicitly asks to create one.
Questions and read-only discussion do not need branches or a formal review.

## Choose the checkout and start work

- Inspect `git status --short --branch` and `git worktree list --porcelain`.
  Respect unfinished work and concurrent human activity. Never stash, discard,
  or move someone else's changes to make a command succeed.
- State the actual checkout and branch at the start of repository work and
  after switching either. Identify a nested package directory separately when
  its commands run somewhere other than the repository root.
- Use the checkout authorized by the user/project. Ask before an otherwise
  unauthorized branch or worktree action. Worktree creation and cleanup belong
  to the project workflow; do not silently create a review copy.
- From a clean checkout at the intended starting commit, validate the chosen
  name with `git check-ref-format --branch "wip/$feature"`. Create it with
  `git switch --no-overwrite-ignore -c "wip/$feature"`, or resume it with
  `git switch --no-overwrite-ignore "wip/$feature"`. If it is checked out
  elsewhere, use that checkout. Never force a switch or rewrite an existing ref.
- Keep agent-authored WIP append-only: ordinary commits and merges are allowed;
  never amend, rebase, reset, delete, or force-update it. Commit subjects are
  short, imperative plain-language summaries without Conventional Commit prefixes.
- Run project validation and commit the intended changes before formal review.
  Recheck Git state after concurrent human operations; no ref or checkout is
  reserved against human use by these instructions.

## Identify the exact review

The examples below use POSIX-shell variables. Set each input deliberately and
check every command's exit status before continuing; do not paste placeholders
or continue after a failed check. Run Git commands in the selected checkout.

For local work, the source must be the current `wip/<feature>` head and the
review name is the feature name. For externally authored code, choose a unique
review name and record the kind as **external**; do not create WIP or land it.
Both use the same read-only review procedure.

Require no staged, unstaged, or untracked changes and no merge, rebase,
cherry-pick, or revert in progress. Choose an explicit ancestor base; never infer
it from a default branch. Capture full object IDs and the canonical checkout:

```sh
checkout=$(git rev-parse --show-toplevel)
base_oid=$(git rev-parse --verify "$review_base^{commit}")
head_oid=$(git rev-parse --verify 'HEAD^{commit}')
tree_oid=$(git rev-parse --verify 'HEAD^{tree}')
git merge-base --is-ancestor "$base_oid" "$head_oid"
git check-ref-format "refs/heads/review/$review_name"
```

Record the repository/checkout, local or external kind, source branch (if any),
review name, base/head/tree IDs, and validation results in the conversation.
Inspect any existing `review/<name>` ref and record its old ID before changing
it. Do not move a Review Branch checked out in any worktree or used by an open
review. A Review Branch is a snapshot marker, never a second working branch.

## Open Neovim and Hunk

Use `herdr` from `PATH`. Use a host-specific binary override only when the
selected session requires it and the executable has been verified; an inherited
`HERDR_BIN_PATH` alone is not a reason to use it. Inspect `herdr workspace list`
and the intended workspace's tabs and panes, then retain their actual IDs.
Target the session, workspace, tab, and pane explicitly instead of assuming the
focused workspace is correct. Apply the same `--session NAME` selector to every
call when selecting a named server. Do not nest tmux in Herdr. Resolve the
destination from the task's agreed workspace or the calling pane's verified
workspace, independently of the UI-focused workspace.

Preserve the user's workspace, tab, and pane focus by default. Create tabs
with `--no-focus`, then prepare them using the returned pane IDs. Opening a
file, creating a tab, preparing a review, and revisiting a review do not
request a focus change. Use `--focus` or explicit workspace, tab, or pane
focus commands only when the user asks to see or switch to that destination;
a requested walkthrough authorizes that switch. Do not infer permission from
an earlier focus snapshot or restore an earlier selection after launch,
because the user may navigate while the agent works.

When a new tab is ready, report its workspace, label, and tab ID and send one
Herdr notification without selecting it. For a review, complete the Hunk
verification below before announcing readiness:

```sh
herdr notification show "Tab ready: $tab_label" \
  --body "Workspace $workspace_id, tab $tab_id" --sound done
```

For an ordinary file request, reuse a suitable Neovim host when its identity
and command route are known. A request for a "new tab" means a new Herdr tab
running Neovim unless the user specifies a Neovim tab. Open it in the relevant
project directory and prepare the tab in the background. Use a known editor
connection or verified pane input to operate an existing host; flatten.nvim
handles editor handoff from its terminal tools, not discovery of arbitrary
editors elsewhere in Herdr. Opening a file does not start a formal review.

For a review, use a Neovim host rooted in the selected checkout. Inspect
`hunk session list --json` before changing a checkout with an existing review
and again before launching Hunk. Keep one Hunk process per checkout. Revisit
the same snapshot by verifying its checkout and revisions and showing the
existing Hunk Tool Tab in that host. Preserve Herdr focus unless the user
requested a switch. Do not silently replace an unrelated or pending review;
resolve that conflict before editing or opening another one.

In an identified existing host, run `:HunkReview BASE HEAD` with the full resolved
commit IDs. When a new review tab is requested or no suitable host exists:

```sh
herdr tab create --workspace "$workspace_id" --cwd "$checkout" \
  --label "review/$review_name" --no-focus
```

Read `result.tab.tab_id`, `result.tab.label`, and `result.root_pane.pane_id` from
the returned JSON, then launch in that pane. Preserve the quotes around
Neovim's `-c` argument inside the shell command sent to Herdr:

```sh
herdr pane run "$pane_id" "nvim -c \"HunkReview $base_oid $head_oid\""
```

The configured Neovim adapter opens `hunk diff BASE...HEAD --watch --mode stack`.
It validates two full lowercase, same-length commit IDs, not Git state or
approval. Repeating the range reuses its toggle; changing it replaces the job
in the same Tool Tab. Invalid arguments leave the current review intact.
`<leader>gd` always selects working-tree changes and `<leader>gD` staged changes.
Changing any review input ends the old review; preserve its notes first and
verify the new snapshot. Hunk's `e` returns to this host Neovim with project
language tooling. In a separately authorized terminal or tmux fallback, run
`nvim -c "HunkReview $base_oid $head_oid"` from the checkout.

A launched pane does not prove the review is ready. Inspect the live Hunk list
until the intended session registers (use a bounded wait, normally ten seconds).
Verify `cwd`, `repoRoot`, and `sourceLabel` identify the selected checkout,
`inputKind` is `vcs`, and structured `review.base` and `review.head` equal the
resolved full commit IDs. The title may abbreviate revisions; it is a display
label, not proof of snapshot identity. Stop if the structured revision fields
are missing, or on mismatch, ambiguity, unavailable presentation, or timeout;
close only a tab created by this failed attempt. Do not report a successful
review yet.

```sh
hunk session get "$session_id" --json
hunk session review "$session_id" --include-patch --include-notes --json
```

Check that the actual patch covers the intended full change set. Recheck the
checkout is clean at `head_oid`, its tree is `tree_oid`, and local WIP still
points there. Only then publish `refs/heads/review/$review_name` using
`git update-ref <ref> <head_oid> <previous_oid>`; use an empty previous-ID argument
for an absent ref. This compare-and-update must fail if the ref changed during
launch. Do not force it through a concurrent change. Record the verified Hunk
session ID and Herdr tab/pane IDs alongside the snapshot in the conversation.

For a requested walkthrough, first focus the review's Herdr tab and editor pane,
then navigate inside that exact Hunk session:

```sh
herdr tab focus "$tab_id"
hunk session navigate "$session_id" --file "$path" --new-line "$line" --json
```

Herdr selects the visible editor; Hunk selects the file and hunk within it.
Honor the requested comparison layout. Explain the behavior before and after
each important change, show the relevant validation evidence and its limits,
and give the user time to inspect before moving on. Use Hunk's `e` when source
context helps. Keep findings on this same visible session; `comment add --focus`
can bring a new finding into view.

## Findings and approval

Review the whole change set. Add every actionable finding to that exact live
session before asking the user for a decision:

```sh
hunk session comment add "$session_id" --file "$path" --new-line "$line" \
  --summary "$summary" --rationale "$rationale" --author "$author" --json
```

Use `--old-line` for removed code. Keep HEAD, index, and files unchanged while
review is open. Hunk notes belong to its live process; conversation summaries
must capture the findings and decision needed for continuity, not assume notes
survive process exit. Hiding a Tool Tab, including with Neovim's `:tabclose`,
leaves Hunk running. To finish a review, preserve its notes, quit that Hunk
process, and verify its session is gone from `hunk session list --json`. Do not
close a shared Neovim host containing unrelated buffers or work.

A request to revise the current task authorizes ending its own review this way
before editing. Apply the requested changes as new WIP commits, then open and
verify the new snapshot for fresh approval. An unrelated or pending review
still needs its owner's decision before it is replaced.

Approval is the user's explicit authorization of one exact **local** snapshot,
recorded in the conversation with its base/head/tree and Review Branch. Opening
a review, an agent's review result, a Git ref, or an old record is not approval.
Any WIP or Review Branch change invalidates it. Once approved, the task's review
may finish and its checkout may be reused while the approved refs stay unchanged.
If another session cannot establish the snapshot and approval from available
conversation evidence, perform a fresh review and obtain fresh approval.
Create no custom approval database or on-disk review-record format. Preserve
historical records and refs; they do not independently authorize landing.

## Land the approved change

Only after explicit approval, land on the existing local branch the user
selected. Ask for the target only if it has not already been selected; do not
infer it from the default branch. The target cannot be `wip/*` or `review/*`.
Use a clean checkout already on that target, with no Git operation in progress.
Do not reuse an open review's checkout before approval. Derive one
complete-feature imperative title from the feature name and complete WIP
history, following project commit rules.

Before changing the target, verify all of the following:

- The approval evidence names this local feature, exact base/head/tree, and
  Review Branch. External reviews cannot land.
- `refs/heads/wip/<feature>` and `refs/heads/review/<feature>` still equal the
  approved head, and that commit still has the approved tree. Any known movement
  since approval requires fresh review even if a ref was later moved back.
- The target contains the approved base (`git merge-base --is-ancestor`). Capture
  its current full HEAD ID; refuse a feature already contained in that history.
- `git merge-tree --write-tree "$target_oid" "$head_oid"` succeeds without
  conflicts. Capture its resulting tree. A failed preflight must not mutate the
  checkout; integrate the target into WIP, resolve and test there, then re-review.

Recheck target branch/HEAD, clean state, source refs, and approval immediately
before applying. In the target checkout, run:

```sh
git merge --squash --no-overwrite-ignore "$head_oid"
```

Require success, no unresolved files or unstaged changes, and `git write-tree`
equal to the preflight tree. Refuse an empty/already-applied change. Recheck that
HEAD is still `target_oid` and the reviewed refs/approval remain valid, then run
`git commit -m "$title"`. Verify the resulting commit has exactly that target
parent and expected tree and the checkout is clean. If concurrent changes or
unexpected results appear, stop and inspect; never commit mixed state or discard
human work. Do not solve conflicts in the landing checkout or automatically reset
after a failed operation; coordinate recovery, then return integration work to WIP.

After successful landing, preserve the review findings and outcome in the
conversation and finish any remaining Hunk review owned by this task. Close its
dedicated review host or Herdr tab only if it contains no unrelated work. This
is routine review cleanup; leave unrelated and pending reviews open.

Leave WIP, the Review Branch, and historical evidence intact. Pushing,
submission, onward delivery, target creation, and branch/worktree cleanup
require their own project/user authorization. Carry forward authorization
already given for those actions; local review approval alone does not supply it.

## Create a CR only when requested

Create a CR only when the user explicitly asks for one. Keep the submission
method and destination in the project instructions or conversation.

Use an authorized `cr/<feature>` branch based on the agreed current submission
base. Verify that base and the intended change set; do not choose a base from
an unrelated checkout or assume an old base is still suitable. Prepare the
branch through the same approved-snapshot checks and squash procedure above.
The result must be one commit containing the full feature above the submission
base, with the expected parent, tree, and clean checkout. Follow the checkout
and branch authorization rules above; do not silently replace or rewrite an
existing submission branch. Resolve a changed base or a required fix in WIP,
validate it, and review the new snapshot before preparing the submission.

Submit from `cr/<feature>`. Before running a submission tool, check whether it
can amend commits or change branches. Keep WIP and the Review Branch unchanged,
including when a tool adds submission metadata, and recheck those refs
afterward. Verify the submitted change set matches the prepared commit.
Describe the concrete problem, resulting behavior, and relevant validation in
plain language.
