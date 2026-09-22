# Pass review revisions as HunkReview arguments

## Outcome

Replace `HUNK_REVIEW_BASE_OID` and `HUNK_REVIEW_HEAD_OID` with explicit
`:HunkReview <base-oid> <head-oid>` arguments. Support both an existing Neovim
session and startup from the review checkout:

```sh
nvim -c "HunkReview $base_oid $head_oid"
```

Implement this separately from the retirement of devflow. This brief records
future work; the current launcher still uses environment variables.

## Context / current state

[`hunk.lua`](../../nvim/lua/custom/plugins/hunk.lua) reads both variables when
loaded, validates full lowercase object IDs, and conditionally registers
`:HunkReview` for `hunk diff BASE...HEAD --watch --mode stack`.

The shared [terminal-tool helper](../../nvim/lua/custom/lib/terminal_tool.lua)
currently copies fixed command arguments at registration and creates Ex commands
without argument handling. Its reuse path compares the selected variant rather
than the actual command arguments; changing revisions must not accidentally
toggle or reuse a process displaying the previous diff. Startup invocation is
deferred until the UI is ready, so arguments must survive that deferral.

## Scope and boundaries

- Replace the environment-variable interface rather than maintain two launch paths.
- Require two full immutable commit IDs initially. Keep base selection, commit
  resolution, ancestry checks, and approval policy with the calling workflow.
- Keep terminal lifecycle, checkout isolation, and editor handoff in the shared
  helper; do not introduce a separate terminal implementation, CLI, or plugin.
- Update the shared workflow, Neovim guidance, and affected tests together.
- Preserve the exact-snapshot review rules; changing revisions starts a different
  review and cannot carry approval forward.

## Open decision

Should `<leader>gd` toggle the checkout's most recently selected exact-revision
review, as it does in today's review context, or always select working-tree
changes? Make the behavior explicit and keep staged review accessible through
`<leader>gD`.

## Acceptance criteria

- `:HunkReview BASE HEAD` works without review environment variables, both
  interactively and through `nvim -c`, showing the exact requested diff.
- Missing, extra, malformed, or mismatched-length IDs produce a clear error
  without disrupting an existing valid review; accept full SHA-1 and SHA-256 IDs.
- Repeating the same range preserves the existing toggle/reuse behavior.
  Selecting a different range displays that new range, with one Hunk process
  and Tool Tab per checkout and independent state across checkouts.
- Hunk's `e` action still returns to the correct Neovim host with project tooling.
- Maintained launch instructions and configuration no longer depend on the old
  review environment variables.

## Verification and starting points

Read [`nvim/AGENTS.md`](../../nvim/AGENTS.md) and the
[development workflow](../agents/development-workflow.md). Check current Neovim
user-command documentation before choosing the helper interface.

Extend the existing terminal-tool regression and PTY rendering tests under
[`nvim/tests/`](../../nvim/tests/) to cover argument validation, startup deferral,
same-range reuse, changed-range retargeting, and independent checkouts. Exercise
a real Herdr launch and Hunk editor handoff, and verify working-tree and staged
review still follow the documented mappings. Run the scoped Neovim checks
required by its guidance.
