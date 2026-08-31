# Dotfiles

Personal development environment configuration, organized around a small set of durable workflow surfaces.

## Language

**Development Surface**:
The primary place where development work is initiated, coordinated, and returned to after using supporting tools.
_Avoid_: Editor, shell, terminal

**Host Window**:
The most recently used non-tool window to which Tool Tabs return. Moving between Tool Tabs does not change the Host Window.
_Avoid_: Main buffer, previous tab, calling tool

**Tool Tab**:
A dedicated Development Surface workspace owned by one terminal-tool instance. Invoking a tool selects the existing instance for the Host Window's context; singleton tools have one instance. The workspace exists until that instance's process exits.
_Avoid_: Terminal float, tool window, Terminal Tool Surface

**Language Tooling**:
The language-centered part of the Development Surface contract: source-language capabilities that require coordination across supporting tools are declared as one coherent capability.
_Avoid_: Tool config, plugin-specific language setup

**Language Tooling Inventory**:
The canonical read-only catalogue of enabled LSP configurations, Mason packages, Treesitter parsers, Conform formatting policy, and nvim-lint mappings shared across supporting tools; it stays in plugin-native data shapes so those tools can consume it directly.
_Avoid_: LSP server list, formatter list, parser list

**Review Surface**:
A focused place for inspecting complete changesets before deciding what to keep, change, or commit.
_Avoid_: Diff viewer, pager

**WIP Branch**:
The append-only development history for one feature. Feedback extends it with new commits, and landing never rewrites or deletes it.
_Avoid_: Feature branch, topic branch, mutable work branch

**WIP Guard**:
A repository-local safeguard that permits a WIP Branch to be created and advanced while preventing its history from being rewritten or deleted, including during push.
_Avoid_: Global Git policy, security boundary, advisory rule

**Work Flow**:
The branch lifecycle that creates and extends a WIP Branch. It can supply a Change Set to the Review Flow but is not required by it.
_Avoid_: WIP workflow, development flow, review workflow

**Workflow Engine**:
The Python 3.14 application that validates and performs Work Flow, Review Flow, and Squash Landing transitions. It is managed with `uv`, models decisions with typed immutable data and pure functions, and keeps Git and user-interface effects at its outer boundary.
_Avoid_: Shell script, agent prompt, Git wrapper

**Main Merge**:
An ordinary merge of `main` into a WIP Branch. It records when concurrent mainline changes entered the feature without rewriting its history.
_Avoid_: Rebase, branch refresh, sync commit

**Change Set**:
An immutable unit of code change presented for review, identified by its base and resulting revision. It may originate from a WIP Branch or from externally authored code.
_Avoid_: Diff, branch, working tree

**Review Flow**:
A read-only workflow that presents a Change Set through the Review Surface and coordinates human review with the Agent Review Loop. It does not require or mutate a WIP Branch.
_Avoid_: WIP workflow, development workflow, landing flow

**Review Snapshot**:
The exact Change Set presented through the Review Surface. For locally developed features, it is taken only after WIP incorporates current `main`; for external code, it preserves the supplied change identity without creating WIP history.
_Avoid_: Review copy, synthetic squash, review commit

**Invoking Checkout**:
The Git checkout containing the directory from which the Workflow Engine is invoked. It may be the repository's primary checkout or a user-created worktree, and it remains the sole project context for that invocation.
_Avoid_: Canonical checkout, managed checkout, repository checkout

**In-place Checkout**:
The invariant that Work Flow and Review Flow use only the Invoking Checkout and leave all worktree topology under user control. It does not imply that the repository has only one worktree.
_Avoid_: Checkout mode, no-worktree repository, automatic checkout

**Review Branch**:
A read-only `review/*` ref that exposes a Review Snapshot without being checked out by the Workflow Engine. Only the Review Flow may create or advance it to the selected Change Set revision; development changes never originate there.
_Avoid_: Staging branch, second WIP branch, review copy

**Review Approval**:
Explicit authorization that the latest Review Snapshot represents the complete feature and may land. A newer WIP revision invalidates it; movement on the Mainline Branch does not unless integration requires new WIP commits.
_Avoid_: Base approval, branch approval, blanket approval

**Mainline Branch**:
The shared integration history named `main`, `mainline`, or `master`. It advances only through a Squash Landing of the latest reviewed and approved complete feature.
_Avoid_: Base branch, development branch, direct-commit branch

**Landing Candidate**:
The prospective result of applying an approved Review Snapshot to the current Mainline Branch as one logical feature change. It is validated before the Mainline Branch advances.
_Avoid_: Merge result, squash branch, release candidate

**Squash Landing**:
The single-commit integration of the latest reviewed and approved complete feature into the Mainline Branch. It leaves the WIP Branch unchanged.
_Avoid_: Merge commit, partial landing, direct mainline commit

**Workflow Exception**:
Any branch or worktree action outside the Work Flow, Review Flow, and Squash Landing contract. It requires explicit user approval before execution.
_Avoid_: Edge case, implicit permission, automatic recovery

**Diffing Solution**:
The canonical renderer for changed code across Git-facing tools in the development environment.
_Avoid_: External diff, pager, renderer

**Git Transaction Surface**:
The place for choosing Git objects and changing Git state, including staging, committing, stash operations, branch navigation, and history inspection.
_Avoid_: Git UI, commit tool

**Editor Handoff**:
The transition from a supporting surface back into the host Neovim at the file and line being inspected, preserving the Invoking Checkout's project context. Terminal tools should use the same Editor Handoff mechanism instead of bespoke per-tool launch shims.
_Avoid_: Open file, jump to editor, tool-specific editor wrapper

**Global Editor Contract**:
The shell-owned environment contract that declares Neovim as the default editor for terminal tools through `EDITOR`, `VISUAL`, and `GIT_EDITOR`.
_Avoid_: Per-tool editor override, launcher-local editor setting

**Agent Review Loop**:
A review workflow where a local agent inspects and annotates the same Hunk session the developer is viewing.
_Avoid_: AI review, bot review

**Agent Harness**:
The product or runtime that hosts a coding agent, such as Codex or Claude Code.
_Avoid_: Agent, assistant, AI tool

**Code Interface**:
The stable set of local surfaces used to inspect, edit, review, and commit code, regardless of which agent harness is active.
_Avoid_: Agent UI, IDE integration

**Default Bias**:
The preference to keep upstream tool behavior unless a deviation directly supports the uniform code interface.
_Avoid_: Minimal config, vanilla config
