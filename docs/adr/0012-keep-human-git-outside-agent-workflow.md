---
status: amended by ADR-0013
---

# Keep human Git outside the agent workflow

The deny-by-default branch policy governs coding-agent actions only. Human Git
and LazyGit remain wholly unrestricted, so devflow installs no repository hooks,
changes no Git policy configuration, and never denies or rewrites a human
branch, ref, push, checkout, reset, rebase, or worktree operation. Harness
guidance requires agents to use the Work Flow, Review Flow, and Squash Landing
commands and to request explicit approval for an agent action outside that
contract. This supersedes ADR 0007 and the hook-entrypoint portion of ADR 0009
while preserving ADR 0009's Python, packaging, and functional-core decisions.

Devflow still validates every transition it owns. It may refuse its own command
when it observes a conflicting human checkout, dirty invoking checkout, stale
snapshot, changed ref, or incompatible history, but it does not reserve that
state. Compare-and-swap protects the refs in the final transaction; no mechanism
can prevent a human operation after an earlier preflight or serialize another
worktree's index and files. Concurrent activity in a shared checkout is therefore
an explicit coordination boundary, and agents must revalidate after human Git
operations.

Squash Landing names `main`, `mainline`, or `master` with a required `--target`
argument. Devflow never infers or falls back to another integration branch.
