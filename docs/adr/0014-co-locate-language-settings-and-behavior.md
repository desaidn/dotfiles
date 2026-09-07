---
status: accepted
---

# Co-locate language settings and behavior

Language Tooling currently splits language-specific settings and behavior between a central inventory, shared tooling modules, and partially specialized adapters. Each Language Adapter under `nvim/lua/custom/languages/adapters/` will own its language's settings, tool declarations, project behavior, and integration logic, while shared modules apply common tooling behavior and consume the combined Language Tooling Inventory. This makes a language change local to its adapter, accepting inventory assembly and explicit lifecycle coordination instead of retaining a central settings file with separate language callbacks.

This placement decision includes language-specific policy currently outside the inventory, such as Ruff capability overlap and ESLint project-root selection. It retains ADR 0004's modular layout, native configuration shapes, and explicit loading; it changes the central-inventory placement described in the current Neovim guidance, which must be aligned when implementation occurs.

Mechanical changes to existing tests that are required by the production refactor are allowed, including activation calls and expectations tied to the adapter interface. Preserve behavioral coverage; the test-harness redesign remains excluded.

Every Language Adapter separates declaration from activation. Importing an adapter returns its native configuration tables and callbacks without loading plugins, registering commands or autocommands, or starting servers. The language bootstrap collects the declarations, initializes the shared tooling, and then calls each adapter's optional `setup()` explicitly; settings-only adapters need no setup function, and existing lazy debugger activation stays lazy.

Each Language Adapter explicitly declares every supporting tool and parser it needs, including dependencies also declared by another adapter. The inventory collector deduplicates package and parser names. Repeating those names keeps a language's requirements visible in its own file and prevents its dependencies from being supplied implicitly by another language; shared-tool presets, a separate shared package list, and inferred dependency mappings are not part of this design.

The collector rejects duplicate LSP server definitions and duplicate filetype mappings within the same configuration category, even when the definitions match. Its error names the conflicting entry and both owning adapters. Only package and parser names are deduplicated; configuration ownership must not depend on load order.

An adapter owns a coherent language family rather than an individual file extension. JavaScript, JSX, TypeScript, and TSX form one family, as do Bash/sh, JSON/JSONC, CSS/SCSS, and Markdown with its inline parser. Java, Kotlin, Python, and Rust remain separate families; sharing a machine runtime does not imply shared editor-tooling ownership.

A language family with an enabled LSP and/or DAP integration gets its own adapter file. Families without LSP/DAP share one grouped adapter, including parser-only support, editor/support formats, and Markdown's parsers and Prettier formatting. Keep each family's declarations together within that file, including the existing C/C++ format-on-save exclusions. This yields twelve standalone language files and one grouped file, superseding the earlier proposal to give every family its own file while retaining the agreed family boundaries and configuration ownership rules.

Standalone files therefore cover Bash, CSS/SCSS, Fish, HTML, Java, JavaScript/TypeScript, JSON/JSONC, Kotlin, Lua, Python, Rust, and YAML. The user chose this capability-based rule after considering limiting standalone files to six primary languages; supporting languages with an LSP are not grouped merely to reduce file count.

The user confirmed Haskell is unused. Remove its configured HLS integration, Mason package declaration, parser declaration, and the required `ghcup` provisioning and validation, aligning dependency documentation and installer expectations. Existing installed system toolchains are not automatically uninstalled.

One explicit, ordered list selects the enabled adapters and supplies both inventory collection and subsequent activation. Each selected adapter is loaded once, its declarations are collected and validated, and its optional `setup()` is called after shared tooling initialization. Adding a file does not enable it, and no separate activation list or automatic directory discovery is introduced.

JavaScript owns the complete existing ESLint integration, including root discovery, executable availability checks, lint events, debouncing, and read-only-buffer protection. Move that integration into the JavaScript adapter's activation and remove `languages/lint.lua`, preserving its current behavior. ESLint is the sole current `nvim-lint` consumer; common scheduling can be extracted if a second language actually needs it rather than introducing a new callback interface now.

As a companion simplification, retain Blink's native LSP-snippet expansion, placeholder navigation, and personal-snippet source while removing LuaSnip and friendly-snippets. Disable friendly-snippets catalog discovery explicitly, remove the LuaSnip preset and loader, and remove its package-build branch and both plugin declarations/lock entries. Personal snippet support uses the existing native engine and adds no replacement plugin; LuaSnip-specific advanced behavior and the bundled catalog are the accepted feature removals.

Documentation has explicit ownership: the root README covers installation, dependency inventory, quick start, and links to tool guides; tool READMEs cover usage, commands, keybindings, and troubleshooting; AGENTS files retain constraints, ownership, and required validation. The detailed agent workflow lives in `docs/agents/development-workflow.md`, ADRs explain decisions, and CONTEXT remains a glossary. Replace duplicate explanations with links without removing safety constraints, self-contained distributable devflow guidance, or useful Neovim instructional comments.

Implement the adapter refactor, native-snippet simplification, Haskell removal, and documentation consolidation as separate commits so each logical change can be reverted independently. Keep necessary behavioral-test and documentation adjustments with their corresponding change; do not redesign test harnesses, shell startup, plugin selection beyond the agreed removals, terminal tooling, or runtime version policy.
