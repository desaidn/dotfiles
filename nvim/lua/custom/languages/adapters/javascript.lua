-- JavaScript and TypeScript share project-owned semantics, ESLint, and js-debug.

local capabilities = require 'custom.languages.capabilities'
local context = require 'custom.languages.context'
local prettier = { 'prettierd', 'prettier', stop_after_first = true }
local filetypes = { 'javascript', 'javascriptreact', 'typescript', 'typescriptreact' }

local typescript_projects = {}
local javascript_root_markers = {
  { 'package-lock.json', 'yarn.lock', 'pnpm-lock.yaml', 'bun.lockb', 'bun.lock' },
  { '.git' },
}
local javascript_launch_types = { 'node', 'chrome', 'msedge', 'pwa-node', 'pwa-chrome', 'pwa-msedge' }
local javascript_launch_aliases = {
  node = 'pwa-node',
  chrome = 'pwa-chrome',
  msedge = 'pwa-msedge',
}

local function javascript_root(path)
  local project_root = vim.fs.root(path, javascript_root_markers)
  if not project_root then return nil end

  local deno_root = vim.fs.root(path, { 'deno.json', 'deno.jsonc' })
  local deno_lock_root = vim.fs.root(path, { 'deno.lock' })
  if deno_lock_root and #deno_lock_root > #project_root then return nil end
  if deno_root and #deno_root >= #project_root then return nil end
  return project_root
end

local javascript_root_profile = {
  markers = javascript_root_markers,
  resolve = javascript_root,
}

local function prepare_javascript_launch(config)
  config.type = javascript_launch_aliases[config.type] or config.type
  return config
end

local javascript_dap = {
  lsp_client = 'tsc',
  root_profile = javascript_root_profile,
  launch_types = javascript_launch_types,
  prepare_launch = prepare_javascript_launch,
}

local function project_typescript(root)
  if typescript_projects[root] then return typescript_projects[root] end

  local executable = vim.fn.has 'win32' == 1 and 'tsc.cmd' or 'tsc'
  local compiler = vim.fs.joinpath(root, 'node_modules', '.bin', executable)
  if vim.fn.executable(compiler) ~= 1 then return nil end

  local result = vim.system({ compiler, '--version' }, { text = true }):wait()
  local version = result.code == 0 and vim.version.parse(result.stdout or '') or nil
  if not version then return nil end

  local tsserver = vim.fs.joinpath(root, 'node_modules', 'typescript', 'lib', 'tsserver.js')
  local tsserver_stat = vim.uv.fs_stat(tsserver)
  local project = {
    compiler = compiler,
    version = version,
    tsserver = tsserver_stat and tsserver_stat.type == 'file' and tsserver or nil,
  }
  typescript_projects[root] = project
  return project
end

local function typescript_context(bufnr)
  local project = context.for_buffer(bufnr, javascript_root_profile)
  if not project then return nil end

  local typescript = project_typescript(project.root)
  if not typescript then return nil end
  return { root = project.root, path = project.path, typescript = typescript }
end

local function typescript_root(bufnr, on_dir)
  local project = typescript_context(bufnr)
  if not project or project.typescript.version.major < 7 then return end

  on_dir(project.root)
end

local function start_typescript(dispatchers, config)
  local root = assert(config and config.root_dir, 'TypeScript requires a project root')
  local project = assert(project_typescript(root), 'TypeScript is not installed in the project root')
  assert(project.version.major >= 7, 'TypeScript 7+ is not installed in the project root')
  return vim.lsp.rpc.start({ project.compiler, '--lsp', '--stdio' }, dispatchers, { cwd = root })
end

local function legacy_typescript_root(bufnr, on_dir)
  local project = typescript_context(bufnr)
  if not project or project.typescript.version.major >= 7 or not project.typescript.tsserver then return end

  on_dir(project.root)
end

local function configure_legacy_typescript(params, config)
  local root = assert(config and config.root_dir, 'TypeScript compatibility requires a project root')
  local project = assert(project_typescript(root), 'TypeScript is not installed in the project root')
  assert(project.version.major < 7 and project.tsserver, 'A pre-TypeScript-7 tsserver is not installed in the project root')

  config.init_options = config.init_options or {}
  config.init_options.tsserver = config.init_options.tsserver or {}
  config.init_options.tsserver.path = project.tsserver
  params.initializationOptions = config.init_options
end

local function start_legacy_typescript(dispatchers, config)
  local root = assert(config and config.root_dir, 'TypeScript compatibility requires a project root')
  local project = assert(project_typescript(root), 'TypeScript is not installed in the project root')
  assert(project.version.major < 7 and project.tsserver, 'A pre-TypeScript-7 tsserver is not installed in the project root')
  return vim.lsp.rpc.start({ 'typescript-language-server', '--stdio' }, dispatchers, { cwd = root })
end

local function enforce_legacy_typescript(_, result, handler_context)
  local client_id = handler_context and handler_context.client_id
  local client = client_id and vim.lsp.get_client_by_id(client_id) or nil
  if not client then return end

  local root = client.config and client.config.root_dir
  local project = root and project_typescript(root) or nil
  local reported = result and vim.version.parse(result.version or '') or nil
  local matches_project = project
    and project.version.major < 7
    and project.tsserver
    and result
    and result.source == 'user-setting'
    and reported
    and vim.version.cmp(project.version, reported) == 0
  if matches_project then return end

  local source = result and result.source or 'unknown'
  local version = result and result.version or 'unknown'
  vim.notify(
    ('TypeScript compatibility rejected %s TypeScript %s; restart Neovim after repairing the project installation'):format(source, version),
    vim.log.levels.ERROR,
    { title = 'TypeScript' }
  )
  client:stop(true)
end

local did_setup = false

local function current_project() return context.for_buffer(nil, javascript_root_profile) end

local function current_program()
  local project = current_project()
  if project then return project.path end
  return require('dap').ABORT
end

local function current_root()
  local project = current_project()
  if project then return project.root end
  return require('dap').ABORT
end

local function ensure_js_debug()
  if did_setup then return end

  local executable = vim.fn.exepath 'js-debug-adapter'
  if executable == '' then error 'Mason js-debug-adapter is not installed or unavailable on PATH' end

  local debugger = require 'dap'
  local adapter = {
    type = 'server',
    host = '127.0.0.1',
    port = '${port}',
    executable = {
      command = executable,
      args = { '${port}', '127.0.0.1' },
    },
  }
  local function resolve_alias(resolve, config)
    prepare_javascript_launch(config)
    resolve(adapter)
  end
  for _, launch_type in ipairs(javascript_launch_types) do
    local normalized = prepare_javascript_launch { type = launch_type }
    debugger.adapters[launch_type] = normalized.type == launch_type and adapter or resolve_alias
  end

  debugger.configurations.javascript = debugger.configurations.javascript or {}
  debugger.configurations.javascript[#debugger.configurations.javascript + 1] = {
    type = 'pwa-node',
    request = 'launch',
    name = 'Launch current JavaScript file',
    program = current_program,
    cwd = current_root,
  }
  did_setup = true
end

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

local M = {
  lsp_servers = {
    tsc = {
      cmd = start_typescript,
      root_dir = typescript_root,
      workspace_required = true,
      on_attach = capabilities.disable_formatting,
    },
    ts_ls = {
      cmd = start_legacy_typescript,
      root_dir = legacy_typescript_root,
      workspace_required = true,
      before_init = configure_legacy_typescript,
      handlers = { ['$/typescriptVersion'] = enforce_legacy_typescript },
      -- Preserve nvim-lspconfig's buffer commands while Conform owns formatting.
      on_init = capabilities.disable_formatting,
    },
  },
  mason_tools = { 'js-debug-adapter', 'typescript-language-server', 'eslint_d', 'prettier', 'prettierd' },
  treesitter_parsers = { 'javascript', 'typescript', 'tsx' },
  formatters_by_ft = {
    javascript = prettier,
    javascriptreact = prettier,
    typescript = prettier,
    typescriptreact = prettier,
  },
  linters_by_ft = {
    javascript = { 'eslint_d' },
    javascriptreact = { 'eslint_d' },
    typescript = { 'eslint_d' },
    typescriptreact = { 'eslint_d' },
  },
  dap_by_ft = {
    javascript = javascript_dap,
    javascriptreact = javascript_dap,
    typescript = javascript_dap,
    typescriptreact = javascript_dap,
  },
}

function M.setup()
  local gh = require('custom.lib.pack').gh
  local dap = require 'custom.languages.dap'

  -- Linting via nvim-lint: https://github.com/mfussenegger/nvim-lint
  vim.pack.add { gh 'mfussenegger/nvim-lint' }

  local lint = require 'lint'

  -- Only enable declared linters when their executables are available.
  lint.linters_by_ft = {}
  for filetype, declared_linters in pairs(M.linters_by_ft) do
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

  vim.api.nvim_create_autocmd('FileType', {
    group = vim.api.nvim_create_augroup('javascript-dap-setup', { clear = true }),
    pattern = filetypes,
    callback = function(event) dap.register_buffer_setup(event.buf, ensure_js_debug) end,
  })
end

return M
