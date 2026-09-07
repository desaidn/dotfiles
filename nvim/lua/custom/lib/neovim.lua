local M = { minimum = '0.12.5' }

function M.check()
  local version_api = vim.version
  local version = version_api and version_api()
  local supported = type(version_api) == 'table' and type(version_api.ge) == 'function' and version and version_api.ge(version, M.minimum) or false

  return supported, ('Neovim %s (minimum: %s)'):format(tostring(version or 'unknown'), M.minimum)
end

return M
