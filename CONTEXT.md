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
A dedicated Development Surface workspace owned by one terminal tool. Invoking the tool returns to its existing workspace rather than creating another; the workspace exists until the tool exits.
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

**Diffing Solution**:
The canonical renderer for changed code across Git-facing tools in the development environment.
_Avoid_: External diff, pager, renderer

**Git Transaction Surface**:
The place for choosing Git objects and changing Git state, including staging, committing, stash operations, branch navigation, and history inspection.
_Avoid_: Git UI, commit tool

**Editor Handoff**:
The transition from a supporting surface back into the host Neovim at the file and line being inspected. Terminal tools should use the same Editor Handoff mechanism instead of bespoke per-tool launch shims.
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
