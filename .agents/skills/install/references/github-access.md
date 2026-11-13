# GitHub access for this checkout

Use this only when repository access is part of the user's setup request.
Authentication is not permission to push, change remote branches, or publish.
Keep account names, key paths, and device codes out of this skill.

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
