---
name: development-review
description: Use before identifying, opening, revisiting, or finishing a Hunk review of agent-authored changes; adding review findings; running an adversarial review when asked; landing an approved change onto a branch; or delivering it as a code review submission or pull request. Carries out the development workflow's WIP, Review Branch, approval, and landing rules.
---

# Development review

This is the procedure behind the rules in the always-loaded development
workflow. Those rules still apply; this skill says how to carry them out. The
steps are the same on every machine. Only the delivery step depends on the
repository and machine; see [delivery](references/delivery.md).

Before driving Hunk, read its bundled guide in full:

```sh
hunk skill show hunk-review
```

The examples below use POSIX-shell variables. Set each input deliberately and
check every command's exit status before continuing; do not paste placeholders
or continue after a failed check. Run Git commands in the selected checkout.

## 1. Identify the exact review

For local work, the source must be the current `wip/<feature>` head and the
review name is the feature name. For externally authored code, choose a unique
review name and record the kind as **external**; do not create WIP or land it.
Both use the same read-only review procedure.

Require no staged, unstaged, or untracked changes and no merge, rebase,
cherry-pick, or revert in progress. Choose an explicit ancestor base; never
infer it from a default branch. Capture full object IDs and the canonical
checkout:

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

## 2. Open Neovim and Hunk

Use the environment where the task is running. Resolve the destination from
the agreed task context or the calling terminal's verified identity,
independently of UI focus. Do not ask the user to choose again when that
context already identifies it.

| Environment | How to find it | Where to open the review |
| --- | --- | --- |
| Herdr app | `$HC_TERMINAL_ID` is set | Follow the `herdr-app` skill's "Show something" section, on the Mac or a remote machine |
| Herdr TUI | `herdr --skill` check passes | The Herdr TUI commands below |
| tmux | `$TMUX_PANE` is set | A detached window in the task's running server |
| Plain terminal | none of the above | A known Neovim host, or the destination the task supplies |

Use the relevant executable from `PATH` and target native IDs explicitly. An
inherited `HERDR_BIN_PATH` alone is not a reason to use a different binary.
Herdr app, Herdr TUI, and tmux are top-level alternatives; do not nest tmux
inside either Herdr environment.

Preserve focus when the native API supports background preparation. A
requested new tab authorizes that tab being shown; Herdr app shows new tabs at
once, so create one only when asked. Explicit focus commands for an existing
destination require a request to see or switch to it; a walkthrough supplies
that request. Do not restore an earlier selection after launch, because the
user may navigate while the agent works.

For an ordinary file request, reuse a suitable Neovim host when its identity
and command route are known. A request for a "new tab" means a native terminal
tab running Neovim (a window in tmux), unless the user specifies a Neovim tab.
flatten.nvim handles editor handoff from its terminal tools, not discovery of
arbitrary editors in other tabs or panes. Opening a file does not start a
formal review.

For a review, use a Neovim host rooted in the selected checkout. Inspect
`hunk session list --json` before changing a checkout with an existing review
and again before launching Hunk. Keep one Hunk process per checkout. Revisit
the same snapshot by verifying its checkout and revisions and showing the
existing Hunk Tool Tab in that host. Do not silently replace an unrelated or
pending review; resolve that conflict before editing or opening another one.

In an identified existing host, run `:HunkReview BASE HEAD` with the full
resolved commit IDs. For a new destination, launch
`nvim -c "HunkReview $base_oid $head_oid"` in the checkout:

- **Herdr app.** Use the `herdr-app` skill's recipe with that command. It
  passes your `PATH` with `env "PATH=$PATH"`, because programs started by the
  core do not inherit your shell's environment. Never type the command into a
  shell with `hc send`.
- **Herdr TUI.** Create the tab without focus, then run Neovim in its pane:

  ```sh
  herdr tab create --workspace "$workspace_id" --cwd "$checkout" \
    --label "review/$review_name" --no-focus
  herdr pane run "$pane_id" "nvim -c \"HunkReview $base_oid $head_oid\""
  ```

  Read `result.tab.tab_id`, `result.tab.label`, and `result.root_pane.pane_id`
  from the first command's JSON. Apply the same `--session NAME` selector to
  every call when using a named server.
- **tmux or a plain terminal.** Use that environment's native window or pane
  and run the command from the checkout.

The configured Neovim adapter opens `hunk diff BASE...HEAD --watch --mode stack`.
It validates two full lowercase, same-length commit IDs, not Git state or
approval. Repeating the range reuses its toggle; changing it replaces the job
in the same Tool Tab. Invalid arguments leave the current review intact.
`<leader>gd` resumes the checkout's current review after Editor Handoff and
defaults to working-tree changes when none is running. Argument-free
`:HunkReview` explicitly selects working-tree changes; `<leader>gD` selects
staged changes. Changing any review input ends the old review; preserve its
notes first and verify the new snapshot. Hunk's `e` returns to this host
Neovim with project language tooling.

## 3. Verify the session and publish the Review Branch

A launched pane does not prove the review is ready. Inspect the live Hunk list
until the intended session registers (use a bounded wait, normally ten
seconds). Verify `cwd`, `repoRoot`, and `sourceLabel` identify the selected
checkout, `inputKind` is `vcs`, and structured `review.base` and `review.head`
equal the resolved full commit IDs. The title may abbreviate revisions; it is
a display label, not proof of snapshot identity. Stop if the structured
revision fields are missing, or on mismatch, ambiguity, unavailable
presentation, or timeout; close only a tab created by this failed attempt.

```sh
hunk session get "$session_id" --json
hunk session review "$session_id" --include-patch --include-notes --json
```

Check that the actual patch covers the intended full change set. Recheck the
checkout is clean at `head_oid`, its tree is `tree_oid`, and local WIP still
points there. Only then publish `refs/heads/review/$review_name` using
`git update-ref <ref> <head_oid> <previous_oid>`; use an empty previous-ID
argument for an absent ref. This compare-and-update must fail if the ref
changed during launch. Do not force it through a concurrent change.

Record the verified Hunk session ID and the native destination IDs alongside
the snapshot in the conversation. When ready, report the review's space or
workspace, tab or window label, and native IDs. If the environment provides
notifications, send one without changing focus; in Herdr TUI:

```sh
herdr notification show "Tab ready: $tab_label" \
  --body "Workspace $workspace_id, tab $tab_id" --sound done
```

For a requested walkthrough, first show the review's tab or window and focus
its editor pane: in Herdr app, follow the `herdr-app` skill; in Herdr TUI, use
`herdr tab focus`; in tmux, select the verified window and pane. Then navigate
inside that exact Hunk session:

```sh
hunk session navigate "$session_id" --file "$path" --new-line "$line" --json
```

Honor the requested comparison layout. Explain the behavior before and after
each important change, show the relevant validation evidence and its limits,
and give the user time to inspect before moving on.

## 4. Review and record findings

Review the whole change set: correctness, failure paths, tests, scope, and
documentation that the change makes stale. Add every actionable finding to
that exact live session before asking the user for a decision:

```sh
hunk session comment add "$session_id" --file "$path" --new-line "$line" \
  --summary "$summary" --rationale "$rationale" --author "$author" --json
```

Use `--old-line` for removed code, and `hunk session comment apply` for a
batch. Keep HEAD, index, and files unchanged while review is open. Hunk notes
belong to its live process; conversation summaries must capture the findings
and decision needed for continuity, not assume notes survive process exit.

## 5. Adversarial review, only when asked

When the user asks for an adversarial review, have an independent reviewer try
to break the change rather than summarize it:

- Give the reviewer the checkout, the base and head IDs, the stated goal, and
  the project's validation commands, but not the author's reasoning or
  expected conclusions. Keep it read-only and forbid it from starting further
  agents.
- In Herdr app, prefer an `hc` reviewer template from `hc templates`, started
  as the `herdr-app` and `hc --skill` guides describe. Otherwise use the
  harness's own subagent mechanism. If neither exists, review cold yourself
  and say so.
- Ask it to look for incorrect behavior, unhandled failure paths, missing or
  misleading tests, scope beyond the request, and documentation drift, each
  with a concrete failing scenario.
- Verify each reported finding yourself before presenting it. Add confirmed
  findings to the live Hunk session, and report which were rejected and why.

## 6. Finish or revise the review

Hiding a Tool Tab, including with Neovim's `:tabclose`, leaves Hunk running.
To finish a review, preserve its notes, quit that Hunk process, and verify its
session is gone from `hunk session list --json`. Do not close a shared Neovim
host containing unrelated buffers or work.

A request to revise the current task authorizes ending its own review this way
before editing. Apply the requested changes as new WIP commits, then open and
verify the new snapshot for fresh approval. An unrelated or pending review
still needs its owner's decision before it is replaced. If another session
cannot establish the snapshot and approval from available conversation
evidence, perform a fresh review and obtain fresh approval.

## 7. Land the approved change

Land only on the existing local branch the user selected; it cannot be `wip/*`
or `review/*`. Use a clean checkout already on that target, with no Git
operation in progress. Do not reuse an open review's checkout before approval.
Derive one complete-feature imperative title from the feature name and
complete WIP history, following project commit rules.

Before changing the target, verify all of the following:

- The approval evidence names this local feature, exact base/head/tree, and
  Review Branch. External reviews cannot land.
- `refs/heads/wip/<feature>` and `refs/heads/review/<feature>` still equal the
  approved head, and that commit still has the approved tree. Any known
  movement since approval requires fresh review even if a ref was later moved
  back.
- The target contains the approved base (`git merge-base --is-ancestor`).
  Capture its current full HEAD ID; refuse a feature already contained in that
  history.
- `git merge-tree --write-tree "$target_oid" "$head_oid"` succeeds without
  conflicts. Capture its resulting tree. A failed preflight must not mutate
  the checkout; integrate the target into WIP, resolve and test there, then
  re-review.

Recheck target branch/HEAD, clean state, source refs, and approval immediately
before applying. In the target checkout, run:

```sh
git merge --squash --no-overwrite-ignore "$head_oid"
```

Require success, no unresolved files or unstaged changes, and `git write-tree`
equal to the preflight tree. Refuse an empty or already-applied change.
Recheck that HEAD is still `target_oid` and the reviewed refs and approval
remain valid, then run `git commit -m "$title"`. Verify the resulting commit
has exactly that target parent and expected tree and the checkout is clean.
If concurrent changes or unexpected results appear, stop and inspect; never
commit mixed state or discard human work. Do not solve conflicts in the
landing checkout or automatically reset after a failed operation; coordinate
recovery, then return integration work to WIP.

After landing, preserve the review findings and outcome in the conversation
and finish any remaining Hunk review owned by this task. Close its dedicated
review tab or window only if it contains no unrelated work. Leave WIP, the
Review Branch, and historical evidence intact.

## 8. Deliver, only when asked

Read [delivery](references/delivery.md) before submitting the landed change
for code review or opening a pull request.
