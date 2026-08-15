# Unify Neovim language actions

## Outcome

Provide one documented, language-neutral interface for editing, selecting run
and test targets, and debugging across the primary language set. Language
plugins remain backends, not separate user-facing modes.

## Current state

The completed Rust cleanup removed Rust-only `<leader>r*` mappings and the
Rust-specific `K` override. Rustaceanvim's advanced actions remain available
as documented `:RustLsp` commands, and the common DAP controls are `F5`,
`F1`–`F3`, `<leader>b`, and `F7`.

This establishes the boundary but does not yet provide a common target
selection interface. Rust, Python, TypeScript, Java, Kotlin, and browser
debugging expose targets through different upstream capabilities. The shared
DAP core is intentionally language-neutral; language integrations register
their own setup only when needed.

## Scope

- Research and define a common run/test/debug target-selection interface.
- Document its availability and unavailable-action behavior consistently.
- Implement backend adapters incrementally without language-specific keymap
  namespaces or overrides of generic LSP interactions.
- Preserve existing common DAP controls and lazy loading.

## Boundaries / non-goals

- Do not reintroduce Rust-specific `<leader>r*` mappings or a Rust `K` override.
- Do not remove Rustaceanvim, CodeLLDB, or project-aware target discovery.
- Do not claim parity where an upstream adapter cannot support an action.
- Do not choose a final abstraction before evaluating the remaining language
  backends and their project-root requirements.

## Open decisions

- What common command or picker selects run, test, and debug targets?
- Should that interface be a small local module, DAP configuration selection,
  or an upstream facility shared by the supported adapters?
- How should unsupported actions be shown without misleading users?
- How does the interface obtain canonical project context without global CWD?

## Acceptance criteria

- One documented user-facing interface spans every supported language backend.
- Backends do not claim private leader-key namespaces or generic LSP mappings.
- Each supported action either works through the common interface or reports
  its upstream limitation clearly.
- The common controls remain lazy, and language-specific setup remains scoped
  to its buffers or project lifecycle.

## Starting points

- [`docs/lsp-dap-research.md`](../lsp-dap-research.md)
- [`nvim/lua/custom/languages/dap.lua`](../../nvim/lua/custom/languages/dap.lua)
- [`nvim/lua/custom/languages/adapters/rust.lua`](../../nvim/lua/custom/languages/adapters/rust.lua)
- [`nvim/AGENTS.md`](../../nvim/AGENTS.md)
