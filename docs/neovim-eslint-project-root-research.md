# Neovim ESLint project-root handling

Research date: 2026-08-13. Sources are upstream documentation and source code, checked against the revisions pinned in `nvim/nvim-pack-lock.json`.

## Conclusion

`nvim-lint` does **not** detect project roots for `eslint_d` out of the box. That is deliberate: its contribution guide says linter definitions must not contain project-root detection and tells callers to pass `cwd` to `try_lint`. If this setup keeps `nvim-lint` plus `eslint_d`, a small buffer-to-root resolver is the upstream-supported integration, not a workaround.

The no-custom-root-logic option is the ESLint language server already supported by `nvim-lspconfig`. Its current default configuration is explicitly monorepo-aware: it starts one server at the lockfile/Git project root, confirms that the buffer has an ESLint config in its ancestor chain, and defaults the server's per-document `workingDirectory` to `auto`. The Microsoft server then finds the nearest package/config marker and supplies that directory as ESLint's `cwd`.

For this repository today, however, the concrete recommendation is to keep `nvim-lint`/`eslint_d` and add the small nearest-ESLint-config `cwd` resolver. It follows `nvim-lint`'s documented contract, fixes all ESLint invocations in one editor adapter, and preserves the current, actively updated `eslint_d` 15 path. Switching diagnostic ownership to the LSP would be reasonable if its code actions or on-type protocol behavior are wanted for their own sake, but it is a larger change than this root bug warrants and Mason currently distributes the old `vscode-langservers-extracted` 4.10.0 package.

Independently, the most robust project-side fix is to make typed linting CWD-independent. `typescript-eslint` recommends `projectService` over `project`; if a relative `project` path is retained, explicitly setting `tsconfigRootDir` to the ESLint config directory guarantees that an editor or CLI launched elsewhere finds the same TSConfig.

## Why the current path is CWD-sensitive

The pinned `nvim-lint` implementation exposes `try_lint(..., { cwd = ... })`, but when neither that option nor a static linter `cwd` is present it uses `vim.fn.getcwd()`. Its built-in `eslint_d` adapter only selects a command, passes the buffer's absolute path through `--stdin-filename`, and parses JSON; it has no root discovery. These behaviors are explicit in the [pinned `nvim-lint` API](https://github.com/mfussenegger/nvim-lint/blob/a219b2c9e5b4765e5c845aba119dad55806fcaf1/lua/lint.lua#L42-L43), its [`cwd` fallback](https://github.com/mfussenegger/nvim-lint/blob/a219b2c9e5b4765e5c845aba119dad55806fcaf1/lua/lint.lua#L356-L400), and the [built-in `eslint_d` definition](https://github.com/mfussenegger/nvim-lint/blob/a219b2c9e5b4765e5c845aba119dad55806fcaf1/lua/lint/linters/eslint_d.lua#L1-L27). Most directly, upstream states: ["Linters must not have custom logic to detect a project root. Users should pass the `cwd` to `try_lint` instead."](https://github.com/mfussenegger/nvim-lint/blob/a219b2c9e5b4765e5c845aba119dad55806fcaf1/README.md#L324-L337)

`eslint_d` preserves that decision rather than correcting it. The client forwards `process.cwd()` to its daemon, and the daemon changes into that directory before invoking ESLint ([forwarder](https://github.com/mantoni/eslint_d.js/blob/main/lib/forwarder.js#L89-L108), [service](https://github.com/mantoni/eslint_d.js/blob/main/lib/service.js#L148-L185)). `ESLINT_D_ROOT` only changes where `eslint_d` searches for the ESLint package; it is not a lint working-directory setting ([README](https://github.com/mantoni/eslint_d.js/blob/main/README.md#environment-variables), [resolver](https://github.com/mantoni/eslint_d.js/blob/main/lib/resolver.js#L14-L28)).

That matters to typed linting. `typescript-eslint` documents that a relative `parserOptions.project` is interpreted relative to the working directory when no effective `tsconfigRootDir` is set. It also documents `tsconfigRootDir` specifically as the way to keep TSConfig lookup working when ESLint is run outside the project root ([parser `project`](https://typescript-eslint.io/packages/parser/#project), [`tsconfigRootDir`](https://typescript-eslint.io/packages/parser/#tsconfigrootdir)). Thus an absolute `--stdin-filename` identifies the source file but does not itself make `./tsconfig.json` relative to that file.

## Options compared

| Option | Root/CWD behavior | Fit for this configuration |
| --- | --- | --- |
| Keep `nvim-lint` + `eslint_d` | Caller must find the applicable root and pass `cwd` to every `try_lint` call. This is the documented `nvim-lint` design. | Valid and small, but the Neovim config owns marker policy and must keep it correct for monorepos. |
| Use `nvim-lspconfig`'s `eslint` server | Built-in project-root detection plus per-document `workingDirectory = { mode = 'auto' }`; one server supports different package configs in a monorepo. | Automatic alternative, but a larger capability swap whose Mason distribution is stale. Adopt for LSP features, not just to avoid a small root resolver. |
| Use Conform's `eslint_d` formatter | Conform's built-in formatter already finds the nearest `package.json` and runs there. | Not a replacement for diagnostics. It is relevant only if ESLint should own fixing/formatting; this repo already assigns formatting to Prettier. |
| Fix the ESLint config | Use `projectService: true`, or set `tsconfigRootDir: import.meta.dirname` alongside a relative `project`. | Recommended as defense in depth because terminal, CI, and every editor then agree. This is a project change, not an editor-side answer. |

### ESLint LSP evidence

The pinned `nvim-lspconfig` revision says that `vscode-eslint-language-server` [supports monorepos by default and automatically finds each package's config](https://github.com/neovim/nvim-lspconfig/blob/292f44408498103c47996ff5c18fd366293840d8/lsp/eslint.lua#L34-L40). Its root function selects a package-manager lockfile ahead of `.git`, verifies an ESLint config exists between the buffer and that project root, and starts the client at the project root ([root detection](https://github.com/neovim/nvim-lspconfig/blob/292f44408498103c47996ff5c18fd366293840d8/lsp/eslint.lua#L114-L152)). Its defaults then set [`workingDirectory = { mode = 'auto' }`](https://github.com/neovim/nvim-lspconfig/blob/292f44408498103c47996ff5c18fd366293840d8/lsp/eslint.lua#L153-L177).

The Microsoft server implements that promise per document. Its `auto` branch calls `findWorkingDirectory` for the current file ([settings resolution](https://github.com/microsoft/vscode-eslint/blob/main/server/src/eslint.ts#L870-L919)); the search recognizes all `eslint.config.*` variants, `package.json`, `.eslintignore`, and legacy configs, walking upward only within the workspace ([markers and search](https://github.com/microsoft/vscode-eslint/blob/main/server/src/eslint.ts#L784-L802), [`findWorkingDirectory`](https://github.com/microsoft/vscode-eslint/blob/main/server/src/eslint.ts#L1323-L1350)). It then passes the result as the ESLint class `cwd` and temporarily changes the server process into it while linting ([execution](https://github.com/microsoft/vscode-eslint/blob/main/server/src/eslint.ts#L1152-L1175)).

The long-lived LSP also removes the main reason for `eslint_d`: process startup cost. `eslint_d`'s own README says editors that cache ESLint instances do not gain performance from the daemon ([upstream note](https://github.com/mantoni/eslint_d.js/blob/main/README.md#atom-vscode-webstorm)).

There is an important distribution caveat. Mason's current registry entry installs [`vscode-langservers-extracted@4.10.0`](https://github.com/mason-org/mason-registry/blob/main/packages/eslint-lsp/package.yaml), a package published roughly two years ago, while current `eslint_d` 15 supports ESLint 4 through 10 and current Node LTS releases ([compatibility table](https://github.com/mantoni/eslint_d.js/blob/main/README.md#compatibility)). The old server already contains automatic working-directory support, so this does not invalidate the root-handling comparison. It does make replacing a current CLI adapter with that server solely for this bug a poor maintenance trade.

### Conform evidence

Conform is more opinionated about formatter roots than `nvim-lint`: its pinned built-in [`eslint_d` formatter](https://github.com/stevearc/conform.nvim/blob/619363c30309d29ffa631e67c8183f2a72caa373/lua/conform/formatters/eslint_d.lua#L1-L13) sets `cwd` using the nearest `package.json`. That handles fix output (`--fix-to-stdout`), not diagnostic publication, so moving lint diagnostics to Conform would conflate two capabilities.

## Recommended Neovim direction

Keep the existing language configuration and `nvim-lint`/`eslint_d` ownership. Resolve the nearest `eslint.config.*` from the current buffer and pass that directory as `try_lint`'s `cwd`; do not change Neovim's global CWD. The resolver belongs in the `nvim-lint` adapter, not in each language declaration or in the built-in linter table.

This is hand-written integration code, but it is precisely the extension point upstream documents. Use all six flat-config names as equal-priority markers, search upward from the buffer, and fall back to normal `nvim-lint` behavior when none exists. For the affected file this selects `packages/assets`, so both package-local ESLint resolution and `./tsconfig.json` agree with the package's own lint command.

If the repository later chooses the ESLint LSP for its richer diagnostics/code-action contract, use `nvim-lspconfig`'s defaults rather than recreating its root logic. No custom `root_dir` or `workingDirectory` override should be needed for the affected pnpm monorepo: the default finds the monorepo's `pnpm-lock.yaml`, and the server's `auto` search stops at the package-local `eslint.config.js`/`package.json`.
