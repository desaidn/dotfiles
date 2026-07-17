-- Autoformat
-- See `:help conform`

local gh = require('custom.lib.pack').gh
local languages = require 'custom.languages'

vim.pack.add { gh 'stevearc/conform.nvim' }

require('conform').setup {
  notify_on_error = false,
  format_on_save = function(bufnr)
    -- Disable "format_on_save lsp_fallback" for languages that don't have a
    -- well standardized coding style. Add or re-enable filetypes in the Inventory.
    if languages.format_on_save_disabled_filetypes[vim.bo[bufnr].filetype] then
      return nil
    else
      return {
        timeout_ms = 500,
        lsp_format = 'fallback',
      }
    end
  end,
  formatters_by_ft = languages.formatters_by_ft,
}

vim.keymap.set({ 'n', 'v' }, '<leader>f', function() require('conform').format { async = true, lsp_format = 'fallback' } end, { desc = '[F]ormat buffer' })
