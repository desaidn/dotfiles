---
name: upgrade-dependencies
description: Upgrade this dotfiles repository's managed dependencies, or a requested subset, across Homebrew, Mise, and Neovim. Use for dependency upgrade execution or inspection; a request for instructions or an update report remains read-only.
---

# Upgrade dependencies

Bring the selected dependency inventory up to date, verify the installed result,
and preserve reproducible runtime pins and plugin revisions. This skill is for
this dotfiles repository, not application dependencies in unrelated projects.
It uses ordinary Markdown and native tools; any agent can follow this file
directly, without a harness-specific command or plugin.

Paths named in prose are relative to the canonical repository root. Read
[AGENTS.md](../../../AGENTS.md), the
[development workflow](../../../docs/agents/development-workflow.md), and
[dependency ownership and version policy](../../../README.md#dependency-ownership)
before acting. Those documents own policy; this skill owns upgrade mechanics.

## 1. Establish scope and a usable checkout

Carry forward the user's selected scope, checkout, release lines, target branch,
and permissions. A full upgrade means the repository-managed inventory below,
not every package or application installed on the machine. A scoped request
such as "upgrade Neovim dependencies" includes its supporting tools and runtimes,
but does not add unrelated shell applications or casks. State the selected scope.
Questions, plans, and inspection requests authorize discovery only; do not launch
normal Neovim startup or run package upgrades for them.
For inspection only, report the inventory and available evidence without preparing
a WIP branch or establishing review readiness. If the user requests no changes
at all, defer metadata refreshes that write caches and disclose stale candidates.

Before changing files or installed packages:

- Inspect `git status --short --branch` and `git worktree list --porcelain`.
  Record the canonical checkout, branch, and explicit starting commit.
- Inspect `hunk session list --json` and the intended Herdr workspace with real
  access to their sockets. A sandboxed empty list is not reliable evidence that
  no review exists if socket access is restricted. Resolve access first; use the
  harness's permission mechanism when needed. An existing different review must
  be coordinated before edits, not discovered at final commit time.
- When tracked pins, lockfiles, or configuration will change, follow the
  development workflow to create or resume the appropriate WIP branch. Pure
  installed-package work preserves the current branch. Use the workflow's
  approval rules for closing an unrelated review. Keep the starting commit as
  the proposed review base unless integration changes it.
- Inspect inventory without provisioning: read manifests, plugin lockfiles,
  installed package metadata, and CLI help. Normal Neovim startup can install
  missing tools and rewrite its lockfile.

For execution, this step is complete when the authorized scope, starting snapshot,
and ability to perform the selected mutations without disturbing another review
are established.

## 2. Build the upgrade inventory

| Owner | Authoritative scope | Record before changing it |
| --- | --- | --- |
| Homebrew | Active-platform `Brewfile` entries, plus installer-owned macOS casks documented in the root README; their installed runtime dependency closure | Installed versions, pins, available stable versions, package type and ownership |
| Mise | `mise/conf.d/00-dotfiles.toml` | Exact selectors, version lines/vendor, Rust profile/components, effective config sources, installed versions |
| Neovim plugins | Configuration declarations and `nvim/nvim-pack-lock.json`, reconciled with installed `vim.pack` packages | Source, constraint, revision, active/inactive state, local plugin edits |
| Mason | `mason_tools` from the enabled language adapters; additionally installed tools only when included in the user's scope | Receipt/installed version, refreshed registry candidate, any explicit pin or condition |
| Treesitter | The adapters' `treesitter_parsers`; additional installed parsers only when included in scope | Installed parsers and revisions supported by the selected plugin |

The platform owns SDKs, native compilers, and OS utilities. Verify required
capabilities and report a missing/broken platform prerequisite; a dependency
upgrade is not an OS/Xcode upgrade or authorization to install another compiler.
Preserve the existing ownership split and retained dependencies. Optional
provider warnings do not add packages to this inventory.

Resolve current candidates from the installed manager and authoritative upstream
documentation, not remembered version numbers. Preserve plugin constraints and
deliberate pins. By default retain Node's major, Python's minor, and Java's vendor
and JDK line; advance Rust within its selected stable major. Honor the manager's
release-age policy. Ask only for an unresolved change of release line, pin,
ownership, or scope that is needed to proceed.

For each selected item, track its before version, candidate, and eventual outcome:
updated, already current, intentionally held, unsupported, or failed. Temporary
logs are sufficient unless the user asks for a saved report. Keep approval
evidence in the conversation under the existing development workflow.

## 3. Apply upgrades by owner

Read the relevant reference before changing that layer:

1. [Homebrew and Mise](references/package-managers.md): update selected
   applications and native libraries, then resolve and install exact runtimes.
2. [Neovim](references/neovim.md): update plugins and their native builds; use a
   fresh configured process for Mason and parser updates.

Use the newly selected runtime environment for dependent installers and checks.
Parallelize independent discovery or reviews when helpful; serialize managers
that write the same installed packages, lockfile, or caches. Keep one Neovim
maintenance process at a time. Preserve existing installations and backups;
cleanup, package removal, and unrelated global configuration edits are separate
work. Do not run the full installer merely to upgrade dependencies: it also
changes configuration links and intentionally avoids broad upgrades.

If a layer fails, retain its logs and partial outcomes. Diagnose the failed item
before retrying it; continue independent authorized work when possible. Never
turn a zero process exit or a completed progress indicator into a blanket success
claim. Reconcile actual installed versions and files before resuming after an
interruption, rather than replaying every successful upgrade.
Coherent validated progress can be preserved in ordinary WIP commits, explicitly
reported as incomplete. Failures do not silently narrow the task: obtain the
user's agreement before treating deferred items as outside the completion scope.
Do not request approval to land a complete upgrade while selected failures remain.

## 4. Validate the installed result

Follow [validation and completion](references/validation.md) and the relevant
tool's current instructions. Update active docs and version-dependent fixtures
when changing exact pins; preserve historical audits and ADR evidence. Keep
compatibility minimums unchanged unless a required capability justifies a change.

Every selected item must have a verified outcome. A pinned, release-age-delayed,
unsupported, or failed item must remain visible in the result. Distinguish
optional health warnings from broken configured capabilities. Run the required
checks once; repeat them for actual changes, failures, or concurrent checkout
activity that invalidates the earlier result.

## 5. Deliver the upgrade

For tracked changes, complete the native Git/Herdr/Neovim/Hunk procedure in the
development workflow: commit the validated WIP, inspect the entire exact live
review, publish its snapshot marker, and request snapshot approval only when
required and not already supplied for that same snapshot. Add actionable
findings to that live review. A previous feature's approval is not approval of
new versions. Reuse an already selected landing target; ask only if none exists.
Do not manufacture an empty commit or review when no tracked content changed.

Report the scope and meaningful before/after versions, verified counts, held or
failed items, validation results, and actual Git delivery state. Installed
machine updates take effect before Git landing; say clearly if those succeeded
while review or landing is still pending. Mention fresh shell/editor sessions
when needed. Preserve WIP/review history and obtain separate authorization for
any push, submission, or cleanup required beyond the agreed task.
