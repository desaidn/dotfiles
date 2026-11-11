# Agent development workflow

Apply the relevant parts of this workflow to agent work in personal and
professional projects, including coding, writing, planning, and research.
Read the project's instructions before acting. The user and project supply the
scope, checkout, feature, review base, target, validation, and delivery
requirements. These are agent instructions, not executable guards. Human Git
and LazyGit remain unrestricted. For repository changes, use native Git,
Neovim, Hunk, and the task's terminal environment; do not require a workflow
CLI.

This file holds the rules that always apply. Step-by-step procedures live in
skills, loaded when the task reaches them; see
[Load the matching skill](#load-the-matching-skill).

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

## Rules for repository changes

Questions and read-only discussion need none of the following.

- **Checkout.** Inspect `git status --short --branch` and
  `git worktree list --porcelain` first. State the checkout and branch you are
  using. Use the checkout the user or project authorized, and ask before any
  other branch or worktree action. Never stash, discard, or move someone
  else's changes to make a command succeed.
- **Work in progress.** Work on `wip/<feature>`, created from a clean checkout
  at the intended starting commit. Keep it append-only: ordinary commits and
  merges are allowed; never amend, rebase, reset, delete, or force-update it.
  Commit subjects are short, imperative plain-language summaries without
  Conventional Commit prefixes. Validate and commit before review.
- **Review.** Review the exact committed snapshot in Hunk, marked by
  `review/<feature>`, and put every actionable finding in that live session
  before asking for a decision. Keep the commit, index, and files unchanged
  while the review is open.
- **Approval.** Approval is the user's explicit authorization of one exact
  local snapshot, recorded in the conversation with its base, head, and tree
  IDs and its Review Branch. Opening a review, an agent's review result, a Git
  ref, or an old record is not approval. Any change to WIP or the Review Branch
  invalidates it. Create no on-disk approval record.
- **Landing.** Only after approval, squash the snapshot onto the existing local
  branch the user selected, usually `main` or `mainline`. Ask for the target
  only if it has not been selected.
- **Delivery.** Submitting the landed change for code review or as a pull
  request happens only when the user explicitly asks. Pushing, cleanup of
  branches and worktrees, and other onward steps need their own authorization.
- **Adversarial review.** Run an independent adversarial review only when the
  user asks for one.
- **Concurrent humans.** Recheck Git state after concurrent human operations.
  No ref or checkout is reserved against human use.

## Load the matching skill

These skills are installed globally for Codex, Claude Code, and pi. Load the
one that matches the step and follow it in full. If a required skill is not
available, say so and stop rather than improvising its procedure.

- **`development-review`**, before identifying, opening, or revisiting a
  review; adding findings; running an adversarial review; landing; or
  delivering a change.
- **`herdr-app`**, when running in Herdr app or herdr-core terminals
  (`$HC_TERMINAL_ID` is set), and before opening any tab, pane, or agent
  terminal there.
- **`parallel-worktrees`**, before splitting work across worktrees, starting
  or managing agents on separate ideas or coordinated pieces of a feature, or
  working as a manager or worker in such a group.
- **Hunk's bundled skill**, read with `hunk skill show hunk-review`, before
  driving a live Hunk session. It matches the installed Hunk version.
- **Herdr TUI's bundled skill**, read with `herdr --skill`, when the task runs
  in Herdr TUI.
