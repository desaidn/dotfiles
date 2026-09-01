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
The append-only development history for one feature, named `wip/<feature>`. Devflow creates it from the Invoking Checkout's current commit or resumes it without rewriting it.
_Avoid_: Feature branch, topic branch, mutable work branch

**WIP Guard**:
The agent-only rule that WIP changes append history. Harness guidance constrains agent actions and devflow validates transitions it owns; no repository hook constrains human Git or LazyGit.
_Avoid_: Repository hook, global Git policy, security boundary

**Work Flow**:
The part of devflow that creates or resumes a WIP Branch and carries locally authored work into Review Flow.
_Avoid_: WIP workflow, development flow, review workflow

**Workflow Engine**:
The `devflow` Agent Tool that orchestrates Work Flow, Review Flow, and Squash Landing while accepting project-specific choices as explicit inputs.
_Avoid_: Shell script, agent prompt, Git wrapper

**Agent Tool**:
A small independently named utility that agent instructions, skills, scripts, people, and other tools can invoke directly.
_Avoid_: Plugin, workflow framework, generic subcommand

**Tool Workspace**:
The repository's `tools/` directory, which organizes independent Agent Tools such as `tools/devflow/`. It is a source layout rather than an umbrella command, plugin registry, or shared framework.
_Avoid_: Tools CLI, plugin directory, application framework

**Project Workflow**:
The team-specific process composed around devflow, including checkout or worktree preparation, branch conventions, publishing, team review, queues, and onward delivery.
_Avoid_: Devflow plugin, built-in team workflow, hard-coded convention

**Composition Surface**:
The small command-line and JSON interface through which a Project Workflow supplies explicit choices and consumes validated results. Devflow has no plugin, callback, hook, or project-configuration layer.
_Avoid_: Plugin API, workflow hooks, embedded team configuration

**Target Merge**:
An append-only merge of Landing Target changes into WIP when integration requires feature changes before landing. The resulting WIP must be reviewed again.
_Avoid_: Rebase, landing-time conflict resolution, hidden integration fix

**Change Set**:
An immutable unit of code change identified by an explicit Review Base and source revision. It may originate from a WIP Branch or from externally authored code.
_Avoid_: Diff, branch, working tree

**External Change Set**:
A Change Set authored outside the local Work Flow and reviewed without creating or mutating a WIP Branch. It uses the same Review Flow but cannot use Squash Landing.
_Avoid_: External workflow, adopted WIP, landable review

**Review Base**:
The exact revision explicitly chosen as the comparison point for a Review Snapshot.
_Avoid_: Inferred mainline, default branch, landing destination

**Review Flow**:
A source-read-only workflow that presents either WIP or an External Change Set through the same Herdr, Neovim, Hunk, and Agent Review Loop.
_Avoid_: WIP workflow, development workflow, landing flow

**Review Snapshot**:
The exact Change Set presented through the Review Surface, including its Review Base, source revision, and resulting tree. A local snapshot names the exact WIP head; an external snapshot remains review-only.
_Avoid_: Review copy, synthetic squash, review commit

**Review Record**:
The durable immutable evidence for one successfully opened Review Snapshot, identified by its review ID.
_Avoid_: Approval record, mutable review state, workflow log

**Invoking Checkout**:
The project directory from which devflow is invoked, whether it is the primary checkout or a worktree.
_Avoid_: Canonical checkout, managed checkout, repository checkout

**In-place Checkout**:
The invariant that devflow operates in its Invoking Checkout and leaves worktree topology to the Project Workflow.
_Avoid_: Checkout mode, no-worktree repository, automatic checkout

**Review Branch**:
A `review/<name>` branch that points to the exact source revision in a Review Snapshot. For local work it matches WIP; for an External Change Set it cannot land.
_Avoid_: Staging branch, second WIP branch, review copy

**Review Approval**:
The user's explicit authorization that one exact local WIP Review Snapshot represents the complete feature and may land. It becomes stale when WIP or its Review Branch changes.
_Avoid_: Base approval, branch approval, blanket approval, teammate approval

**Mainline Branch**:
The project's normal shared integration history, commonly named `main`, `mainline`, or `master`. It is one possible Landing Target rather than the only branch devflow may land onto.
_Avoid_: Base branch, development branch, mandatory landing branch

**Landing Target**:
The existing local branch explicitly chosen to receive an approved Review Snapshot. It may use any project convention except the reserved `wip/*` and `review/*` roles.
_Avoid_: Destination Branch, inferred target, managed target

**Landing Title**:
The complete-feature commit subject the agent derives from the feature name and the WIP changes, following project commit rules.
_Avoid_: Last WIP subject, user-supplied boilerplate, generated prefix

**Landing Candidate**:
The prospective result of applying an approved Review Snapshot to its Landing Target as one feature change.
_Avoid_: Merge result, squash branch, release candidate

**Squash Landing**:
The single-commit integration of one exact reviewed and approved local feature from its Review Branch into an explicit Landing Target. It leaves WIP and review intact; publishing, cleanup, and onward delivery remain in the Project Workflow.
_Avoid_: Merge commit, partial landing, direct mainline commit

**Workflow Exception**:
Any coding-agent branch or worktree action that is neither part of the common devflow contract nor authorized by direct user or project instructions. It requires explicit user approval before execution and never classifies the user's own Git or LazyGit actions.
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
