-- Inject Neovim runtime settings only when editing the Neovim config directory.
-- Other Lua projects get the nvim-lspconfig defaults or use their own .luarc.json.
-- See: https://luals.github.io/wiki/settings/
---@param client vim.lsp.Client
local function configure_neovim_lua_workspace(client)
  if client.workspace_folders then
    local path = vim.fn.resolve(client.workspace_folders[1].name)
    if path ~= vim.fn.resolve(vim.fn.stdpath 'config') then return end
  end

  local current = client.config.settings.Lua or {} --[[@as table]]
  client.config.settings.Lua = vim.tbl_deep_extend('force', current, {
    runtime = {
      version = 'LuaJIT',
      -- Match Neovim's module roots so plugin names cannot alias config files.
      path = { 'lua/?.lua', 'lua/?/init.lua' },
    },
    diagnostics = { globals = { 'vim' } },
    workspace = {
      checkThirdParty = false,
      library = {
        vim.env.VIMRUNTIME,
        '${3rd}/luv/library',
      },
    },
  })
end

return {
  lsp_servers = {
    lua_ls = {
      on_init = configure_neovim_lua_workspace,
      settings = {
        Lua = {
          completion = { callSnippet = 'Replace' },
          -- Uncomment to ignore noisy `missing-fields` warnings.
          -- diagnostics = { disable = { 'missing-fields' } },
        },
      },
    },
  },
  mason_tools = { 'lua-language-server', 'stylua' },
  treesitter_parsers = { 'lua', 'luadoc' },
  formatters_by_ft = { lua = { 'stylua' } },
}
