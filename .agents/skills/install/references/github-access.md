# GitHub access and commit identity for this checkout

During setup, verify this checkout's personal GitHub login through `gh` and set
its commit email to `me@desaidn.dev`.
Authentication is not permission to push, change remote branches, or publish.
Keep account names, key paths, and device codes out of this skill.

## Check the login and commit identity

Use the existing GitHub CLI configuration for this checkout. When its local
`git gh` alias selects a separate profile, use that alias for `gh` commands;
otherwise use `gh` directly. Check `gh auth status` and `gh api user --jq .login`
through the selected invocation and confirm the intended personal account.
Preserve working authentication; use the login procedure below only when needed.

GitHub authentication and Git commit identity are separate settings. Set this
checkout's commit email without changing the global email or existing name:

```sh
git config --local user.email me@desaidn.dev
```

Check `git config --show-origin --get user.email`, `git var GIT_AUTHOR_IDENT`,
and `git var GIT_COMMITTER_IDENT`. Both effective identities must use
`me@desaidn.dev`. Preserve existing commits and report any environment override
that prevents the local setting from taking effect.

## Establish the scope

Inspect the checkout's remote protocol, existing authentication, and relevant
Git configuration origins without exposing credentials. Carry forward the
user's account, protocol, and configuration-scope choices.

Preserve working SSH or HTTPS access. If a protocol decision is needed, consult
GitHub's current [setup guide](https://docs.github.com/en/get-started/git-basics/set-up-git);
distinguish its recommendation from the protocols it supports.

By default, make Git configuration changes local to this checkout. Explain
that repository-local Git settings do not make a `gh` login repository-local:
its credentials and host protocol preference are user-level state. If the user
needs credentials limited to one repository, establish that requirement before
choosing an authentication mechanism.

Record enough of the existing relevant local and global Git configuration to
verify the agreed scope afterward. Preserve existing credential helpers when
they are outside the agreed host and repository scope.

## HTTPS through GitHub CLI

Check the installed `gh auth login --help` and
[login documentation](https://cli.github.com/manual/gh_auth_login) before use.
Use the selected invocation above for the `gh` commands in this procedure.
When login is needed and authorized, run it interactively in a persistent
terminal:

```sh
gh auth login --hostname github.com --git-protocol https --web
```

Decline the prompt to configure Git authentication automatically when the
agreed scope is repository-local. Do not run `gh auth setup-git` for that scope;
it changes global Git configuration rather than this checkout's configuration.
See the [setup-git documentation](https://cli.github.com/manual/gh_auth_setup-git).

For the agreed GitHub HTTPS helper, run from the selected checkout:

```sh
git config --local --replace-all credential.https://github.com.helper ''
git config --local --add credential.https://github.com.helper '!gh auth git-credential'
```

The empty entry clears inherited helpers for this URL; the next entry selects
GitHub CLI. Both changes belong in this checkout's `.git/config`. Verify the
effective entries and their origins. Adapt the host only when that was selected.
Git documents [configuration scope](https://git-scm.com/docs/git-config) and
[helper reset/selection](https://git-scm.com/docs/gitcredentials).

Send the actual device URL and current code promptly. Keep the login process
alive while waiting for the user; report authentication as pending. If the code
expires, restart login and send the new code. After the user authorizes, check
the process result and authenticated account instead of assuming success.

GitHub CLI may fall back to a plaintext credential file when a system credential
store is unavailable. Report that storage mode if it occurs, without displaying
the token; do not claim the login is confined to this repository.

## Verify the requested access

Confirm `gh auth status`, the intended account, the remote, and the effective
repository-local helper. Compare the relevant global Git configuration with
the earlier state and report any unexpected change.

For read access, a successful remote read is appropriate. For requested push
access, also check repository write permissions and, when useful, an explicitly
targeted `git push --dry-run`. A remote read alone does not verify push access;
a dry run does not guarantee that every branch-protection rule permits a
future real push.

Report the verified access and any remaining browser action. Leave real pushes,
SSH key replacement, account changes, and credential cleanup to their explicitly
authorized scope.
