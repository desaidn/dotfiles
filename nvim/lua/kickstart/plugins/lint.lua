-- Linting via nvim-lint.
-- https://github.com/mfussenegger/nvim-lint

local gh = require('custom.lib.pack').gh
local tooling = require 'custom.language_tooling'

vim.pack.add { gh 'mfussenegger/nvim-lint' }

local lint = require 'lint'

-- Only enable declared linters when their executables are available.
lint.linters_by_ft = {}
for filetype, declared_linters in pairs(tooling.linters_by_ft()) do
  local available_linters = {}
  for _, linter in ipairs(declared_linters) do
    if vim.fn.executable(linter) == 1 then available_linters[#available_linters + 1] = linter end
  end
  if #available_linters > 0 then lint.linters_by_ft[filetype] = available_linters end
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
