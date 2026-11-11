# Review pieces cut from the canonical branch

Read this when the manager has chosen to cut review pieces from the canonical
WIP branch rather than reviewing each workstream on its own. All branches
here stay append-only. Creating branches and worktrees still needs the
person's or the project's authorization.

## Plan the cut

Order the pieces for a reviewer, not by who wrote them: foundations first,
each piece small enough to read in one sitting and complete enough to build
and pass on its own. Agree the list with the person, with each piece's
purpose and the files or hunks it takes.

Name pieces so their order shows: `wip/<feature>-01-<slug>`,
`wip/<feature>-02-<slug>`, and so on. Each is reviewed as
`review/<feature>-NN-<slug>`.

## Cut the pieces

Start from the target commit the canonical branch last merged. Each piece
starts from the head of the piece below it:

1. Create piece 01 from that target commit in its own worktree. Bring over
   its slice from the canonical branch: whole files with
   `git restore --source="$canonical" -- <paths>`, partial files by applying
   only the hunks it owns. Commit.
2. Create each next piece from the previous piece's head and repeat.
3. The last piece completes the feature. Check that its tree equals the
   canonical branch's tree; any difference is a lost or duplicated change:

   ```sh
   test "$(git rev-parse "$top^{tree}")" = "$(git rev-parse "$canonical^{tree}")"
   ```

Then test each piece as section 5 of the skill requires: the target plus the
pieces below it.

## Re-cut after a fix

Fixes still go on the owning workstream and merge into the canonical branch
first. Then carry them into the pieces, appending rather than rewriting:

1. Find the lowest piece the fix belongs to.
2. On that piece, commit its share of the fix.
3. On each piece above it, lowest first, merge the piece below's new head,
   then commit that piece's own share, if any.
4. Check the top piece's tree equals the canonical tree again.

Every piece that moved needs fresh review and approval. When pieces are
already submitted for review, update each submission in place, lowest
first, following the project's delivery steps, so reviewers keep the same
links.

## After a piece lands

Landing usually gives the piece a new commit on the target, so the target
does not contain the piece's own head, and the next piece's review base no
longer matches.

1. Merge the updated target into the next piece; this is a Target Merge. Its
   review base becomes the target commit that contains the landed piece.
2. Repeat upward through the stack, merging each piece below into the one
   above.
3. Merge the target into the canonical branch too, and check the top piece's
   tree against it again.
4. Feedback on the landed piece becomes a new change on top of the target.
