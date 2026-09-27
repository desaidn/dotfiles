local function project_root(path)
  local repository = vim.fs.root(path, '.git')
  local function within_repository(markers)
    local root = vim.fs.root(path, markers)
    if root and (not repository or vim.fs.relpath(repository, root)) then return root end
  end

  return within_repository(function(name, parent) return name == '.vscode' and vim.uv.fs_stat(vim.fs.joinpath(parent, name, 'launch.json')) ~= nil end)
    or within_repository { { '.clangd', 'compile_commands.json', 'compile_flags.txt' } }
    or repository
    or vim.fs.root(path, { { 'CMakeLists.txt', 'Makefile', 'meson.build', 'configure.ac' } })
    or vim.fs.dirname(path)
end

local dap_config = {
  lsp_client = 'clangd',
  prefer_lsp_root = false,
  root_profile = { markers = {}, resolve = project_root },
  launch_types = { 'codelldb', 'lldb' },
  prepare_launch = function(config)
    -- CodeLLDB's VS Code extension uses "lldb"; native lldb-dap is a different adapter.
    if config.type == 'lldb' then config.type = 'codelldb' end
    return config
  end,
}

local M = {
  lsp_servers = { clangd = { filetypes = { 'c', 'cpp', 'c.doxygen', 'cpp.doxygen' } } },
  mason_tools = { 'clangd', 'clang-format', 'codelldb' },
  treesitter_parsers = { 'c', 'cpp' },
  formatters_by_ft = { c = { 'clang-format' }, cpp = { 'clang-format' } },
  format_on_save_disabled_filetypes = { c = true, cpp = true },
  dap_by_ft = { c = dap_config, cpp = dap_config },
}

local function codelldb_executable()
  local executable = vim.fn.exepath 'codelldb'
  if executable ~= '' then return executable end

  local root = require('mason.settings').current.install_root_dir
  local name = vim.fn.has 'win32' == 1 and 'codelldb.exe' or 'codelldb'
  executable = vim.fs.joinpath(root, 'packages', 'codelldb', 'extension', 'adapter', name)
  assert(vim.fn.executable(executable) == 1, 'CodeLLDB is unavailable. Install codelldb with :Mason, then retry debugging.')
  return executable
end

local function default_configurations(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then return {} end
  local filetype = vim.bo[bufnr].filetype
  if not M.dap_by_ft[filetype] then return {} end

  local dap = require 'dap'
  if #(dap.configurations[filetype] or {}) > 0 or #dap.providers.configs['dap.launch.json'](bufnr) > 0 then return {} end
  local project = require('custom.languages.dap').project(bufnr)
  if not project then return {} end

  return {
    {
      name = 'Launch executable',
      type = 'codelldb',
      request = 'launch',
      cwd = project.root,
      program = function()
        local executable = vim.fn.input('Executable: ', project.root .. '/', 'file')
        if executable == '' then return dap.ABORT end
        return executable
      end,
    },
    {
      name = 'Attach to process',
      type = 'codelldb',
      request = 'attach',
      cwd = project.root,
      pid = require('dap.utils').pick_process,
    },
  }
end

local function setup_debugger()
  local dap = require 'dap'
  if not dap.adapters.codelldb then
    dap.adapters.codelldb = {
      type = 'server',
      host = '127.0.0.1',
      port = '${port}',
      executable = { command = codelldb_executable(), args = { '--port', '${port}' } },
    }
  end
  dap.providers.configs['c_cpp.defaults'] = default_configurations
end

function M.setup()
  local conform = require 'conform'
  -- Inherit Conform's filename, style discovery, stdin, and range handling.
  conform.formatters['clang-format'] = conform.formatters['clang-format']
    or function(bufnr)
      local command = vim.b[bufnr].clang_format
      if command and vim.fn.executable(command) ~= 1 then
        vim.notify_once('Requested C/C++ formatter is unavailable: ' .. command .. '. Check b:clang_format and :ConformInfo.', vim.log.levels.ERROR)
      end
      return { command = command or 'clang-format' }
    end

  local group = vim.api.nvim_create_augroup('c-cpp-language-setup', { clear = true })
  vim.api.nvim_create_autocmd('LspAttach', {
    group = group,
    callback = function(event)
      local client = vim.lsp.get_client_by_id(event.data.client_id)
      if client and client.name == 'clangd' then require('custom.languages.capabilities').disable_formatting(client) end
    end,
  })
  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = { 'c', 'cpp' },
    callback = function(event) require('custom.languages.dap').register_buffer_setup(event.buf, setup_debugger) end,
  })
end

return M
