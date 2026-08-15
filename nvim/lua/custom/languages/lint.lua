-- Linting via nvim-lint.
-- https://github.com/mfussenegger/nvim-lint

local gh = require('custom.lib.pack').gh
local languages = require 'custom.languages.config'

local eslint_config_markers = {
  {
    '.eslintrc',
    '.eslintrc.js',
    '.eslintrc.cjs',
    '.eslintrc.yaml',
    '.eslintrc.yml',
    '.eslintrc.json',
    'eslint.config.js',
    'eslint.config.mjs',
    'eslint.config.cjs',
    'eslint.config.ts',
    'eslint.config.mts',
    'eslint.config.cts',
  },
}

local function eslint_root(source) return vim.fs.root(source, eslint_config_markers) end

vim.pack.add { gh 'mfussenegger/nvim-lint' }

local lint = require 'lint'

-- Only enable declared linters when their executables are available.
lint.linters_by_ft = {}
for filetype, declared_linters in pairs(languages.linters_by_ft) do
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
  if not vim.bo.modifiable then return end

  local bufnr = vim.api.nvim_get_current_buf()
  local cwd
  for _, linter in ipairs(lint.linters_by_ft[vim.bo[bufnr].filetype] or {}) do
    if linter == 'eslint_d' then
      cwd = eslint_root(bufnr)
      break
    end
  end

  lint.try_lint(nil, { cwd = cwd })
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
    debounce_timer:start(100, 0, function() vim.schedule(try_lint_if_modifiable) end)
  end,
})
