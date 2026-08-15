-- Buffer-derived project paths shared by language consumers.

local M = {}

local function named_file(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(bufnr) or vim.bo[bufnr].buftype ~= '' then return nil end

  local path = vim.api.nvim_buf_get_name(bufnr)
  if path == '' then return nil end
  return vim.fs.normalize(vim.fn.fnamemodify(path, ':p'))
end

---@param bufnr integer?
---@param profile { markers: string[] | string[][], resolve?: fun(path: string): string? }
---@return { root: string, path: string }?
function M.for_buffer(bufnr, profile)
  assert(type(profile) == 'table' and type(profile.markers) == 'table', 'project context requires marker profile')

  local path = named_file(bufnr)
  if not path then return nil end

  local root = profile.resolve and profile.resolve(path) or vim.fs.root(path, profile.markers)
  if not root then return nil end
  root = vim.fs.normalize(root)

  return { root = root, path = path }
end

---@param consumer string
---@param root string
---@return string
function M.workspace_data(consumer, root)
  assert(type(consumer) == 'string' and consumer ~= '', 'workspace-data consumer is required')
  assert(type(root) == 'string' and root ~= '', 'workspace-data root is required')

  local normalized_root = vim.fs.normalize(vim.fn.fnamemodify(root, ':p'))
  local readable_name = vim.fs.basename(normalized_root):gsub('[^%w._-]', '-')
  local identity = vim.fn.sha256(normalized_root):sub(1, 12)
  return vim.fs.joinpath(vim.fn.stdpath 'cache', consumer, readable_name .. '-' .. identity)
end

return M
