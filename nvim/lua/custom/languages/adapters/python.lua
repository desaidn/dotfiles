-- Python owns debugpy; the shared DAP module remains language-neutral.

local gh = require('custom.lib.pack').gh

vim.pack.add({ gh 'mfussenegger/nvim-dap-python' }, { load = function() end })

local did_setup = false

local function ensure_debugpy()
  if did_setup then return end

  local ok, err = pcall(vim.cmd.packadd, 'nvim-dap-python')
  if not ok then error(('Unable to load nvim-dap-python: %s'):format(err)) end

  require('dap-python').setup 'uv'
  did_setup = true
end

vim.api.nvim_create_autocmd('FileType', {
  group = vim.api.nvim_create_augroup('python-dap-setup', { clear = true }),
  pattern = 'python',
  callback = function(event)
    require('custom.languages.dap').register_buffer_setup(event.buf, ensure_debugpy)
  end,
})
