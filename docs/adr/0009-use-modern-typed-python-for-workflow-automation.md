---
status: amended by ADR-0012
---

# Use modern typed Python for workflow automation

The Workflow Engine uses the latest deliberately pinned Python 3.14 patch, initially [Python 3.14.7](https://www.python.org/downloads/release/python-3147/), and is packaged, installed, and tested with `uv`; workflow policy is not duplicated in shell. The implementation follows the typed functional-core/effectful-shell style described in [Statically Typed Functional Programming with Python 3.12](https://wickstrom.tech/2024-05-23-statically-typed-functional-programming-python-312.html): immutable dataclasses and union types model inputs, states, transitions, and failures; pattern matching and pure functions decide what may happen; narrow outer adapters perform Git, Herdr, Neovim, Hunk, filesystem, and process effects. Git remains the source of repository truth. Existing shell configuration and the self-contained installer safety boundary remain outside this workflow module. This uses the repository's existing Mise ownership of Python while making orchestration testable and deterministic without introducing a second implementation language. ADR 0012 removes repository-hook enforcement while retaining these language, packaging, and architecture decisions.
