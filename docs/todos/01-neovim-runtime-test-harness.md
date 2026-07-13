# Deepen the Neovim Runtime Test Harness

## Outcome

Provide a reusable Neovim runtime test harness with a small interface so runtime-facing tests can express scenarios and observations without constructing or mutating a fake `vim` implementation directly. Preserve the behavior currently protected by the terminal-tool regression and real-PTY suites.

## Context / current state

The terminal-tool module is a deep production module, but its test runtime is embedded in [`terminal_tool_spec.lua`](../../nvim/tests/terminal_tool_spec.lua). The spec currently owns a large fake covering jobs, buffers, windows, mappings, autocommands, environment variables, notifications, deferred callbacks, and terminal input. Individual checks reach into the fake's mutable tables to resize windows, change directories, inspect job attempts, and simulate process lifecycle events.

[`terminal_tool.lua`](../../nvim/lua/custom/lib/terminal_tool.lua) is the primary production consumer under test. The production Hunk declaration also has a separate real-PTY regression in [`terminal_tool_hunk_render.exp`](../../nvim/tests/terminal_tool_hunk_render.exp) and [`terminal_tool_hunk_render_init.lua`](../../nvim/tests/terminal_tool_hunk_render_init.lua), but that suite does not cross the same harness interface as the headless fake tests.

The motivating architecture review describes a reusable seam serving terminal-tool, package-build, and keymap tests, with fake and real Neovim behavior treated as adapters. See the [Neovim runtime harness candidate](../architecture-review-20260711-164013.html#nvim-runtime-harness).

## Scope

- Characterize the behaviors and observations the current terminal-tool regression suite relies on before moving code.
- Introduce a reusable test-harness module with a deliberately small scenario/observation interface.
- Move fake Neovim behavior out of the terminal-tool spec and behind that interface.
- Rewrite the existing terminal-tool checks to use the harness interface instead of raw runtime tables.
- Isolate global `vim`, module cache, job lifecycle, and deferred-callback state between checks.
- Add focused coverage for the harness contract where doing so protects fixture fidelity.
- Demonstrate that the seam is reusable through at least one representative additional runtime test or adapter, chosen based on current repo needs.
- Keep the real-PTY regression working and decide whether it should share any interface or assertions with the new harness.
- Update [`nvim/AGENTS.md`](../../nvim/AGENTS.md) if test locations, commands, or architectural guidance change.

## Boundaries / non-goals

- Do not change terminal-tool product behavior merely to simplify its tests.
- Do not introduce a general-purpose mocking framework or a second test framework unless current evidence makes it necessary.
- Do not weaken or delete race, failure-recovery, resize, tab-movement, environment, or Editor Handoff coverage.
- Do not replace the real Hunk PTY suite with fake-only coverage.
- Do not add speculative fake APIs for production modules that are not yet tested through the harness.
- Treat bugs discovered during extraction as separate product changes unless a minimal correction is required to preserve an already-documented invariant.

## Open decisions

- What is the smallest interface that covers setup, user actions, external events, time/deferred work, and observations without exposing fake internals?
- Which second consumer best proves the seam is real: package-build behavior, keymap declarations, a production plugin declaration, or a real-headless adapter?
- How much behavior can genuinely be shared between deterministic fake execution and a real Neovim process?
- Should real-PTY assertions reuse harness-level observations, or remain a separate end-to-end layer?
- What ownership model prevents `_G.vim` and `package.loaded` state from leaking when a check fails?
- Which behaviors belong to the harness contract versus terminal-tool-specific test helpers?

## Acceptance criteria

- [`terminal_tool_spec.lua`](../../nvim/tests/terminal_tool_spec.lua) no longer defines the fake Neovim runtime inline.
- Terminal-tool checks do not mutate raw fake runtime tables or depend on their storage layout.
- The harness interface covers all currently protected scenarios, including startup failure, synchronous exit, stale generations, delayed acknowledgement, working-directory replacement, resize, tab movement, environment protection, and production declarations.
- Harness state is isolated so checks remain order-independent and restore the real global runtime after failures.
- At least one additional representative test or adapter crosses the harness seam, demonstrating leverage beyond a file move.
- The existing real-PTY Hunk checks remain green.
- No production terminal-tool behavior or public declaration interface changes unless separately justified and documented.
- Relevant Neovim test documentation names the new module, its intended interface, and the supported verification commands.

## Verification

Run the narrow headless regression repeatedly, including in a different check order if the chosen test runner makes that practical:

```sh
nvim --clean --headless -l nvim/tests/terminal_tool_spec.lua
```

Run any new harness contract and second-consumer specs directly. Then run the real integration regression:

```sh
/usr/bin/expect nvim/tests/terminal_tool_hunk_render.exp
```

Also start the production configuration headlessly to catch runtime-path and module-loading errors. Before changing code, verify the current Neovim runtime, `nvim-lspconfig`/plugin-loading conventions where relevant, and any other upstream APIs the harness will emulate; do not rely on remembered API behavior.

## Starting points / references

- [`nvim/tests/terminal_tool_spec.lua`](../../nvim/tests/terminal_tool_spec.lua) — current fake runtime, scenario helpers, and protected behaviors.
- [`nvim/lua/custom/lib/terminal_tool.lua`](../../nvim/lua/custom/lib/terminal_tool.lua) — production interface and runtime calls the fake models.
- [`nvim/tests/terminal_tool_hunk_render.exp`](../../nvim/tests/terminal_tool_hunk_render.exp) — real-PTY behavior and external dependency checks.
- [`nvim/tests/terminal_tool_hunk_render_init.lua`](../../nvim/tests/terminal_tool_hunk_render_init.lua) — production declaration loaded by the PTY suite.
- [`nvim/lua/custom/lib/pack.lua`](../../nvim/lua/custom/lib/pack.lua) — possible second consumer, subject to the open decision above.
- [`nvim/AGENTS.md`](../../nvim/AGENTS.md) — Neovim architecture, test commands, and configuration philosophy.
- [Architecture review: Neovim runtime harness](../architecture-review-20260711-164013.html#nvim-runtime-harness).
