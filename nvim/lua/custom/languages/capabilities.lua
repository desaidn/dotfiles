-- Shared LSP capability policy.

local M = {}

-- Conform is the sole formatter owner for configured languages.
function M.disable_formatting(client)
  client.server_capabilities.documentFormattingProvider = false
  client.server_capabilities.documentRangeFormattingProvider = false
end

return M
