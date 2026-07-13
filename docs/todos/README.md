# TODO briefs

These briefs turn the repository's working TODO list into self-contained starting points for coding agents. Each brief records the desired outcome, current evidence, boundaries, unresolved decisions, acceptance criteria, and verification path without locking the implementer into a particular patch.

## Lifecycle

`TODO.md` and the index below are two views of the same active-work queue. They must contain the same items, and every item must link to exactly one brief under `docs/todos/`. This directory is not an archive.

### Adding an item

1. Create one self-contained `docs/todos/<NN>-<slug>.md` brief that describes the outcome, current evidence, boundaries, open decisions, acceptance criteria, verification, and useful references.
2. Add a matching item link to `TODO.md` and the index below.

Define what must be true without prescribing the exact patch. Do not include effort estimates or language that primes an implementing agent to expect a particular amount of work.

### While an item is active

Keep unresolved investigation and design context in the brief. Update it when new evidence changes the problem, but let the implementing agent inspect the current code and choose the implementation.

### Retiring an item

When an item is completed, abandoned, or superseded, retire it in the same change:

1. Preserve any durable knowledge in its proper long-lived home.
2. Remove the item from `TODO.md` and the index below.
3. Delete its brief.
4. Verify that the two indexes still match and no references to the deleted brief remain.

Never retain a completed entry as `[x]`, and do not keep its brief as a completion record. Code, tests, maintained documentation, and Git history record ordinary implementation work. If the work has an originating GitHub issue or spec, its specification, implementation decisions, and testing decisions remain there. Put shared domain terminology in `CONTEXT.md`; use an ADR only for an architectural decision that is surprising, difficult to reverse, and involves a meaningful tradeoff.

## Using a brief

Point an agent at one brief and ask it to take ownership of that item. The agent should still:

1. Read the repository-level `AGENTS.md` and any scoped `AGENTS.md` named by the brief.
2. Inspect the current implementation rather than assuming the snapshot in the brief is still exact.
3. Check current upstream documentation before changing integrations with external tools.
4. Resolve or surface the brief's open decisions before committing to a design.
5. Implement and run the listed verification in proportion to the change.

## Index

- [Deepen the Neovim runtime test harness](01-neovim-runtime-test-harness.md)
- [Add OCaml and OxCaml](03-ocaml-and-oxcaml.md)
- [Add Pi integration](04-pi-integration.md)
- [Add a local model](05-local-model.md)
- [Add Hunk preferences](06-hunk-preferences.md)
