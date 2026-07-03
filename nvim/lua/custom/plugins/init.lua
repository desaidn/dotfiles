-- You can add your own plugins here or in other files in this directory!
--  I promise not to create any merge conflicts in this directory :)
--
-- See the kickstart.nvim README for more information

local plugins_dir = vim.fs.joinpath(vim.fn.stdpath 'config', 'lua', 'custom', 'plugins')
local modules = {}

for file_name, entry_type in vim.fs.dir(plugins_dir, { follow = true }) do
  if (entry_type == 'file' or entry_type == 'link') and file_name:match '%.lua$' and file_name ~= 'init.lua' then
    local module = file_name:gsub('%.lua$', '')
    table.insert(modules, module)
  end
end

table.sort(modules)

for _, module in ipairs(modules) do
  require('custom.plugins.' .. module)
end
