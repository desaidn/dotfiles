# Environment overlays

An **environment overlay** is the set of source changes a deployment needs
to run in one particular environment, and that must never be reviewed or
landed. Typical examples are a development account added to a hard-coded
allowlist, or a one-line hook that reads a namespace from an environment
variable instead of the user name. Values the code already reads at deploy
time, such as an account, region, or profile in an untracked environment
file, are not an overlay; keep them in those untracked files.

An overlay contains only what the environment needs: identifiers,
namespaces, endpoints, and the smallest hooks that read them. Documentation,
other people's settings, and anything else does not belong in it, even when
it happens to sit on the branch the overlay started from.

## First, weigh needing no overlay

Every overlay is a branch to keep current, a source of merge conflicts with
the target, and a reason the deployed code differs from the reviewed code.
Before creating one, consider whether a small upstream change would remove
it:

- **A hook** that reads a value from the environment, falling back to
  today's behaviour, can usually be landed once on its own. After that the
  value lives in an untracked file and the overlay loses that line.
- **An entry in someone else's configuration**, such as an allowlist, may be
  worth submitting through its owner's review, or may be personal enough to
  stay in the overlay.

This is a judgement call, not a rule: upstreaming takes another review and
someone else's time, while an overlay costs maintenance for as long as the
feature is deployed. Raise it with the person when the overlay is first
needed, and again if it keeps conflicting.

## Keep one overlay per environment

When an overlay is needed:

- Keep it on one branch per environment, named so it is clearly not WIP, for
  example `env/<environment>`, in the project's own repository. Do not depend
  on another checkout's remote, which may disappear.
- Start it from the target branch, not from a setup or feature branch, so it
  carries nothing else. Its diff against the target should show only overlay
  changes.
- Keep it current by merging the target into it when they conflict. Like
  WIP, it is append-only.
- Never merge it into a workstream, a review piece, or the canonical branch.

## Deploy from a disposable checkout

Combine code with an overlay only in a deploy checkout on a detached HEAD,
so no branch is created that must be cleaned up later:

```sh
git worktree add --detach "$deploy_checkout" "$code_commit"
git -C "$deploy_checkout" merge --no-edit "env/$environment"
```

Before each deploy, check:

1. The deploy checkout differs from the code commit only in the overlay's
   files:

   ```sh
   git -C "$deploy_checkout" diff --stat "$code_commit" HEAD
   ```

2. The active credentials or deployment target belong to the overlay's
   environment. Environments often share resource names, so a deploy to the
   wrong one can look identical. Fail rather than fall back when
   credentials are missing.
3. The build starts clean, not from another deploy's leftover output.

Record what was deployed as the code commit and the overlay commit together,
with the environment. The code commit is what tree checks and reviews refer
to; the overlay is never part of them.

Recreate the deploy checkout for the next deploy rather than committing on
top of it. Never review or land from it. Once a run's result is recorded,
the checkout and its build output are disposable: remove them when the
person has authorized it, and otherwise list them for cleanup.
