# Add OCaml and OxCaml Language Tooling

## Outcome

Provide reliable OCaml and OxCaml editing in Neovim—LSP features, formatting, and syntax parsing—using the toolchain selected for the project. Ensure an upstream OCaml project uses its compatible OCaml tools and an OxCaml project uses the OxCaml-aware tools from its active switch.

## Context / current state

The canonical language configuration in [`lua/custom/languages/config.lua`](../../nvim/lua/custom/languages/config.lua) currently enables neither `ocamllsp` nor `ocamlformat`, and its authoritative Treesitter parser whitelist does not include OCaml.

The configuration keeps enabled LSP configuration names and Mason-managed package names in independent tables. It can therefore enable `ocamllsp` without adding it to `mason_tools`, which matches current OCaml guidance to install `ocaml-lsp-server` in the active opam switch because the language server is compiler-version-sensitive. `ocamlformat` is similarly expected to match the project toolchain and can be configured without making Mason its installer. At the time this brief was written, `opam`, `ocamllsp`, `ocamlformat`, and `dune` were not available on the investigating workstation's `PATH`.

OxCaml is a fast-moving extension of OCaml, not a separate Neovim filetype. Its toolchain supplies modified OCaml tools, including `ocaml-lsp-server` and `ocamlformat`, through an OxCaml opam switch. The same Neovim language intent should therefore work with either toolchain while resolving binaries from the intended project environment.

## Scope

- Verify current upstream OCaml, OxCaml, `ocaml-lsp`, `nvim-lspconfig`, Conform, Treesitter, Mason, and opam guidance before choosing the integration.
- Add one coherent OCaml capability covering both upstream OCaml and OxCaml project environments.
- Enable the current `ocamllsp` configuration without allowing Mason to shadow an active switch's incompatible binary.
- Configure `ocamlformat` for the appropriate Neovim filetypes without making Mason the source of truth unless current upstream guidance has changed.
- Add the minimum useful OCaml Treesitter parser set, including interface files where supported.
- Preserve all existing language configuration declarations when adding the OCaml entries.
- Document required per-machine/project toolchain activation and how to confirm which binaries Neovim sees.
- Smoke-test both an upstream OCaml project and a project using OxCaml-only syntax.

## Boundaries / non-goals

- Do not introduce a separate OxCaml LSP server, filetype, or duplicated configuration unless current upstream tooling requires it.
- Do not hardcode Homebrew, opam-switch, or user-specific absolute paths in the Neovim config or shell rc files.
- Do not make the dotfiles installer install opam, create switches, or compile an OxCaml toolchain.
- Do not add broad opam shell activation globally without deciding how projects select switches and how that interacts with the repo's per-machine activation contract.
- Do not add a dedicated OCaml plugin if native Neovim, `nvim-lspconfig`, Conform, and Treesitter provide the required capability.
- DAP, REPL/toplevel integration, Dune task runners, and OCaml-specific structural editing are outside this task unless separately requested.
- Do not silently accept an unverified configuration-only result as complete when neither toolchain has been exercised.

## Open decisions

- How should Neovim inherit or select the project opam switch: inherited shell environment, `opam exec`, project-local environment tooling, or another current upstream recommendation?
- Which formatter filetypes should be explicit given current Neovim detection for `.ml`, `.mli`, `.mll`, `.mly`, Reason, and Dune files?
- Which Treesitter parsers are the minimum supported set: `ocaml` and `ocaml_interface`, or also Menhir/ocamllex parsers?
- Should Dune-file formatting be included, and if so, which current formatter owns it?
- What OCaml and OxCaml versions form the supported verification baseline?
- Does the currently locked `nvim-lspconfig` version already provide all needed `ocamllsp` filetypes, root markers, language IDs, and implementation/interface commands?

## Acceptance criteria

- Opening an OCaml implementation or interface file in an upstream OCaml project attaches a compatible `ocamllsp` from the intended project toolchain.
- Opening a project containing OxCaml-only syntax attaches the OxCaml-aware `ocamllsp` and provides diagnostics/hover without parser-version errors caused by an upstream-only server.
- `ocamlformat` formats supported OCaml/OxCaml buffers using the intended project toolchain.
- Mason does not install or prepend an incompatible OCaml LSP/formatter that shadows the active switch.
- The language configuration enables `ocamllsp` and maps `ocamlformat` without adding either tool to `mason_tools`, while preserving all existing declarations.
- OCaml implementation and interface files receive working Treesitter highlighting with no startup errors.
- Toolchain prerequisites and switch-selection expectations are documented without machine-specific paths.
- A clean production Neovim startup remains green.

## Verification

For each of an upstream OCaml switch and an OxCaml switch, launch Neovim using the project environment recommended by the current upstream documentation and verify:

- `vim.fn.exepath('ocamllsp')` and `vim.fn.exepath('ocamlformat')` resolve inside the intended toolchain.
- `:checkhealth vim.lsp`/`:LspInfo` reports `ocamllsp` attached to `.ml` and `.mli` buffers.
- Hover, go-to-definition, diagnostics, and implementation/interface switching work where supported.
- `:ConformInfo` identifies `ocamlformat`, and formatting a deliberately unformatted file produces the expected result.
- `:InspectTree` shows an attached OCaml parser for implementation and interface files.
- An OxCaml-only construct is understood by the OxCaml LSP rather than rejected by an upstream-only binary.
- `:Mason` does not own or shadow the selected OCaml tools.

Run a clean production startup outside a project as well, confirming that absent optional OCaml binaries do not break users working in other languages.

Upstream behavior is especially time-sensitive here. Before changing code, re-read the current official documentation and current locked plugin sources; do not rely on the package names, switch commands, filetypes, or compatibility assumptions recorded in this brief if upstream has changed.

## Starting points / references

- [`nvim/lua/custom/languages/config.lua`](../../nvim/lua/custom/languages/config.lua) — current language configuration, including independent LSP configuration, Mason installation, and Treesitter parser declarations.
- [`nvim/lua/custom/languages/lsp.lua`](../../nvim/lua/custom/languages/lsp.lua) — `nvim-lspconfig`, Mason, and LSP enablement adapter.
- [`nvim/lua/custom/languages/format.lua`](../../nvim/lua/custom/languages/format.lua) — formatter adapter.
- [`nvim/AGENTS.md`](../../nvim/AGENTS.md) — current language-tooling workflow and platform/path constraints.
- [OCaml editor setup](https://ocaml.org/docs/set-up-editor) — official editor and Neovim guidance.
- [OCaml LSP](https://github.com/ocaml/ocaml-lsp) — server installation and compatibility details.
- [OxCaml overview](https://oxcaml.org/) and [OxCaml installation](https://oxcaml.org/get-oxcaml/) — official toolchain and switch guidance.
- [nvim-lspconfig `ocamllsp` config](https://github.com/neovim/nvim-lspconfig/blob/master/lsp/ocamllsp.lua) — current Neovim defaults; compare with the locked local source before implementation.
- [Conform `ocamlformat` adapter](https://github.com/stevearc/conform.nvim/blob/master/lua/conform/formatters/ocamlformat.lua) — current formatter invocation.
- [nvim-treesitter supported languages](https://github.com/nvim-treesitter/nvim-treesitter/blob/master/SUPPORTED_LANGUAGES.md) — current parser support and stability.
