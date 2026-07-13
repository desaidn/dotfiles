# Improve the Language Tooling Directory Structure

## Outcome

Make the Language Tooling Inventory and its internal implementation easy to locate and understand as one coherent module, while preserving the existing small production interface and all projected language-tooling behavior.

## Context / current state

The public production inventory lives in [`lua/custom/language_tooling.lua`](../../nvim/lua/custom/language_tooling.lua). It declares Language Families and returns the projections created by a second, same-named module at [`lua/custom/lib/language_tooling.lua`](../../nvim/lua/custom/lib/language_tooling.lua). The second file owns validation, immutable copying, and the LSP, Mason, formatter, and linter projections.

Production plugin adapters consistently require `custom.language_tooling`:

- [`lsp.lua`](../../nvim/lua/kickstart/plugins/lsp.lua)
- [`conform.lua`](../../nvim/lua/kickstart/plugins/conform.lua)
- [`lint.lua`](../../nvim/lua/kickstart/plugins/lint.lua)

The split preserves a small interface, but the two files' identical basenames and distant locations obscure that the factory is an internal seam of the Language Tooling module. [`language_tooling_spec.lua`](../../nvim/tests/language_tooling_spec.lua) exercises both the internal factory and the production inventory.

## Scope

- Choose a directory/module layout that colocates the production inventory and its internal validation/projection implementation.
- Preserve `require 'custom.language_tooling'` as the production-facing interface unless current evidence shows a compelling reason to change it.
- Move or rename the existing files without changing inventory semantics.
- Update internal test imports and all documentation paths.
- Keep the internal factory testable without exposing additional production-facing concepts.
- Ensure the layout follows current Neovim/Lua runtime-path conventions and the repo's `custom` versus `kickstart` ownership model.

One likely direction is a `custom/language_tooling/` module directory containing the public entry point and its private implementation, but the implementing agent should choose names only after checking current code and module-loading behavior.

## Boundaries / non-goals

- Do not add, remove, or change Language Families as part of this move.
- Do not change the Language Tooling declaration schema, validation rules, projection ordering, deduplication, or formatter fallback semantics.
- Do not split each Language Family into its own automatically loaded file without separate evidence that the extra interface and loader are worth the complexity.
- Do not move plugin setup, event wiring, or invocation behavior into the inventory.
- Keep the Treesitter parser list separate; its current package-build ownership is documented in [`nvim/AGENTS.md`](../../nvim/AGENTS.md).
- Avoid compatibility shims that leave two permanent ways to import the same internal module.

## Open decisions

- What names most clearly distinguish the public inventory/facade from its internal factory or model?
- Should tests continue importing the internal factory directly, or should a narrower test-only/internal entry point express that seam more clearly?
- Can the current production module move to a directory entry point with no consumer changes under the repo's actual `package.path`?
- Are there generated docs, Lua language-server annotations, or external local scripts that refer to the old paths but are not found by a simple repository search?

## Acceptance criteria

- The production inventory and its internal implementation are colocated under a clear Language Tooling module structure.
- `require 'custom.language_tooling'` continues to return the same four projections used by the plugin adapters.
- LSP server order, Mason tool order/deduplication, formatter maps, linter maps, and validation errors remain behaviorally unchanged.
- There is only one supported import path for the production interface and one intentional internal seam for factory tests.
- All old repository path references are removed from tests and documentation.
- The three production plugin adapters remain thin and require no behavioral changes.
- [`language_tooling_spec.lua`](../../nvim/tests/language_tooling_spec.lua) passes unchanged in intent, including the exact production inventory regression.

## Verification

Search for both old module names and paths before and after the move, then run:

```sh
nvim --clean --headless -l nvim/tests/language_tooling_spec.lua
```

Start the production configuration headlessly to verify real runtime-path resolution, and load each of the three plugin adapters through the normal configuration startup. If formatting tools are available, run the repository's Lua formatter/checks over moved files.

Before changing code, verify current Neovim Lua module-loading and runtime-path documentation rather than assuming `?.lua`/`?/init.lua` resolution from memory. Re-read the current repository files because this brief may outlive the layout it describes.

## Starting points / references

- [`nvim/lua/custom/language_tooling.lua`](../../nvim/lua/custom/language_tooling.lua) — production Language Tooling Inventory and facade.
- [`nvim/lua/custom/lib/language_tooling.lua`](../../nvim/lua/custom/lib/language_tooling.lua) — validation and projection implementation.
- [`nvim/tests/language_tooling_spec.lua`](../../nvim/tests/language_tooling_spec.lua) — internal interface and production-inventory coverage.
- [`nvim/lua/kickstart/plugins/lsp.lua`](../../nvim/lua/kickstart/plugins/lsp.lua) — LSP and Mason adapter.
- [`nvim/lua/kickstart/plugins/conform.lua`](../../nvim/lua/kickstart/plugins/conform.lua) — formatter adapter.
- [`nvim/lua/kickstart/plugins/lint.lua`](../../nvim/lua/kickstart/plugins/lint.lua) — linter adapter.
- [`nvim/AGENTS.md`](../../nvim/AGENTS.md) and [`nvim/README.md`](../../nvim/README.md) — documented module paths and language workflow.
