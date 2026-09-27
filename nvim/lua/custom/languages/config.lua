-- One ordered list owns both inventory collection and adapter activation.
local adapter_names = {
  'bash',
  'c_cpp',
  'css',
  'fish',
  'html',
  'java',
  'javascript',
  'json',
  'kotlin',
  'lua',
  'python',
  'rust',
  'yaml',
  'supporting',
}

local list_fields = { 'mason_tools', 'treesitter_parsers' }
local map_fields = { 'lsp_servers', 'formatters_by_ft', 'format_on_save_disabled_filetypes', 'linters_by_ft', 'dap_by_ft' }
local inventory = {}
local owners = {}
local adapters = {}
for _, field in ipairs(list_fields) do
  inventory[field], owners[field] = {}, {}
end
for _, field in ipairs(map_fields) do
  inventory[field], owners[field] = {}, {}
end

for _, name in ipairs(adapter_names) do
  local adapter = require('custom.languages.adapters.' .. name)
  adapters[#adapters + 1] = adapter
  -- Shared tools and parsers are deliberately declared by every consumer.
  for _, field in ipairs(list_fields) do
    for _, value in ipairs(adapter[field] or {}) do
      if not owners[field][value] then
        inventory[field][#inventory[field] + 1] = value
        owners[field][value] = name
      end
    end
  end
  for _, field in ipairs(map_fields) do
    for key, value in pairs(adapter[field] or {}) do
      local owner = owners[field][key]
      if owner then error(('Duplicate %s entry %q in adapters %q and %q'):format(field, key, owner, name)) end
      inventory[field][key] = value
      owners[field][key] = name
    end
  end
end

-- Imports above are inert; activate only after the shared tooling is ready.
function inventory.setup()
  for _, adapter in ipairs(adapters) do
    if adapter.setup then adapter.setup() end
  end
end

return inventory
