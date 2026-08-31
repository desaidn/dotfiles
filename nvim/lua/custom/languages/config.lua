local prettier = { 'prettierd', 'prettier', stop_after_first = true }
local capabilities = require 'custom.languages.capabilities'
local context = require 'custom.languages.context'

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

  project.typescript = project_typescript(project.root)
  if not project.typescript then return nil end
  return project
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
end

return {
  treesitter_parsers = {
    'bash',
    'c',
    'css',
    'diff',
    'dockerfile',
    'fish',
    'gitcommit',
    'gitignore',
    'haskell',
    'html',
    'java',
    'javascript',
    'json',
    'kotlin',
    'lua',
    'luadoc',
    'markdown',
    'markdown_inline',
    'python',
    'query',
    'regex',
    'rust',
    'scss',
    'sql',
    'toml',
    'tsx',
    'typescript',
    'vim',
    'vimdoc',
    'yaml',
  },

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
    bashls = {
      filetypes = { 'bash', 'sh' },
      on_attach = capabilities.disable_formatting,
      settings = {
        bashIde = {
          globPattern = '*@(.sh|.inc|.bash|.command)',
        },
      },
    },
    fish_lsp = {
      root_markers = { 'config.fish', '.git' },
    },
    basedpyright = {
      -- Neovim 0.12 pull diagnostics expose every edit as work progress.
      -- Push workspace diagnostics retain cross-file feedback and startup status.
      init_options = { disablePullDiagnostics = true },
      settings = {
        basedpyright = {
          analysis = { diagnosticMode = 'workspace' },
          disableOrganizeImports = true,
        },
      },
    },
    ruff = { on_attach = capabilities.disable_ruff_overlap },
    jsonls = { init_options = { provideFormatter = false } },
    yamlls = { settings = { yaml = { keyOrdering = false } } },
    html = { init_options = { provideFormatter = false } },
    cssls = { init_options = { provideFormatter = false } },
    hls = {},
    kotlin_lsp = {},
  },

  -- Keep install ownership explicit: an enabled LSP need not be Mason-managed.
  mason_tools = {
    'lua-language-server',
    'stylua',
    'js-debug-adapter',
    'typescript-language-server',
    'bash-language-server',
    'fish-lsp',
    'shellcheck',
    'shfmt',
    'prettier',
    'prettierd',
    'eslint_d',
    'rust-analyzer',
    'codelldb',
    'basedpyright',
    'ruff',
    'debugpy',
    'json-lsp',
    'yaml-language-server',
    'html-lsp',
    'css-lsp',
    'haskell-language-server',
    'jdtls',
    'java-debug-adapter',
    'java-test',
    'google-java-format',
    'kotlin-lsp',
    'ktlint',
  },

  formatters_by_ft = {
    lua = { 'stylua' },
    javascript = prettier,
    javascriptreact = prettier,
    bash = { 'shfmt' },
    sh = { 'shfmt' },
    typescript = prettier,
    typescriptreact = prettier,
    json = prettier,
    jsonc = prettier,
    css = prettier,
    scss = prettier,
    html = prettier,
    markdown = prettier,
    python = { 'ruff_fix', 'ruff_format', 'ruff_organize_imports' },
    java = { 'google-java-format' },
    kotlin = { 'ktlint' },
  },

  format_on_save_disabled_filetypes = {
    c = true,
    cpp = true,
  },

  -- Debug launch files are resolved from the active buffer's nearest project
  -- marker, never Neovim's process-wide current directory.
  dap_by_ft = {
    javascript = javascript_dap,
    javascriptreact = javascript_dap,
    typescript = javascript_dap,
    typescriptreact = javascript_dap,
    rust = {
      lsp_client = 'rust_analyzer',
      root_profile = { markers = { 'Cargo.toml', 'rust-project.json', '.git' } },
      launch_types = { 'codelldb' },
    },
  },

  linters_by_ft = {
    javascript = { 'eslint_d' },
    javascriptreact = { 'eslint_d' },
    typescript = { 'eslint_d' },
    typescriptreact = { 'eslint_d' },
  },
}
