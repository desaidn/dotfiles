-- Shared LSP capability policy.

local M = {}

-- Conform is the sole formatter owner for configured languages.
function M.disable_formatting(client)
  client.server_capabilities.documentFormattingProvider = false
  client.server_capabilities.documentRangeFormattingProvider = false
end

-- BasedPyright provides semantic hover while Ruff diagnostics/actions remain.
function M.disable_ruff_overlap(client)
  client.server_capabilities.hoverProvider = false
  M.disable_formatting(client)
end

return M
