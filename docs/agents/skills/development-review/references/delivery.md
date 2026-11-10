# Delivery

Delivery sends a landed change somewhere others review it. It happens only
when the user explicitly asks. It is the one step that differs between
machines and repositories; everything before it is the same everywhere.

## Choose the method

Use the first source that settles it:

1. **The user's request** in the conversation, such as "open a pull request"
   or "submit it for code review".
2. **The project's instructions**, if they name a delivery method or tool.
3. **Instructions installed on this machine**, such as a code-review skill or
   rules supplied by the machine's environment. Follow them for the
   submission command and its conventions.
4. **A `github.com` remote** for the target branch: a GitHub pull request.
5. **Otherwise**, there is nothing to deliver: landing was the last step. If
   the user still asked for delivery, explain what is missing and ask.

Do not guess an internal tool or service from hostnames, and do not install
one.

## Deliver the landed commit

Landing already produced the single squashed commit to deliver, so delivery
creates no new local branch. Before submitting, verify:

- The target branch's HEAD is the landed commit, recorded with its feature,
  approved snapshot, and Review Branch in the conversation.
- The landed commit's parent is the current head of the remote base branch
  (fetch it first). Otherwise the submission would include other commits, or
  the base has moved. Stop and explain; resolving it belongs in WIP with a
  fresh review, not in the target branch.
- `wip/<feature>` and `review/<feature>` are unchanged. Recheck both after the
  submission, because some tools add metadata or switch branches.

Before running any submission tool, check whether it can amend commits, change
branches, or push on its own. Verify afterward that the submitted change
matches the landed commit's tree. Describe the concrete problem, resulting
behavior, and relevant validation in plain language.

## GitHub pull request

The user's request to open a pull request authorizes pushing this one branch.
Use the feature's name for the remote branch:

```sh
git ls-remote --heads "$remote" "review/$feature"   # must print nothing
git push "$remote" "$landed_oid:refs/heads/review/$feature"
gh pr create --repo "$repository" --base "$base_branch" \
  --head "review/$feature" --title "$title" --body-file "$body_file"
gh pr view "review/$feature" --repo "$repository" --json headRefOid,url
```

If the remote branch already exists, stop and ask; never force-push it.
Confirm `headRefOid` equals the landed commit, then report the URL. The local
`review/<feature>` keeps marking the reviewed snapshot; only the remote branch
carries the landed commit.

## Code review system provided by the environment

Follow the installed instructions or skill for that system. Apply the checks
above, keep the description to the change itself, and report the submission's
link or identifier.

## No remote delivery

When the repository has no review destination, the landed commit on the
selected local branch is the result. Say so instead of creating one.
