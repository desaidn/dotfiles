---
name: install
description: Install or reapply this dotfiles checkout, assess the machine before and after ./install.sh, and handle setup that needs judgment or user input.
---

# Install dotfiles

Assess the machine, run `./install.sh`, and establish whether the intended setup
works in the user's actual environment. The installer owns repeatable
provisioning and linking. This skill supplies the judgment around it: preserving
personal settings, interpreting failures, checking integrations, and resolving
manual steps or choices that a shell script cannot reasonably decide.

Creating or discussing this skill does not itself authorize installation.
Paths below are relative to the dotfiles checkout.

## 1. Assess before installing

Read [AGENTS.md](../../../AGENTS.md), the
[installation guide](../../../README.md#quick-start), and
[dependency ownership](../../../README.md#dependency-ownership). Inspect
`install.sh` to distinguish its existing checks from work that needs assessment.

Carry forward the selected machine, checkout, scope, and prior decisions.
Inspect the OS, architecture, shell, local or remote session, display
availability, `git status --short --branch`, and
`git worktree list --porcelain`. Use the task's terminal environment and its
applicable skill. A machine-only installation needs no new branch. Preserve
unrelated work; establish whether local changes to installer inputs are intended.
Pull only when requested, using the existing checkout and agreed Git workflow.

Build a concise checklist for before and after installation from the machine's
role, the repository's setup, and the user's intended workflows. Cover each
applicable area without testing every installed capability:

| Area | What requires assessment |
| --- | --- |
| Configuration and personal state | Existing links, overrides, customizations, and agent instructions; what installation will preserve or back up, and what may need selective migration. |
| Effective tools and environment | What the user's shell and applications actually select, including stale processes or competing installations. |
| Editor and development | Startup health, plugin and tool provisioning, and a representative workflow appropriate to the languages the user uses. |
| Workspace and integrations | The current terminal/editor arrangement, clipboard and editor handoff, and platform-specific first-launch or permission steps. |
| Access | Authentication and connections required for the requested work, with their intended account and configuration scope. |

Record enough of the current state to identify existing issues and recognize
changes afterward, including relevant configuration sources and backup paths.
Use the tool guides linked from the README for expected behavior. Establish
material choices before they affect the install; ask only when evidence and
prior decisions do not settle them.

## 2. Run the installer

Run `./install.sh` from the selected checkout and retain its output and actual
exit status. Use a persistent terminal for a long run. Use the full install
unless the user selected `--skip-mise-runtimes`; failure does not authorize
silently switching modes.

On failure, identify the stage and cause before choosing a repair. A system
dialog, authentication prompt, or conflicting user-owned instruction may need
intervention. Prepare the specific next step while preserving existing state.
A restriction in the agent's environment does not prove the host cannot do the
work; use the available permission mechanism for authorized actions. After a
user completes a blocked step, inspect the result before resuming.

Rerun the installer after resolving its blocking cause; it owns resumable
provisioning and link idempotence. A zero exit status starts the after-install
assessment.

## 3. Reconcile and verify afterward

Inspect warnings, skips, backups, and manual instructions in the install output.
Revisit every applicable area from the baseline using targeted checks in the
actual configured environment. Confirm useful behavior through representative
workflows in addition to package and installer checks.

Review replaced configuration and preserved overrides for settings that still
matter to the user, even when tools appear healthy. Propose selective migrations
into the appropriate local configuration; explain omissions and resolve
uncertain choices. Reuse existing authorization, back up affected local files,
and preserve unrelated settings and original backups.

Use each tool's documented diagnostics and representative integration checks.
For example, distinguish Neovim's version from successful startup and editor
tool provisioning, or a clipboard executable from working clipboard behavior
in this display or SSH session. Interpret results for the machine's role; a
remote host does not need a local desktop application.

Check startup-dependent changes in fresh configured processes and identify
which existing sessions still need refreshing. An agent subprocess does not
refresh the user's terminal. Use existing surfaces where possible; opening
tabs, restarting applications, changing login shells, and configuring additional
access require the relevant user request.

Use these references when their conditions arise:

| Condition | Reference |
| --- | --- |
| Verify managed runtime selection, or diagnose competing binaries, overrides, or stale activation. | [Runtime environment](references/runtime-environment.md) |
| Recover settings from shell backups or reconcile preserved per-machine startup files. | [Shell settings](references/shell-settings.md) |
| Assess this checkout's personal GitHub login and commit identity, or handle requested push access. | [GitHub access and commit identity](references/github-access.md) |

These are known cases, not the limit of the assessment. Follow observed issues
in other configured tools through their owning guides. Make focused repairs
within the agreed scope, then repeat the affected checks. Leave broad upgrades,
new optional integrations, and removal of old installations or backups to their
own requests.

## 4. Report what is established

Report the installer outcome, the areas and workflows actually verified,
approved migrations and backup locations, accepted differences, and remaining
failures or user actions. Distinguish prepared, applied, and verified work.
Pending browser authorization, first launch, or a required session refresh
remains pending; a skipped check is not a successful check.

Account for every applicable area before finishing. Claim the setup is ready
only to the extent demonstrated, and make any incomplete portion explicit.

When a new reusable case appears, capture its trigger, decision, and
verification in a focused reference. Put repeatable deterministic checks in
the installer where practical. Keep this skill centered on assessment and
judgment.
