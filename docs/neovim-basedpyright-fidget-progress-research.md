# BasedPyright and Fidget progress research

## Question

Why does Fidget show a completed LSP task after Python edits, including a
Normal-mode deletion, and what configuration preserves high-fidelity Python
tooling without misleading progress UI?

## Conclusion

The Python analysis is expected, but the repeated popup exposed an incomplete
BasedPyright configuration. Our setup did not start duplicate clients or send
duplicate edits. It inherited nvim-lspconfig's `openFilesOnly` default and
Neovim 0.12's pull-diagnostics capability, even though the high-fidelity plan
called for whole-workspace diagnostics. Each pull diagnostic request uses the
same standard work-done channel that Fidget renders.

Use BasedPyright's initialization option to retain push diagnostics and set the
requested workspace scope explicitly:

```lua
basedpyright = {
  init_options = {
    disablePullDiagnostics = true,
  },
  settings = {
    basedpyright = {
      analysis = {
        diagnosticMode = 'workspace',
      },
      disableOrganizeImports = true,
    },
  },
}
```

This is an analysis-delivery change, not a Fidget filter. BasedPyright still
analyzes edits and publishes live diagnostics; Fidget continues to receive the
meaningful initial workspace-analysis progress but receives no per-edit pull
progress. Java and Rust progress remain untouched. Projects should bound large
workspaces with their committed BasedPyright include/exclude configuration.

## Evidence

### Protocol and server behavior

- The LSP protocol makes server-initiated work-done progress conditional on
  the client advertising `window.workDoneProgress`; it is a reporting channel,
  not a diagnostic or analysis switch. [LSP work-done progress
  specification](https://github.com/microsoft/language-server-protocol/blob/gh-pages/_specifications/lsp/3.17/types/workDoneProgress.md#server-initiated-progress)
- Neovim advertises that capability by default and stores received progress in
  each LSP client's progress ring buffer. [Neovim default client
  capabilities](https://github.com/neovim/neovim/blob/master/runtime/lua/vim/lsp/protocol.lua#L626-L637),
  [Neovim client progress implementation](https://github.com/neovim/neovim/blob/master/runtime/lua/vim/lsp/client.lua#L430-L468)
- BasedPyright handles every `textDocument/didChange` by updating the open
  file in its containing workspace(s). Insertions and deletions take the same
  path. [BasedPyright change handler](https://github.com/DetachHead/basedpyright/blob/main/packages/pyright-internal/src/languageServerBase.ts#L1282-L1300)
- BasedPyright enables pull diagnostics only when the client advertises the
  relevant diagnostic capability and the initialization option has not set
  `disablePullDiagnostics = true`. In push mode it runs analysis itself;
  with pull diagnostics enabled, invalidation instead asks the client to
  refresh diagnostics. [BasedPyright capability and analysis selection](https://github.com/DetachHead/basedpyright/blob/main/packages/pyright-internal/src/languageServerBase.ts#L659-L674)
- Its progress wrapper emits a standard begin with an empty title, followed by
  analysis messages and an end; analysis completion starts/reports while files
  remain and ends at zero. [Progress wrapper](https://github.com/DetachHead/basedpyright/blob/main/packages/pyright-internal/src/languageServerBase.ts#L173-L193),
  [analysis progress update](https://github.com/DetachHead/basedpyright/blob/main/packages/pyright-internal/src/languageServerBase.ts#L1774-L1841)
- The server enables that standard path specifically when the client reports
  `window.workDoneProgress`. When it is absent, BasedPyright falls back to
  legacy `pyright/*Progress` notifications; capability removal therefore is
  not a server-analysis fix. [Capability detection](https://github.com/DetachHead/basedpyright/blob/main/packages/pyright-internal/src/languageServerBase.ts#L659-L674),
  [real server fallback implementation](https://github.com/DetachHead/basedpyright/blob/main/packages/pyright-internal/src/realLanguageServer.ts#L334-L380)

### Fidget behavior

- Fidget is expressly a UI for Neovim's `$/progress` handler. Its defaults
  allow new messages in Insert mode and retain completed work for three
  seconds. It provides `progress.ignore` to exclude named LSP clients. [Fidget
  README and configuration](https://github.com/j-hui/fidget.nvim/blob/main/README.md#configuration)
- Fidget substitutes the literal `"Completed"` when a completed progress
  event has no message, precisely matching the observed widget. [Default
  formatter](https://github.com/j-hui/fidget.nvim/blob/main/lua/fidget/progress/display.lua#L5-L24)

### Golden configurations reviewed

| Source | Relevant practice | Result |
| --- | --- | --- |
| [BasedPyright's official Neovim 0.11+ example](https://docs.basedpyright.com/latest/configuration/language-server-settings/#neovim) | Uses ordinary server settings and `diagnosticMode = "openFilesOnly"`; it does not discuss the Neovim 0.12 pull-diagnostics interaction. | Good generic baseline, but not a whole-workspace Neovim 0.12 configuration. |
| [nvim-lspconfig's BasedPyright definition](https://github.com/neovim/nvim-lspconfig/blob/master/lsp/basedpyright.lua) | Uses the normal command, Python filetype, project roots, and `openFilesOnly`. It does not set initialization options. | Confirms the inherited default that the high-fidelity inventory needed to override explicitly. |
| [kickstart.nvim](https://github.com/nvim-lua/kickstart.nvim/blob/master/init.lua#L565-L567) | Uses Fidget with its upstream defaults as a generic LSP-status UI; Python is intentionally only an example/commented server there. | Confirms Fidget itself was not customized incorrectly; the missing policy is in the Python diagnostic path. |

These samples establish the baseline but do not yet account for the Neovim
0.12 pull-diagnostics interaction. A current Neovim 0.12.2 community report
independently identifies `init_options.disablePullDiagnostics = true` as the
workaround that restores immediate cross-file diagnostics. [Neovim 0.12.2
BasedPyright diagnostic report](https://www.reddit.com/r/neovim/comments/1t64ymg/python_lsps_not_analyzing_workspace/)

### Local differential validation

The regression harness used a real BasedPyright client, the production Fidget
configuration, and a two-file Python workspace:

| Configuration | Startup progress | Progress after edit/delete | Live invalid-type diagnostic |
| --- | --- | --- | --- |
| inherited pull diagnostics + `openFilesOnly` | repeated cycles | repeated cycles | yes |
| `disablePullDiagnostics = true` + `workspace` | one begin/report/end | none | yes |

Ruff remained attached in the successful case, ruling out the auxiliary LSP as
the source. Current official Pyright was also tested under the same Neovim
client and emitted per-edit progress with pull diagnostics enabled, so merely
rolling back the BasedPyright package is not the fix.

## Rejected alternatives

| Alternative | Why it is not the recommended fix |
| --- | --- |
| `progress.ignore = { 'basedpyright' }` | Hides both useful startup analysis and noisy edit progress; it treats the presentation symptom rather than restoring the intended diagnostic path. |
| `progress.suppress_on_insert = true` | Fidget documents it as Insert-mode-only suppression. A Normal-mode delete still opens the popup. |
| `done_ttl = 0` or a custom `format_message` | Hides or relabels the symptom after the task has been reported; it does not establish a meaningful progress contract. |
| `window.workDoneProgress = false` for BasedPyright | Removes both startup and edit progress and makes the client inaccurately advertise a capability; BasedPyright still analyzes and switches to legacy notifications. |
| Disabling diagnostics | Sacrifices live feedback and conflicts with the high-fidelity requirement. |
| Stateful "show the first progress event only" filter | Startup and edit sequences use the same protocol shape, so this is an unreliable custom policy with no semantic boundary. |

## Validation for a future implementation

1. Open a Python file and confirm one BasedPyright client attaches.
2. Confirm one initial BasedPyright workspace-analysis progress cycle.
3. Insert and delete text; diagnostics must continue to update without a
   Fidget progress widget.
4. Change a definition used by another file and confirm workspace diagnostics
   refresh without reopening the dependent file.
5. Open or reimport a Java/Rust project; their genuine long-running progress
   must remain visible.
6. Run the existing language configuration spec. It is the durable regression
   seam because clean repository tests intentionally do not depend on
   user-state Mason packages.
7. Manually run the real BasedPyright headless smoke against installed Mason
   assets, checking startup progress, edit/delete silence, live diagnostics,
   and Ruff attachment. This environment-dependent check must accompany
   BasedPyright, Neovim, or nvim-lspconfig upgrades.
