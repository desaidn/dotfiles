-- Evaluate cwd-dependent plugin code without changing Neovim's directory scopes.
-- The callback must be synchronous and must not change directories or windows.
---@generic T
---@param directory string
---@param callback fun(): T?
---@return T?
return function(directory, callback)
  local previous = assert(vim.uv.cwd())
  assert(vim.uv.chdir(directory))
  local ok, result = pcall(callback)
  assert(vim.uv.chdir(previous))
  if not ok then error(result, 0) end
  return result
end
