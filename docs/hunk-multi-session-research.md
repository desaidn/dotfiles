# Multiple Hunk sessions in one Neovim instance

**Research date:** 2026-08-13

**Local baseline:** Hunk 0.17.0; Neovim integration on branch `main`

**Latest upstream release checked:** Hunk 0.18.1 (2026-08-11)

**Status:** Implemented on `codex/hunk-multi-session-research`

## Conclusion

One Neovim instance can manage multiple concurrent Hunk sessions. Hunk already
supports this upstream: every TUI process gets its own session UUID and the
shared local broker stores multiple sessions at once. Neovim can likewise host
separate terminal jobs in separate terminal buffers and tabpages. The current
limit on `main` was entirely in this repository's launcher: it allocated one
mutable state record for the single registered `hunk` tool and replaced that
process whenever the Host Window's working directory changed.

The recommended first implementation is **one persistent Hunk Tool Tab per
normalized Host Window working directory**, all inside the existing Neovim
process. Keep singleton behavior as the default for other terminal tools. Give
each Hunk instance its own opaque local identity, terminal job, buffer, tabpage,
working directory, and handoff generation. `<leader>gd` should select or create
the Hunk instance for the current Host Window rather than restarting a global
Hunk instance.

Preserve the repository's current **global latest Host Window** behavior in the
first implementation. Pinning each Hunk Tool Tab to its originating Host Window
is a coherent alternative, but it contradicts the current domain definition
and Tool Tab ADR. Treat that as a separate UX decision, not an incidental part
of adding session cardinality.

Do not make Hunk's session daemon the owner of Neovim tabs. It is the right
control plane for agents, but Neovim already has authoritative job, buffer,
window, and tab handles. Polling the daemon would add a second lifecycle model
without solving tab focus or Editor Handoff.

An explicit “new Hunk session” action and picker should be added only if the
actual requirement includes **multiple simultaneous reviews for the same
working directory/repository**. That case is supported by Hunk, but agents can
no longer safely use `hunk session ... --repo`; they must select an exact Hunk
session ID.

Before multiplying persistent `--watch` processes, upgrade the local Hunk
binary from 0.17.0 to at least 0.18.1. The 0.18 release replaced the legacy
250 ms Git-backed watch loop with filesystem event hints, an authoritative Git
signature, and a 10-second safety check. Hunk's frozen cross-platform campaign
measured 35–36 times fewer Git invocations and 1.8–6.4 times less idle
main-process CPU per session, with the platform and projection caveats stated
in the report. This is an operational prerequisite, not a change to the
launcher Interface: the production command remains `hunk diff --watch`.
See the [v0.18.1 release](https://github.com/modem-dev/hunk/releases/tag/v0.18.1),
the immutable
[watch benchmark](https://github.com/modem-dev/hunk/blob/d6e967bf5c5a3a93bb7796aa50e67ee3fec58179/docs/watch-benchmark-final.md#L9-L28),
and the
[v0.18.1 watch contract](https://github.com/modem-dev/hunk/blob/d6e967bf5c5a3a93bb7796aa50e67ee3fec58179/README.md#L60-L83).

The implementation raises the repository's validated Hunk floor to 0.18.1 but
does not change the installer's deliberate `--no-upgrade` policy. A machine
that already has 0.17 must upgrade Hunk explicitly before activating this
branch; installer validation fails before linking configuration until it does.
The real-PTY regression remains compatible with 0.17 so the launcher behavior
can be tested on the research machine, but that compatibility is not the
supported operational floor for concurrent watch sessions.

## Scope and terminology

Three identities must remain separate:

1. A **tool declaration** is the stable local configuration for Hunk: command,
   key, environment, description, and handoff policy.
2. A **tool instance** is Neovim-owned runtime state: one job, terminal buffer,
   Tool Tab, working directory, opaque token, and generation.
3. A **Hunk session** is Hunk-owned runtime state: one TUI process registered
   with Hunk's daemon under a UUID.

On the research baseline these were collapsed into one `tool.state` table. The
implementation replaces that state with a one-to-many relationship from the
Hunk declaration to tool instances. Neovim does not adopt Hunk's UUID as its
own identity.

The primary use case assumed by the recommendation is concurrent work across
repositories or worktrees. Concurrent diff targets in one repository are
treated separately below because their selection semantics are materially
different.

## Verified facts

### Hunk is already a multi-session application

- A live Hunk TUI creates a registration containing a random UUID, its process
  ID, current working directory, repository root, launch time, and review
  metadata. Reloading a live review updates its metadata while deliberately
  preserving that identity. See Hunk 0.17.0's
  [`createSessionRegistration` and `updateSessionRegistration`](https://github.com/modem-dev/hunk/blob/f809983781b7eac9edf676600cfe3033430cfa11/src/hunk-session/sessionRegistration.ts#L54-L90).
- The broker holds sessions in a map keyed by session ID and records the socket
  that owns each one. Registration inserts or replaces only that UUID; it does
  not impose a one-session-per-repository rule. See
  [`SessionBrokerState`](https://github.com/modem-dev/hunk/blob/f809983781b7eac9edf676600cfe3033430cfa11/packages/session-broker-core/src/brokerState.ts#L138-L169)
  and its
  [registration path](https://github.com/modem-dev/hunk/blob/f809983781b7eac9edf676600cfe3033430cfa11/packages/session-broker-core/src/brokerState.ts#L199-L241).
- Multiple live sessions may share a repository. Hunk's official skill says to
  use an exact `<session-id>` in that case; `--repo` is intended for the common
  unambiguous case. See
  [Hunk's session-selection guidance](https://github.com/modem-dev/hunk/blob/f809983781b7eac9edf676600cfe3033430cfa11/skills/hunk-review/SKILL.md#L26-L39).
- The broker rejects an ambiguous repository or session-path selector and tells
  the caller to use a session ID. Its official test constructs two sessions
  with the same `repoRoot` and verifies that behavior. See
  [`resolveSessionTarget`](https://github.com/modem-dev/hunk/blob/f809983781b7eac9edf676600cfe3033430cfa11/packages/session-broker-core/src/brokerState.ts#L69-L136)
  and the
  [two-session test](https://github.com/modem-dev/hunk/blob/f809983781b7eac9edf676600cfe3033430cfa11/packages/session-broker-core/src/brokerState.test.ts#L195-L219).
- `hunk session list` exposes enough metadata for a human or agent to distinguish
  sessions: UUID, PID, working directory, repository root, terminal metadata,
  input kind, title, source label, files, and current snapshot. See
  [`buildListedHunkSession`](https://github.com/modem-dev/hunk/blob/f809983781b7eac9edf676600cfe3033430cfa11/src/hunk-session/projections.ts#L66-L81).
- `hunk session reload` changes the contents of an existing live session rather
  than creating a concurrent review. Hunk documents exact-ID, repository, and
  session-path targeting for reloads. See the
  [official reload workflow](https://github.com/modem-dev/hunk/blob/f809983781b7eac9edf676600cfe3033430cfa11/skills/hunk-review/SKILL.md#L77-L94).

### Neovim supplies the required primitives

- `jobstart(..., { term = true })` starts a process in a new pseudo-terminal
  attached to the current buffer and returns its own job/channel ID. Its options
  include `cwd`, `env`, and `on_exit`, which are the exact lifecycle inputs the
  local launcher already uses. See Neovim's
  [`jobstart()` documentation](https://neovim.io/doc/user/vimfn/#jobstart()).
- Neovim terminal buffers are ordinary buffers with terminal-specific behavior,
  and `jobstart(..., { term = true })` is an officially supported way to create
  one. Their default hidden-buffer behavior permits a process to remain alive
  when its window is no longer displayed. See
  [`:help terminal-start`](https://neovim.io/doc/user/terminal/#terminal-start).
- A tabpage has a stable tab ID and owns one or more windows; switching tabpages
  is Neovim's native way to move among independent window collections. See
  [`:help tabpage-intro`](https://neovim.io/doc/user/tabpage/#tabpage-intro).

**Inference from these facts:** neither Hunk nor Neovim requires a separate
Neovim process per Hunk process. Starting one PTY job and retaining one set of
Neovim handles per instance is sufficient.

### The current repository is singleton at the launcher layer

- [`hunk.lua`](../nvim/lua/custom/plugins/hunk.lua) registers one declaration
  with `id = "hunk"`, one command, and one mapping.
- [`terminal_tool.lua`](../nvim/lua/custom/lib/terminal_tool.lua#L369) creates
  exactly one state table per declaration. Duplicate tool IDs and duplicate
  mappings are rejected during configuration
  ([lines 316-357](../nvim/lua/custom/lib/terminal_tool.lua#L316)).
- That state table has one generation, buffer, window, tab, job, and working
  directory ([lines 369-385](../nvim/lua/custom/lib/terminal_tool.lua#L369)).
  When the Host Window's working directory differs, the toggle stops that job
  and reuses the tab for a replacement
  ([lines 259-287](../nvim/lua/custom/lib/terminal_tool.lua#L259)). This is the
  specific behavior that prevents concurrent per-directory Hunk sessions.
- The launcher has one module-global `host_win`
  ([lines 12-14](../nvim/lua/custom/lib/terminal_tool.lua#L12)). That is a
  deliberate domain rule: Tool Tabs return to the latest non-tool Host Window.
  It need not change merely to add instances. Editor Handoff, however,
  identifies only tool ID plus process generation
  ([lines 303-309](../nvim/lua/custom/lib/terminal_tool.lua#L303)); it needs an
  opaque instance token so two live generations under one declaration cannot
  be confused.
- The existing tests prove that two *different declarations*—Hunk and
  LazyGit—can coexist. They do not model two instances of one declaration. See
  the current
  [Tool Tab coexistence test](../nvim/tests/terminal_tool_spec.lua#L390).

### Local runtime check

On 2026-08-13, with the installed Hunk 0.17.0, an isolated local daemon was
started on `HUNK_MCP_PORT=48657` and two simultaneous
`hunk diff --watch --mode stack` PTYs were launched from the same temporary Git
repository.

- `hunk session list --json` returned two entries with distinct UUID session
  IDs and PIDs but identical `cwd` and `repoRoot` values.
- `hunk session get --repo . --json` exited nonzero with “Multiple active
  sessions match ...; specify sessionId instead”.
- Selecting either exact ID succeeded.
- Both TUIs were exited through Hunk's `q` action, after which the isolated
  daemon's session list was empty.

This confirms both the upstream concurrency model and its selector ambiguity
behavior in the installed binary. The temporary processes and repository were
cleaned up and the check did not alter this repository.

## Design alternatives and recommendation

| Option | What it changes | Strengths | Problems | Verdict |
| --- | --- | --- | --- | --- |
| Fixed Hunk slots | Register `hunk-1`, `hunk-2`, etc. as separate existing tool declarations | Small proof of concept; current handoff ID/generation isolation would work | Arbitrary ceiling, multiple mappings, slot bookkeeping, poor relationship to repository context | Useful only as a throwaway prototype |
| Manual `:terminal hunk ...` tabs | Let the user start arbitrary terminal buffers | No launcher refactor | Bypasses Tool Tab lifecycle, source-aware Editor Handoff, consistent environment, cleanup, and tests | Reject |
| Hunk daemon as Neovim manager | Poll `hunk session list`, then try to map daemon sessions back to tabs | Reuses Hunk's UUID and metadata | The documented session surface controls review contents, navigation, and comments—not Neovim tab focus—and Neovim remains the owner of all local handles. Creates two lifecycle authorities | Reject as the primary design |
| Dynamic local instance registry | One declaration owns multiple Neovim runtime instances | Natural Tool Tabs, one mapping, no new dependency, keeps Hunk and Neovim responsibilities separate | Requires a careful launcher refactor and broader tests | **Recommend** |

The daemon remains valuable for the Agent Review Loop. The recommendation is
only that it should not become the Neovim UI registry.

### Interface designs considered

The dynamic-registry option was designed three ways to test the Seam rather
than accepting the first Interface that worked:

1. **Minimal cardinality policy:** keep `terminal_tool.create` declarative and
   add only `instances = "cwd"`, defaulting to `"singleton"`. `create` still
   returns nothing. This has the greatest Depth and preserves Locality: callers
   state cardinality while the Module hides selection, lifecycle, recovery, and
   Editor Handoff.
2. **Extensible launcher:** return an opaque controller with
   `activate { target = "context"|"new"|"select" }` and accept a context
   resolver callback. This can model same-context duplicates and a picker, but
   it makes every caller learn capabilities that the current workflow has not
   demonstrated a need for. Its flexibility reduces present-day Leverage.
3. **Worktree-aware launcher:** expose a zero-argument `open()` that discovers
   the current buffer's repository/worktree root and owns one Review Surface
   per root. This is attractive for the common Git workflow, but the generic
   Module would either acquire Git-specific policy or need a new Hunk Adapter
   for Git, Jujutsu, Sapling, non-file buffers, and root-resolution failures.

The first Interface is the recommendation. It preserves the existing Seam at
the tool declaration and changes only cardinality. If real usage shows that
sibling window-local directories routinely create duplicate Hunk processes,
add a Hunk-specific context Adapter later; do not make the generic Module infer
VCS semantics preemptively. Likewise, add `new` and `select` only with the
same-context-duplicate capability.

## Recommended design

### 1. Make cardinality a declaration policy

Preserve the existing `terminal_tool.create { ... }` declaration boundary and
add one optional policy describing how runtime instances are keyed. Conceptual
shape:

```lua
require('custom.lib.terminal_tool').create {
  id = 'hunk',
  command = { 'hunk', 'diff', '--watch', '--mode', 'stack' },
  key = '<leader>gd',
  desc = 'Hunk diff',
  env = { OPENTUI_GRAPHICS = 'false' },
  instances = 'cwd',
}
```

The contract is:

- absent policy means `singleton`, preserving LazyGit and every existing caller;
- `cwd` means one instance per canonicalized effective working directory
  (`fs_realpath` when available, normalized path as fallback);
- the declaration remains immutable and does not receive mutable Neovim handles.

This keeps the shared launcher deep: declarations state policy, while the
module owns mappings, selection, jobs, buffers, tabs, handoff, recovery, and
cleanup.

### 2. Store runtime state per opaque instance

A suitable internal model is:

```text
tool declaration
  spec
  instances_by_key
    normalized cwd -> instance

instance
  opaque token
  generation
  cwd
  buffer
  window
  tabpage
  job
```

The opaque token and generation should both travel through the existing
flatten.nvim guest-data path. A stale handoff must match neither a replacement
generation of the same instance nor another Hunk instance.

Do not use a tab number or list position as identity: Neovim documents tab
numbers as mutable while tab IDs remain stable
([`:help tab-ID`](https://neovim.io/doc/user/tabpage/#tab-ID)). The manager
should continue to retain actual Neovim handles and validate them before use.

### 3. Make the ordinary toggle contextual

Recommended `<leader>gd` behavior:

1. From a non-tool Host Window, retain it as the global latest Host Window and
   resolve its normalized effective working directory.
2. If a live Hunk instance already owns that key, focus its Tool Tab without
   restarting the process.
3. Otherwise, create a terminal buffer, Tool Tab, and Hunk job for that key.
4. From a Hunk Tool Tab, return to the latest non-tool Host Window, preserving
   today's Tool Tab behavior.
5. From another tool's Tool Tab, continue to derive context from the latest
   non-tool Host Window, matching today's tool-to-tool behavior.

This changes the current cwd transition from “stop and replace the global Hunk”
to “select or create the Hunk belonging to this context.” Existing instances
continue watching their own worktrees.

### 4. Preserve the Host Window contract unless the UX decision changes

[`CONTEXT.md`](../CONTEXT.md) defines the Host Window as the most recently used
non-tool window, and [ADR 0005](adr/0005-use-tool-tabs-for-persistent-terminal-tools.md)
records direct return to that latest window. Moving between Tool Tabs
deliberately does not change it. Multiple Hunk instances do not technically
require a second Host Window model: every `e` Editor Handoff can continue to
open its absolute file in the global latest Host Window.

There is a plausible alternative: Hunk A could always return and hand off to
the window from which A was last selected, while Hunk B does the same for B.
That would prevent a handoff from changing the buffer in a Host Window whose
working directory belongs to another review context. It would also change the
established meaning of Host Window and contradict ADR 0005. If that behavior is
desired, update the domain language and ADR explicitly and then store one Host
Window per instance. Do not smuggle the change into the registry refactor.

In either design, the shell-owned `EDITOR`, `VISUAL`, and `GIT_EDITOR` contract
and the flatten.nvim Adapter remain unchanged at their public Seam. The opaque
handoff data gains instance identity so the Module validates the exact live
source before routing it.

### 5. Keep hiding and process exit distinct

Preserve today's semantics for every instance:

- native `:tabclose` hides the Tool Tab but retains its live terminal buffer and
  job;
- invoking Hunk for that context recreates the tab around the same buffer;
- quitting Hunk ends that one process, deletes that one buffer, and removes
  only that instance from the registry.

If a picker is added later, it must include hidden live instances; otherwise a
user can create processes that remain alive but are no longer discoverable.

### 6. Do not couple the first version to Hunk's daemon

Neovim already knows every job, buffer, tab, and cwd it created, plus the latest
Host Window. That is sufficient for launching, focusing, hiding, handoff, and
cleanup.

Hunk's UUID remains the public identity for `hunk session` commands. Agents
should keep using the official selection rules:

- one session for a repository: `--repo <path>`;
- more than one session for that repository: run `hunk session list`, then pass
  the exact `<session-id>`.

The official workflow explicitly recommends repository selection for normal
worktrees and exact IDs for same-repository duplicates
([session targeting](https://github.com/modem-dev/hunk/blob/f809983781b7eac9edf676600cfe3033430cfa11/docs/agent-workflows.md#L116-L129)).

## Same-repository duplicates are a second capability

One instance per working directory solves parallel repositories and worktrees.
It does not create two simultaneous reviews rooted at the same directory, such
as a working-tree review beside `show HEAD~1`.

If that is required, add two explicit operations rather than changing the
ordinary toggle:

- **New session for current context:** always launch another Hunk instance with
  a fresh opaque local token.
- **Select session:** use a native `vim.ui.select` picker showing command/input,
  cwd or repository label, visible/hidden state, and launch order.

The registry then becomes `context key -> ordered set of instances`, with one
preferred instance for the ordinary toggle. This is also the point at which
documentation for the Agent Review Loop must foreground exact Hunk session IDs,
because `--repo` will intentionally be ambiguous.

Do not add same-repository duplicates accidentally by keying only on raw
subdirectory paths. Hunk's `--repo` selector is resolved to the containing VCS
root before matching, so two Hunk processes started from different
subdirectories can still share one registered repository root. See Hunk's
[`resolveRepoSelectorRoot`](https://github.com/modem-dev/hunk/blob/f809983781b7eac9edf676600cfe3033430cfa11/src/core/cli.ts#L313-L344).

This creates one remaining product decision:

- If Neovim is consistently rooted at each repository/worktree, normalized cwd
  is the smallest implementation and preserves the launcher's current restart
  boundary.
- If users routinely use window-local directories below a repository root, a
  future Hunk-specific context resolver should coalesce them to the VCS root.
  That resolver belongs in the Hunk declaration/integration, not in the generic
  terminal-tool core, because Hunk supports Git, Jujutsu, and Sapling
  ([Hunk 0.17.0 README](https://github.com/modem-dev/hunk/blob/f809983781b7eac9edf676600cfe3033430cfa11/README.md#L71-L73)).

The current Neovim configuration does not automatically change a window's cwd
to match its buffer. Therefore the per-cwd design distinguishes contexts only
when the user or another established workflow actually gives Host Windows
different effective directories (for example with `:lcd` or `:tcd`). Inferring
the current buffer's repository would be the worktree-aware Interface above,
not a hidden property of `instances = "cwd"`.

## Implementation verification

Extend [`terminal_tool_spec.lua`](../nvim/tests/terminal_tool_spec.lua) with at
least these scenarios:

1. Invoking Hunk from cwd A and cwd B starts two jobs and retains two Tool Tabs.
2. Returning to cwd A selects its original job without restart.
3. Invoking the toggle from either Hunk tab returns to the global latest Host
   Window, preserving the current domain contract.
4. Editor Handoff from either session opens in the latest Host Window while
   validating the exact originating instance and generation.
5. A stale generation or instance token cannot route a handoff to another
   instance.
6. Closing A's tab hides only A; invoking A recreates its tab around the same
   buffer.
7. Exiting A removes only A while B continues running.
8. A failed start in B leaves A and the invoking Host Window intact.
9. Tool-to-tool navigation still derives cwd from the latest Host Window.
10. The default singleton declaration retains today's LazyGit behavior.

If per-instance Host Window ownership is chosen as the separate UX change, add
the inverse routing checks and update the domain documentation and ADR in the
same change.

Extend the real-PTY Hunk regression to launch two production Hunk declarations
or instances inside one Neovim process and verify that both complete first
frames render, both survive tab switches/resizes, and quitting one does not end
the other. If the test queries `hunk session list`, filter to the processes it
created; unrelated live sessions may share the user's daemon.

## Implemented delivery order

1. Refactor launcher state from `tool.state` to an instance registry without
   changing singleton behavior; keep all current tests green.
2. Add opaque instance identity to Editor Handoff while retaining the global
   latest Host Window contract.
3. Add the optional per-cwd policy and enable it only for Hunk.
4. Add multi-cwd headless tests and the two-session real-PTY regression.
5. Update the Tool Tab ADR, Neovim help, README, and `AGENTS.md` from “one Tool
   Tab per tool” to “one Tool Tab per tool instance,” documenting Hunk's
   per-context behavior.
6. Only after a demonstrated need, add explicit same-context creation and a
   native session picker.

## Final recommendation

The implementation uses a Neovim-owned dynamic instance registry, keyed by
normalized Host Window cwd for Hunk and defaulting to singleton for every other
tool. This is the smallest design that preserves active Hunk reviews across
repositories/worktrees, keeps the existing Tool Tab and Editor Handoff
architecture, and matches Hunk's verified multi-session model. Preserve the
global latest Host Window initially; decide and document per-instance Host
Window ownership separately if that UX is preferred.

Before adding explicit same-repository duplicates, confirm that the desired
workflow truly needs concurrent review inputs rather than Hunk's existing
in-place `session reload`. If it does, treat “new” and “select” as explicit UI
operations and require exact Hunk session IDs in agent-facing workflows.
