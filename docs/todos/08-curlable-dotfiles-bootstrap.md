# Add a curlable dotfiles bootstrap

## Outcome

Allow a new machine with curl and Git to begin dotfiles installation from one
documented curl-fed Bash command. The flow must establish or safely reuse a
durable repository checkout before invoking the checkout's local installer, so
the existing `install.sh` remains the installation authority and every managed
link and editable package source remains valid after bootstrap exits.

## Current evidence

The documented quick start requires cloning the repository, changing into the
checkout, and running `./install.sh`. The installer derives `REPO_ROOT` from
`BASH_SOURCE[0]`, preflights files and directories throughout that checkout,
links configuration targets directly to sources below `REPO_ROOT`, and installs
devflow as an editable package from `REPO_ROOT/devflow`.

Piping the current installer directly to Bash cannot satisfy those assumptions:
a script read from standard input has no usable source-file location, and the
rest of the repository is not present. A temporary archive is also insufficient
because successful installation intentionally retains absolute links and an
editable package relationship to the source checkout.

The existing manual workflow already requires Git before `install.sh` begins.
The installer then owns platform prerequisites, Homebrew, Mise runtimes,
devflow, configuration links, and its existing `--skip-mise-runtimes` degraded
mode. Bootstrap should not duplicate those responsibilities.

## Scope

- Provide a stable curl-based entry path that obtains or recognizes a durable
  local checkout and then invokes that checkout's `install.sh`.
- Preserve the current manual clone-and-install workflow.
- Forward supported installer arguments, including `--skip-mise-runtimes`,
  without changing their meaning.
- Validate `HOME`, root execution, the destination path, repository identity,
  and any existing checkout before changing bootstrap-owned state.
- Make interrupted or failed acquisition recoverable without replacing an
  occupied or user-owned destination.
- Document the trust and persistence implications of executing a remote
  bootstrap and retaining the resulting checkout.

## Boundaries / non-goals

- Do not make bootstrap a second implementation of dependency provisioning,
  linking, devflow installation, or uninstall behavior.
- Do not fetch, pull, switch, reset, clean, or otherwise update an existing
  checkout implicitly. Repository updates remain an explicit user Git action.
- Do not overwrite, relocate, or delete an existing foreign checkout or
  non-repository destination.
- Do not use an ephemeral checkout whose removal would leave managed links or
  the editable devflow installation pointing at missing sources.
- Do not remove the existing `install.sh`, `uninstall.sh`, or documented local
  invocation paths.

## Open decisions

- Should the curl entry point be a dedicated bootstrap file or a deliberately
  separated streamed mode that ultimately re-executes the local installer?
- What durable checkout location should be the default, and should an explicit
  override be supported?
- How should an existing checkout prove repository identity while accepting the
  supported HTTPS and SSH remote forms?
- Should bootstrap reuse a recognized dirty checkout, or stop and direct the
  user to its local installer so remote bootstrap never consumes uncommitted
  source changes implicitly?
- How should a partially completed first clone be staged and recovered?
- Should the primary command follow the repository's default branch, a release
  tag, or an explicitly selectable revision, and what inspect-before-execute
  alternative should the documentation provide?

## Acceptance criteria

- From outside any checkout, the documented curl command establishes a durable
  checkout and successfully hands execution to that checkout's installer.
- The installed configuration and devflow ownership receipt refer to the
  durable checkout rather than temporary bootstrap files.
- Installer arguments are forwarded exactly, including degraded mode.
- Repeating the curl command against a recognized checkout performs no implicit
  Git update and preserves the installer's ordinary second-run behavior.
- An occupied destination, foreign repository, unsafe home, root invocation,
  failed acquisition, or disallowed existing-checkout state is preserved and
  rejected with an actionable message before installation begins.
- The documented manual clone workflow continues to work unchanged.

## Verification

- Exercise bootstrap with isolated homes and a local test repository so the
  suite does not depend on GitHub or the network.
- Cover a fresh checkout, an unchanged repeated invocation, argument
  forwarding, an occupied destination, a foreign repository, the chosen dirty
  checkout policy, clone failure, and unsafe home values.
- Verify the bootstrap performs no fetch, pull, switch, reset, or clean against
  an existing checkout.
- Run `bash -n` over every affected shell file and bootstrap test.
- Run `bash tests/install_test.sh` to preserve the existing install and
  uninstall contract.
- Run `git diff --check`.

## Starting points

- [`install.sh`](../../install.sh)
- [`uninstall.sh`](../../uninstall.sh)
- [`tests/install_test.sh`](../../tests/install_test.sh)
- [`README.md`](../../README.md) — quick start, installer behavior, and rollback
- [`AGENTS.md`](../../AGENTS.md) — install, uninstall, and workflow contracts
