# Unify Neovim language actions

## Outcome

Present one documented, language-neutral editing, run, test, and debugging interface across the primary language set. Language-specific plugins remain implementation details and must not establish their own privileged keymap vocabulary.

## Context / current state

The Rust LSP/DAP slice uses rustaceanvim because it provides Cargo-aware runnable, testable, debuggable, macro-expansion, and hover-action capabilities that generic LSP and nvim-dap do not model. The initial slice added Rust-only mappings: `<leader>rr`, `<leader>rt`, `<leader>rd`, `<leader>rm`, and a Rust override of `K`.

The desired code interface is common across Rust, Python, TypeScript, Java, Kotlin, and future supported languages. Existing generic debugger controls—`F5`, `F1`–`F3`, `<leader>b`, and `F7`—are the starting shared DAP surface. Standard Neovim LSP interactions should also remain language-neutral. The Rust mappings are therefore provisional and should be removed after approval rather than becoming a precedent for every language.

The LSP/DAP investigation records the broader cross-project and language-adapter work in [`docs/lsp-dap-research.md`](../lsp-dap-research.md).

## Scope

- Define and document the common user-facing interface before adding language-specific bindings for further language slices.
- Remove the Rust-only `<leader>r*` mappings and the Rust-specific `K` override.
- Retain Rustaceanvim's advanced capabilities, with concise comments documenting the corresponding `:RustLsp` commands for manual discovery while a universal target-selection interface is designed.
- Update Neovim architecture and keybinding documentation to distinguish the common interface from backend-specific integrations.
- Add or update tests that prevent language plugins from silently claiming special keymap namespaces.

## Boundaries / non-goals

- Do not remove rustaceanvim, CodeLLDB, or Cargo-aware Rust target discovery.
- Do not invent a final universal run/test abstraction without first validating the requirements for Python, TypeScript, Java, Kotlin, and browser debugging.
- Do not make normal editing depend on DAP or load DAP at startup.
- Do not change existing generic debugger bindings without an explicit approved interface decision.

## Open decisions

- Which common commands or keymaps should eventually select run, test, and debug targets across every supported language?
- Should the eventual target picker be a small local Neovim module, standard DAP configuration selection, or an upstream mechanism that works across the required adapters?
- How should languages without a native test/runnable protocol advertise unavailable actions without making the interface misleading?

## Acceptance criteria

- Documentation describes one common editing and debugging interface, with language integrations explicitly treated as backends.
- No Rust-only `<leader>r*` mappings or Rust-specific `K` override remain.
- Rust's advanced actions remain discoverable through documented, commented `:RustLsp` commands without adding a second interactive keymap surface.
- Generic DAP controls retain their current behavior and remain lazy outside language attachment requirements.
- Tests cover the removal and guard the shared keymap boundary.

## Verification

1. Run the focused Rust and language-inventory tests.
2. Inspect normal-mode buffer-local mappings in a Rust buffer and confirm no Rust-only leader namespace or `K` override remains.
3. Confirm the common DAP controls still initialize and control the shared nvim-dap session.
4. Confirm Rust runnables, testables, debuggables, macro expansion, and hover actions remain available through their `:RustLsp` commands.

## Starting points / references

- [`nvim/lua/kickstart/plugins/rust.lua`](../../nvim/lua/kickstart/plugins/rust.lua) — current Rust integration and provisional mappings.
- [`nvim/lua/kickstart/plugins/debug.lua`](../../nvim/lua/kickstart/plugins/debug.lua) and [`nvim/lua/custom/lib/dap.lua`](../../nvim/lua/custom/lib/dap.lua) — shared DAP surface and lifecycle.
- [`nvim/AGENTS.md`](../../nvim/AGENTS.md) — current keybinding and architecture documentation.
- [`docs/lsp-dap-research.md`](../lsp-dap-research.md) — language capability and adapter evidence.
