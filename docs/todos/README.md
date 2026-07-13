# TODO briefs

These briefs turn the repository's working TODO list into self-contained starting points for coding agents. Each brief records the desired outcome, current evidence, boundaries, unresolved decisions, acceptance criteria, and verification path without locking the implementer into a particular patch.

## Using a brief

Point an agent at one brief and ask it to take ownership of that item. The agent should still:

1. Read the repository-level `AGENTS.md` and any scoped `AGENTS.md` named by the brief.
2. Inspect the current implementation rather than assuming the snapshot in the brief is still exact.
3. Check current upstream documentation before changing integrations with external tools.
4. Resolve or surface the brief's open decisions before committing to a design.
5. Implement and run the listed verification in proportion to the change.

## Index

- [Deepen the Neovim runtime test harness](01-neovim-runtime-test-harness.md)
- [Improve the Language Tooling directory structure](02-language-tooling-directory-structure.md)
- [Add OCaml and OxCaml](03-ocaml-and-oxcaml.md)
- [Add Pi integration](04-pi-integration.md)
- [Add a local model](05-local-model.md)
- [Add Hunk preferences](06-hunk-preferences.md)
- [Prevent lazygit and Hunk float stacking](07-terminal-tool-float-stacking.md)
- [Make web-language colors consistent across machines](08-cross-machine-neovim-colors.md)
- [Fix tmux command-prompt rendering](09-tmux-command-prompt-rendering.md)
