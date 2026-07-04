local M = {}

local function module_path(module_name)
  local parts = vim.split(module_name, '.', { plain = true })
  return vim.fs.joinpath(vim.fn.stdpath 'config', 'lua', unpack(parts))
end

local function discover_modules(module_name)
  local dir = module_path(module_name)
  local modules = {}

  for file_name, entry_type in vim.fs.dir(dir, { follow = true }) do
    if (entry_type == 'file' or entry_type == 'link') and file_name:match '%.lua$' and file_name ~= 'init.lua' then
      local module = file_name:gsub('%.lua$', '')
      table.insert(modules, module)
    end
  end

  table.sort(modules)
  return modules
end

function M.require_dir(module_name, opts)
  opts = opts or {}
  local loaded = {}

  for _, name in ipairs(opts.order or {}) do
    require(module_name .. '.' .. name)
    loaded[name] = true
  end

  for _, name in ipairs(discover_modules(module_name)) do
    if not loaded[name] then require(module_name .. '.' .. name) end
  end
end

return M
