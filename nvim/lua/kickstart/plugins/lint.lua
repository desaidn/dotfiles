-- Linting via nvim-lint with eslint_d and ruff.
-- https://github.com/mfussenegger/nvim-lint

return {

  {
    'mfussenegger/nvim-lint',
    event = { 'BufReadPre', 'BufNewFile' },
    config = function()
      local lint = require 'lint'

      -- Base linter configuration
      lint.linters_by_ft = {}

      -- Only add linters if they're available
      if vim.fn.executable 'ruff' == 1 then lint.linters_by_ft.python = { 'ruff' } end

      if vim.fn.executable 'eslint_d' == 1 then
        local js_fts = { 'javascript', 'javascriptreact', 'typescript', 'typescriptreact' }
        for _, ft in ipairs(js_fts) do
          lint.linters_by_ft[ft] = { 'eslint_d' }
        end
      end

      -- For more linter options and default linters, see:
      --  https://github.com/mfussenegger/nvim-lint#available-linters

      -- Skip read-only buffers (e.g. LSP hover popups) to avoid superfluous noise
      local function try_lint_if_modifiable()
        if vim.bo.modifiable then lint.try_lint() end
      end

      -- Run linters on key buffer events
      local lint_augroup = vim.api.nvim_create_augroup('lint', { clear = true })

      vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWritePost', 'InsertLeave', 'CursorHold', 'CursorHoldI' }, {
        group = lint_augroup,
        callback = try_lint_if_modifiable,
      })

      -- Debounce lint calls during real-time editing to avoid excessive runs
      local debounce_timer = assert(vim.uv.new_timer())
      vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
        group = lint_augroup,
        callback = function()
          debounce_timer:stop()
          debounce_timer:start(100, 0, function()
            vim.schedule(try_lint_if_modifiable)
          end)
        end,
      })
    end,
  },
}
