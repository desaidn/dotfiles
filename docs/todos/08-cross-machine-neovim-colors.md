# Make Web-Language Colors Consistent Across Machines

## Outcome

TypeScript, JavaScript, HTML, JSX, and TSX should produce the same effective syntax colors on the personal and work machines when using the same dotfiles revision. The fix must follow evidence identifying which runtime layer differs.

## Reproduction / current state

The work laptop displays different colors for the affected languages. The exact differing tokens and highlight groups have not yet been captured, so the cause is unproven.

The custom colorscheme inherits Neovim's default colors and explicitly normalizes only a subset of markup tag captures in [`custom.lua`](../../nvim/colors/custom.lua). Highlighting can also be affected by Treesitter queries/parser artifacts and LSP semantic tokens. Plugin source revisions are recorded in [`nvim-pack-lock.json`](../../nvim/nvim-pack-lock.json), while Treesitter parsers are installed from the set in [`parsers.lua`](../../nvim/lua/kickstart/parsers.lua). Mason-managed language servers may differ by install date/version across machines.

The production config requires Neovim 0.12.4, which narrows but does not eliminate environmental drift. Both machines are required to finish diagnosis.

## Scope

- Create or choose a small deterministic fixture containing representative TS, JS, HTML, JSX, and TSX tokens.
- Capture comparable machine snapshots: repo revision, Neovim version/build, effective colorscheme options, plugin revision, parser/query identity, language-server versions, active LSP clients, and effective highlight stacks at fixed token positions.
- Diff the snapshots before selecting a fix.
- Correct or pin only the layer proven to differ, or explicitly normalize highlight groups when the upstream difference is intentional but undesirable.
- Add a repeatable diagnostic or regression appropriate to the identified cause.
- Document how to verify future cross-machine consistency.

## Boundaries / non-goals

- Do not broadly hardcode every Treesitter or semantic-token group before locating the difference.
- Do not disable semantic tokens or Treesitter globally as a diagnostic shortcut turned permanent.
- Do not assume parser drift, Mason drift, terminal color capability, or repo divergence without comparing evidence.
- Do not solve the problem with machine-specific colorscheme branches.
- Do not add a new colorscheme plugin merely to avoid investigating the current stack.
- Keep the comparison free of private work-repository source by using a synthetic fixture.

## Open decisions

- Which exact tokens differ, and which highlight layer wins at those positions on each machine?
- Are the repo checkout, lockfile, Neovim build, terminal settings, parser/query revisions, and Mason receipts actually identical?
- Is the visible foreground coming from a Treesitter capture, an LSP semantic token, a legacy syntax group, or a link inherited from the default colorscheme?
- If upstream runtime artifacts differ, should the repo pin them, verify them, or normalize the final groups?
- What lightweight snapshot format is stable enough to compare without creating a brittle pixel test?

## Acceptance criteria

- A repository-safe fixture reproduces the original mismatch before the fix.
- Snapshot output from both machines identifies the effective highlight contributors and relevant version/hash differences.
- The chosen fix is tied to the observed difference rather than a guessed layer.
- The affected tokens resolve to equivalent effective highlight definitions on both machines after the change.
- Unrelated language highlighting and the intended custom tag colors remain intact.
- A repeatable command or documented procedure can detect recurrence without using proprietary source files.
- The reason for any new pin or explicit highlight override is documented near the owning configuration.

## Verification

On both machines, from the same fixture and repository revision, capture at least:

- `nvim --version` and repo `HEAD`.
- Locked and actual plugin revisions.
- Parser binary and query identities/hashes for the affected languages.
- Mason package receipts or language-server versions.
- `colors_name`, `termguicolors`, active LSP clients, and semantic-token state.
- `vim.inspect_pos()` or equivalent current Neovim inspection at fixed token coordinates.

Diff the machine-readable snapshots, apply the smallest justified change, then repeat the same capture and visually inspect the fixture in both terminal environments.

The repository includes a synthetic fixture and a headless capture tool for this comparison. From the repository root, run this on each machine:

```bash
nvim --headless -u nvim/init.lua -l nvim/scripts/web_color_snapshot.lua capture /tmp/web-colors.json ~/Projects/desaidn.dev
```

Copy one snapshot to the other machine, then compare them:

```bash
nvim --headless -u nvim/init.lua -l nvim/scripts/web_color_snapshot.lua compare /tmp/personal.json /tmp/work.json
```

The final argument selects the project TypeScript installation used for semantic tokens and defaults to `~/Projects/desaidn.dev` when omitted. The capture prints the resolved definition for each representative token and writes the full evidence as JSON. The comparison exits non-zero only when resolved token colors differ; parser, query, plugin, LSP, TypeScript, or environment differences are reported separately so they can explain a mismatch without being mistaken for one.

Because the capture is headless, its `headless_termguicolors` value does not prove what the TUI auto-detected. In a normal Neovim session on each machine, also run `:set termguicolors?` and record the result alongside the JSON snapshot.

## Starting points / references

- [`nvim/colors/custom.lua`](../../nvim/colors/custom.lua) — inherited defaults and explicit web-tag groups.
- [`nvim/lua/kickstart/parsers.lua`](../../nvim/lua/kickstart/parsers.lua) and [`treesitter.lua`](../../nvim/lua/kickstart/plugins/treesitter.lua) — parser installation and attachment.
- [`nvim/lua/custom/lib/pack.lua`](../../nvim/lua/custom/lib/pack.lua) — parser installation after package changes.
- [`nvim/lua/custom/language_tooling.lua`](../../nvim/lua/custom/language_tooling.lua) and [`lsp.lua`](../../nvim/lua/kickstart/plugins/lsp.lua) — web-language servers and Mason ownership.
- [`nvim/nvim-pack-lock.json`](../../nvim/nvim-pack-lock.json) — locked plugin revisions.
- [`nvim/AGENTS.md`](../../nvim/AGENTS.md) — Neovim verification and native-first guidance.
