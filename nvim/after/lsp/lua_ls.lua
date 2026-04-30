-- Lua Language Server configuration
-- Injects Neovim runtime settings only when editing the Neovim config directory.
-- Other Lua projects get plain lua_ls (or use their own .luarc.json).
--
-- See: https://luals.github.io/wiki/settings/

return {
  cmd = { 'lua-language-server' },
  filetypes = { 'lua' },
  root_markers = { '.luarc.json', '.luarc.jsonc', '.git' },
  ---@param client vim.lsp.Client
  on_init = function(client)
    if client.workspace_folders then
      local path = vim.fn.resolve(client.workspace_folders[1].name)
      if path ~= vim.fn.resolve(vim.fn.stdpath 'config') then return end
    end

    local current = client.config.settings.Lua or {} --[[@as table]]
    client.config.settings.Lua = vim.tbl_deep_extend('force', current, {
      runtime = { version = 'LuaJIT' },
      diagnostics = { globals = { 'vim' } },
      workspace = {
        checkThirdParty = false,
        library = {
          vim.env.VIMRUNTIME,
          '${3rd}/luv/library',
        },
      },
    })
  end,
  settings = {
    Lua = {
      completion = { callSnippet = 'Replace' },
      -- Uncomment to ignore noisy `missing-fields` warnings
      -- diagnostics = { disable = { 'missing-fields' } },
    },
  },
}
