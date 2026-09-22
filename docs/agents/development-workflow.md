# Agent development workflow

Apply this workflow to coding-agent work in every project. Read the project's
instructions before acting; the user and project supply the checkout, feature,
review base, target, validation, and delivery requirements. These are agent
instructions, not executable guards. Human Git and LazyGit remain unrestricted.
Use native Git, Herdr, Neovim, and Hunk; do not require a workflow CLI or skill.

## Choose the checkout and start work

- Inspect `git status --short --branch` and `git worktree list --porcelain`.
  Respect unfinished work and concurrent human activity. Never stash, discard,
  or move someone else's changes to make a command succeed.
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

Use a visible Neovim host rooted in the review checkout. Set
`review_herdr=${HERDR_BIN_PATH:-herdr}` to use the host-supplied compatible binary
when available. Prefer the intended Herdr session/workspace; inspect
`"$review_herdr" workspace list` and capture actual IDs.
From outside a Herdr pane, use explicit session/workspace targeting rather than
assuming the focused workspace is correct. Apply the same `--session NAME`
selector to every call when selecting a named server. Do not nest tmux in Herdr.

Inspect `hunk session list --json` first. Keep one Hunk process per checkout;
do not silently close another review or launch an ambiguous second instance.
Reuse an existing session only after verifying the exact checkout and revisions.
Otherwise create the review tab with immutable context:

```sh
"$review_herdr" tab create --workspace "$workspace_id" --cwd "$checkout" \
  --label "review/$review_name" --env "HUNK_REVIEW_BASE_OID=$base_oid" \
  --env "HUNK_REVIEW_HEAD_OID=$head_oid" --focus
```

Read `result.tab.tab_id` and `result.root_pane.pane_id` from the returned JSON,
then run `"$review_herdr" pane run "$pane_id" nvim +HunkReview`. The configured Neovim
adapter opens full Hunk with `diff BASE...HEAD --watch --mode stack`; it validates
the object-ID format, not Git state or approval. Hunk's `e` returns to this host
Neovim with project language tooling. In a separately authorized terminal or
tmux fallback, the equivalent launch from the checkout is:

```sh
env HUNK_REVIEW_BASE_OID="$base_oid" HUNK_REVIEW_HEAD_OID="$head_oid" nvim +HunkReview
```

A launched pane does not prove the review is ready. Inspect the live Hunk list
until the intended session registers (use a bounded wait, normally ten seconds).
Verify `cwd`, `repoRoot`, and `sourceLabel` identify the selected checkout,
`inputKind` is `vcs`, and the title identifies the full `BASE...HEAD` pair.
Stop on mismatch, ambiguity, unavailable presentation, or timeout; close only a
tab created by this failed attempt. Do not report a successful review yet.

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
survive process exit. End the review before editing its checkout. Apply requested
changes as new WIP commits, then review the new snapshot and obtain new approval.

Approval is the user's explicit authorization of one exact **local** snapshot,
recorded in the conversation with its base/head/tree and Review Branch. Opening
a review, an agent's review result, a Git ref, or an old record is not approval.
Any WIP or Review Branch change invalidates it. Once approved, the review tab
may close and its checkout may be reused while the approved refs stay unchanged.
If another session cannot establish the snapshot and approval from available
conversation evidence, perform a fresh review and obtain fresh approval.
Create no custom approval database or on-disk review-record format. Preserve
historical records and refs; they do not independently authorize landing.

## Land the approved change

Only after explicit approval, ask which **existing local branch** should receive
it. The target cannot be `wip/*` or `review/*`. Use a clean checkout already on
that target, with no Git operation in progress. Do not reuse an open review's
checkout before approval. Derive one complete-feature imperative title from the
feature name and complete WIP history, following project commit rules.

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

Leave WIP, the Review Branch, and historical evidence intact. Pushing, team
review, onward delivery, target creation, and cleanup are separate project/user
decisions. Never infer authorization for them from local review approval.
