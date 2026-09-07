# Support devflow workflows outside Herdr

## Outcome

Allow agents running outside Herdr, including in the Codex desktop app, to
complete devflow's review, approval, and landing workflow without a manual
workflow exception. Keep devflow the shared authority for workflow state and
preserve the existing Herdr experience.

## Current evidence

During the dotfiles simplification review, the Codex app could show the aggregate
diff and the agent could review it, but devflow could not create a recorded
review. Landing therefore required an explicit one-time user exception.

`review.py` requires `HERDR_ENV=1` and `HERDR_WORKSPACE_ID`, launches a Herdr tab
running Neovim and `HunkReview`, and stores Herdr tab/pane and Hunk session IDs.
`landing.py` does not itself require Herdr, but it requires a valid stored review
and matching WIP and Review Branch identities. Showing a diff alone does not
satisfy that contract.

Sandbox permission to open `.git/devflow/workflow.lock` is a separate prerequisite:
resolving a filesystem permission error does not provide a Herdr caller context.

## Boundaries

- Keep workflow policy in devflow; harness integrations remain thin adapters.
- Preserve exact base/head/tree identity, explicit approval, stale-approval
  rejection, clean-checkout checks, concurrency handling, and squash landing.
- Preserve review inspection, actionable comments, and access to the reviewed
  source with normal project tooling. Keep checkout selection explicit.
- Do not fabricate Herdr context or review records, treat displaying a diff as
  approval, or make direct Git landing the normal fallback.
- This item tracks future implementation; it does not relax current workflow
  instructions or introduce a general plugin framework.

## Open decisions

- Which review presentation should be available outside Herdr: independently
  launched Neovim/Hunk, a host-provided review view, or another shared surface?
- How should presentation be selected and a successful review verified without
  relying on Herdr-specific tab/pane identity?
- How should inspection, comments, editor handoff, and review lifetime work in
  each supported environment?
- How should permission requirements and unavailable presentation capabilities
  be reported so the caller can recover without bypassing workflow checks?
- How should existing review records remain usable if their representation
  changes?

## Acceptance criteria

- A caller with no Herdr environment can create and inspect a real review of the
  exact aggregate change set, record findings, obtain explicit user approval,
  and land onto an existing chosen branch through devflow.
- The Codex desktop workflow completes without fabricated environment variables,
  manual review-state edits, or a workflow exception.
- Existing Herdr review and editor-handoff behavior continues to work.
- Launch, verification, and permission failures leave no falsely successful
  review record or changed landing target; recovery preserves unrelated state.
- Shared guidance documents both invocation contexts, approval semantics, and
  failure recovery without duplicating workflow policy in a harness.

## Verification

Extend the existing devflow tests for absent Herdr context, both presentation
paths, exact review identity, comments, failed launch/verification, unavailable
permissions, stale approval, concurrent activity, and unchanged landing guards.
Run the full devflow suite and its lint/type checks. Exercise real review and
landing flows in disposable repositories from both Herdr and the Codex desktop
app; mock-only tests are insufficient evidence for presentation and handoff.

## Starting points

- [`review.py`](../../tools/devflow/src/devflow/review.py)
- [`landing.py`](../../tools/devflow/src/devflow/landing.py)
- [`state.py`](../../tools/devflow/src/devflow/state.py)
- [`test_cli.py`](../../tools/devflow/tests/test_cli.py)
- [`Hunk integration`](../../nvim/lua/custom/plugins/hunk.lua)
- [`Development workflow`](../agents/development-workflow.md)
- [`Distributable agent guidance`](../../tools/devflow/src/devflow/guidance.md)
- [`Repository constraints`](../../AGENTS.md)
