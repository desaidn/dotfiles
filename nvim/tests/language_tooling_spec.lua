local failures = {}
local script_path = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p')
local nvim_root = vim.fs.normalize(vim.fs.dirname(script_path) .. '/..')

package.path = table.concat({
  nvim_root .. '/lua/?.lua',
  nvim_root .. '/lua/?/init.lua',
  package.path,
}, ';')

local model = require 'custom.language_tooling.model'

local function check(name, body)
  local ok, err = pcall(body)
  if ok then
    io.stdout:write('PASS ', name, '\n')
    return
  end

  failures[#failures + 1] = name
  io.stderr:write('FAIL ', name, '\n  ', tostring(err):gsub('\n', '\n  '), '\n')
end

---@param actual string[]
---@param expected string[]
local function assert_list(actual, expected)
  assert(#actual == #expected, string.format('expected %d items, got %d', #expected, #actual))
  for index, expected_item in ipairs(expected) do
    assert(actual[index] == expected_item, string.format('item %d: expected %q, got %q', index, expected_item, tostring(actual[index])))
  end
end

local function assert_deep_equal(actual, expected, path)
  path = path or 'value'
  assert(type(actual) == type(expected), string.format('%s: expected %s, got %s', path, type(expected), type(actual)))
  if type(expected) ~= 'table' then
    assert(actual == expected, string.format('%s: expected %q, got %q', path, tostring(expected), tostring(actual)))
    return
  end

  for key, expected_value in pairs(expected) do
    assert(actual[key] ~= nil, string.format('%s: missing key %q', path, tostring(key)))
    assert_deep_equal(actual[key], expected_value, string.format('%s[%q]', path, tostring(key)))
  end
  for key in pairs(actual) do
    assert(expected[key] ~= nil, string.format('%s: unexpected key %q', path, tostring(key)))
  end
end

check('projects LSP servers in language declaration order', function()
  local tooling = model.create {
    languages = {
      {
        name = 'typescript',
        lsps = {
          { server = 'ts_ls', install = 'typescript-language-server' },
          { server = 'eslint' },
        },
      },
      {
        name = 'python',
        lsps = { { server = 'pyright' } },
      },
      { name = 'markdown' },
    },
  }

  assert_list(tooling.lsp_servers(), { 'ts_ls', 'eslint', 'pyright' })
end)

check('projects unique Mason installs in first-seen language order', function()
  local tooling = model.create {
    languages = {
      {
        name = 'typescript',
        lsps = { { server = 'ts_ls', install = 'typescript-language-server' } },
        tools = { 'prettier', 'prettierd' },
      },
      {
        name = 'json',
        lsps = { { server = 'jsonls', install = 'json-lsp' } },
        tools = { 'prettier', 'prettierd' },
      },
      {
        name = 'go',
        lsps = { { server = 'gopls' } },
      },
    },
  }

  assert_list(tooling.mason_tools(), { 'typescript-language-server', 'prettier', 'prettierd', 'json-lsp', 'gopls' })
end)

check('projects native formatter lists to every declared filetype', function()
  local tooling = model.create {
    languages = {
      {
        name = 'typescript',
        filetypes = { 'javascript', 'typescriptreact' },
        formatters = { 'prettierd', 'prettier', stop_after_first = true },
      },
      {
        name = 'lua',
        filetypes = { 'lua' },
        formatters = { 'stylua' },
      },
      { name = 'go', lsps = { { server = 'gopls' } } },
    },
  }

  assert_deep_equal(tooling.formatters_by_ft(), {
    javascript = { 'prettierd', 'prettier', stop_after_first = true },
    typescriptreact = { 'prettierd', 'prettier', stop_after_first = true },
    lua = { 'stylua' },
  })
end)

check('projects linter lists to every declared filetype', function()
  local tooling = model.create {
    languages = {
      {
        name = 'typescript',
        filetypes = { 'javascript', 'javascriptreact', 'typescript', 'typescriptreact' },
        linters = { 'eslint_d' },
      },
      {
        name = 'python',
        filetypes = { 'python' },
        linters = { 'ruff' },
      },
    },
  }

  assert_deep_equal(tooling.linters_by_ft(), {
    javascript = { 'eslint_d' },
    javascriptreact = { 'eslint_d' },
    typescript = { 'eslint_d' },
    typescriptreact = { 'eslint_d' },
    python = { 'ruff' },
  })
end)

check('keeps validated declarations isolated from later mutation', function()
  local options = {
    languages = {
      {
        name = 'lua',
        filetypes = { 'lua' },
        lsps = { { server = 'lua_ls' } },
        tools = { 'stylua' },
        formatters = { 'stylua' },
        linters = { 'selene' },
      },
    },
  }
  local tooling = model.create(options)

  options.languages[1].lsps[1].server = 'mutated_lsp'
  options.languages[1].tools[1] = 'mutated_tool'
  options.languages[1].formatters[1] = 'mutated_formatter'
  options.languages[1].linters[1] = 'mutated_linter'

  assert_list(tooling.lsp_servers(), { 'lua_ls' })
  assert_list(tooling.mason_tools(), { 'lua_ls', 'stylua' })
  assert_deep_equal(tooling.formatters_by_ft(), { lua = { 'stylua' } })
  assert_deep_equal(tooling.linters_by_ft(), { lua = { 'selene' } })

  local formatters = tooling.formatters_by_ft()
  local linters = tooling.linters_by_ft()
  formatters.lua[1] = 'mutated_formatter'
  linters.lua[1] = 'mutated_linter'

  assert_deep_equal(tooling.formatters_by_ft(), { lua = { 'stylua' } })
  assert_deep_equal(tooling.linters_by_ft(), { lua = { 'selene' } })
end)

check('rejects ambiguous formatter and linter filetype ownership', function()
  local ok, err = pcall(model.create, {
    languages = {
      {
        name = 'web-script',
        filetypes = { 'javascript' },
        formatters = { 'prettier' },
      },
      {
        name = 'typed-script',
        filetypes = { 'javascript' },
        linters = { 'eslint_d' },
      },
    },
  })

  assert(not ok, 'expected duplicate filetype ownership to fail')
  local message = tostring(err)
  assert(message:find('javascript', 1, true), 'error did not name the conflicting filetype')
  assert(message:find('web-script', 1, true), 'error did not name the first Language Family')
  assert(message:find('typed-script', 1, true), 'error did not name the second Language Family')
end)

check('requires filetypes when a Language Family declares formatters or linters', function()
  local ok, err = pcall(model.create, {
    languages = {
      {
        name = 'python',
        formatters = { 'ruff_format' },
        linters = { 'ruff' },
      },
    },
  })

  assert(not ok, 'expected a tool declaration without filetypes to fail')
  local message = tostring(err)
  assert(message:find('python', 1, true), 'error did not name the Language Family')
  assert(message:find('filetypes', 1, true), 'error did not identify the missing field')
end)

check('validates field shapes before cross-field requirements', function()
  local invalid_cases = {
    {
      field = 'formatters',
      shape = 'ordered list',
      language = { name = 'lua', formatters = 'stylua' },
    },
    {
      field = 'linters',
      shape = 'ordered array',
      language = { name = 'python', linters = 'ruff' },
    },
  }

  for _, invalid_case in ipairs(invalid_cases) do
    local ok, err = pcall(model.create, { languages = { invalid_case.language } })
    assert(not ok, string.format('expected invalid %s shape to fail', invalid_case.field))
    local message = tostring(err)
    assert(message:find(invalid_case.language.name, 1, true), 'error did not name the Language Family')
    assert(message:find(invalid_case.field, 1, true), string.format('error did not identify invalid %s shape', invalid_case.field))
    assert(message:find(invalid_case.shape, 1, true), string.format('error did not describe the required %s shape', invalid_case.field))
  end
end)

check('requires every Language Family to have a name', function()
  local ok, err = pcall(model.create, {
    languages = {
      ---@diagnostic disable-next-line: missing-fields -- Intentionally invalid input verifies runtime validation.
      { lsps = { { server = 'lua_ls' } } },
    },
  })

  assert(not ok, 'expected an unnamed Language Family to fail')
  local message = tostring(err)
  assert(message:find('Language Family', 1, true), 'error did not identify the invalid entry')
  assert(message:find('name', 1, true), 'error did not identify the missing field')
end)

check('requires Language Family and LSP declarations to be tables', function()
  local invalid_cases = {
    {
      label = 'Language Family',
      options = { languages = { false } },
    },
    {
      label = 'LSP',
      options = {
        languages = {
          { name = 'lua', lsps = { false } },
        },
      },
    },
  }

  for _, invalid_case in ipairs(invalid_cases) do
    local ok, err = pcall(model.create, invalid_case.options)
    assert(not ok, string.format('expected a non-table %s declaration to fail', invalid_case.label))
    local message = tostring(err)
    assert(message:find(invalid_case.label, 1, true), string.format('error did not identify the invalid %s declaration', invalid_case.label))
    assert(message:find('table', 1, true), string.format('error did not describe the required %s shape', invalid_case.label))
  end
end)

check('requires declarations to use plain data tables', function()
  local invalid_cases = {
    {
      context = 'options',
      options = setmetatable({ languages = {} }, {}),
    },
    {
      context = 'Language Family',
      options = {
        languages = { setmetatable({ name = 'lua' }, {}) },
      },
    },
    {
      context = 'LSP',
      options = {
        languages = {
          {
            name = 'lua',
            lsps = { setmetatable({}, { __index = { server = 'lua_ls' } }) },
          },
        },
      },
    },
    {
      context = 'tools',
      options = {
        languages = {
          { name = 'lua', tools = setmetatable({ 'stylua' }, {}) },
        },
      },
    },
    {
      context = 'formatters',
      options = {
        languages = {
          {
            name = 'lua',
            filetypes = { 'lua' },
            formatters = setmetatable({ 'stylua' }, {}),
          },
        },
      },
    },
  }

  for _, invalid_case in ipairs(invalid_cases) do
    local ok, err = pcall(model.create, invalid_case.options)
    assert(not ok, string.format('expected metatable-backed %s declaration to fail', invalid_case.context))
    local message = tostring(err)
    assert(message:find(invalid_case.context, 1, true), 'error did not identify the declaration context')
    assert(message:find('plain table', 1, true), 'error did not describe the plain-data requirement')
  end
end)

check('rejects unknown declaration fields', function()
  local invalid_cases = {
    {
      context = 'options',
      field = 'langauges',
      options = { languages = {}, langauges = {} },
    },
    {
      context = 'lua',
      field = 'tool',
      options = {
        languages = {
          { name = 'lua', tool = { 'stylua' } },
        },
      },
    },
    {
      context = 'LSP',
      field = 'instal',
      options = {
        languages = {
          {
            name = 'lua',
            lsps = { { server = 'lua_ls', instal = 'lua-language-server' } },
          },
        },
      },
    },
  }

  for _, invalid_case in ipairs(invalid_cases) do
    local ok, err = pcall(model.create, invalid_case.options)
    assert(not ok, string.format('expected unknown %s field to fail', invalid_case.field))
    local message = tostring(err)
    assert(message:find(invalid_case.context, 1, true), 'error did not identify the declaration context')
    assert(message:find(invalid_case.field, 1, true), 'error did not identify the unknown field')
  end
end)

check('rejects duplicate Language Family names', function()
  local ok, err = pcall(model.create, {
    languages = {
      { name = 'typescript', lsps = { { server = 'ts_ls' } } },
      { name = 'typescript', tools = { 'prettier' } },
    },
  })

  assert(not ok, 'expected a duplicate Language Family name to fail')
  local message = tostring(err)
  assert(message:find('duplicate', 1, true), 'error did not identify the duplicate')
  assert(message:find('typescript', 1, true), 'error did not name the duplicate Language Family')
end)

check('requires every LSP declaration to name its runtime server', function()
  local ok, err = pcall(model.create, {
    languages = {
      {
        name = 'lua',
        ---@diagnostic disable-next-line: missing-fields -- Intentionally invalid input verifies runtime validation.
        lsps = { { install = 'lua-language-server' } },
      },
    },
  })

  assert(not ok, 'expected an LSP without a server name to fail')
  local message = tostring(err)
  assert(message:find('lua', 1, true), 'error did not name the Language Family')
  assert(message:find('server', 1, true), 'error did not identify the missing LSP server')
end)

check('requires ordered arrays for languages and LSP declarations', function()
  local sparse_languages = {}
  sparse_languages[2] = true
  sparse_languages[5] = true

  local invalid_cases = {
    {
      field = 'languages',
      options = {
        languages = {
          lua = { name = 'lua', lsps = { { server = 'lua_ls' } } },
        },
      },
    },
    {
      field = 'lsps',
      options = {
        languages = {
          { name = 'lua', lsps = { server = 'lua_ls' } },
        },
      },
    },
    {
      field = 'languages',
      options = {
        languages = sparse_languages,
      },
    },
  }

  for _, invalid_case in ipairs(invalid_cases) do
    local ok, err = pcall(model.create, invalid_case.options)
    assert(not ok, string.format('expected keyed %s data to fail', invalid_case.field))
    assert(tostring(err):find(invalid_case.field, 1, true), string.format('error did not identify invalid %s data', invalid_case.field))
  end
end)

check('rejects sparse install tool arrays', function()
  local sparse_tools = {}
  sparse_tools[2] = 'ruff'

  local ok, err = pcall(model.create, {
    languages = {
      { name = 'python', tools = sparse_tools },
    },
  })

  assert(not ok, 'expected sparse install tools to fail')
  local message = tostring(err)
  assert(message:find('python', 1, true), 'error did not name the Language Family')
  assert(message:find('tools', 1, true), 'error did not identify the invalid field')
  assert(message:find('ordered array', 1, true), 'error did not describe the required shape')
end)

check('rejects sparse filetype arrays', function()
  local sparse_filetypes = {}
  sparse_filetypes[2] = 'python'

  local ok, err = pcall(model.create, {
    languages = {
      {
        name = 'python',
        filetypes = sparse_filetypes,
        formatters = { 'ruff_format' },
      },
    },
  })

  assert(not ok, 'expected sparse filetypes to fail')
  local message = tostring(err)
  assert(message:find('python', 1, true), 'error did not name the Language Family')
  assert(message:find('filetypes', 1, true), 'error did not identify the invalid field')
  assert(message:find('ordered array', 1, true), 'error did not describe the required shape')
end)

check('rejects sparse linter arrays', function()
  local sparse_linters = {}
  sparse_linters[2] = 'ruff'

  local ok, err = pcall(model.create, {
    languages = {
      {
        name = 'python',
        filetypes = { 'python' },
        linters = sparse_linters,
      },
    },
  })

  assert(not ok, 'expected sparse linters to fail')
  local message = tostring(err)
  assert(message:find('python', 1, true), 'error did not name the Language Family')
  assert(message:find('linters', 1, true), 'error did not identify the invalid field')
  assert(message:find('ordered array', 1, true), 'error did not describe the required shape')
end)

check('rejects sparse formatter lists while allowing fallback metadata', function()
  local sparse_formatters = { stop_after_first = true }
  sparse_formatters[2] = 'prettier'

  local ok, err = pcall(model.create, {
    languages = {
      {
        name = 'typescript',
        filetypes = { 'typescript' },
        formatters = sparse_formatters,
      },
    },
  })

  assert(not ok, 'expected sparse formatters to fail')
  local message = tostring(err)
  assert(message:find('typescript', 1, true), 'error did not name the Language Family')
  assert(message:find('formatters', 1, true), 'error did not identify the invalid field')
  assert(message:find('ordered list', 1, true), 'error did not describe the required shape')
end)

check('restricts formatter metadata to boolean stop_after_first', function()
  local invalid_formatters = {
    { 'prettier', stop_after_first = 'yes' },
    { 'prettier', timeout_ms = 500 },
  }

  for _, formatters in ipairs(invalid_formatters) do
    local ok, err = pcall(model.create, {
      languages = {
        {
          name = 'typescript',
          filetypes = { 'typescript' },
          formatters = formatters,
        },
      },
    })

    assert(not ok, 'expected unsupported formatter metadata to fail')
    local message = tostring(err)
    assert(message:find('typescript', 1, true), 'error did not name the Language Family')
    assert(message:find('formatters', 1, true), 'error did not identify the invalid field')
    assert(message:find('stop_after_first', 1, true), 'error did not describe the accepted formatter metadata')
  end
end)

check('requires every Mason install name to be a non-empty string', function()
  local invalid_languages = {
    {
      name = 'lua',
      lsps = { { server = 'lua_ls', install = 42 } },
    },
    {
      name = 'python',
      tools = { '' },
    },
  }

  for _, language in ipairs(invalid_languages) do
    local ok, err = pcall(model.create, { languages = { language } })
    assert(not ok, string.format('expected invalid Mason install data for %s to fail', language.name))
    local message = tostring(err)
    assert(message:find(language.name, 1, true), 'error did not name the Language Family')
    assert(message:find('install', 1, true), 'error did not identify the invalid Mason install name')
  end
end)

check('requires filetype formatter and linter names to be non-empty strings', function()
  local invalid_cases = {
    {
      field = 'filetypes',
      language = { name = 'lua', filetypes = { 42 }, formatters = { 'stylua' } },
    },
    {
      field = 'formatters',
      language = { name = 'lua', filetypes = { 'lua' }, formatters = { false } },
    },
    {
      field = 'linters',
      language = { name = 'python', filetypes = { 'python' }, linters = { '' } },
    },
  }

  for _, invalid_case in ipairs(invalid_cases) do
    local ok, err = pcall(model.create, { languages = { invalid_case.language } })
    assert(not ok, string.format('expected invalid %s data to fail', invalid_case.field))
    local message = tostring(err)
    assert(message:find(invalid_case.language.name, 1, true), 'error did not name the Language Family')
    assert(message:find(invalid_case.field, 1, true), string.format('error did not identify invalid %s data', invalid_case.field))
  end
end)

check('validates filetype values whenever filetypes are declared', function()
  local ok, err = pcall(model.create, {
    languages = {
      ---@diagnostic disable-next-line: assign-type-mismatch -- Intentionally invalid input verifies runtime validation.
      { name = 'metadata-only', filetypes = { 42 } },
    },
  })

  assert(not ok, 'expected invalid standalone filetypes to fail')
  local message = tostring(err)
  assert(message:find('metadata-only', 1, true), 'error did not name the Language Family')
  assert(message:find('filetypes', 1, true), 'error did not identify the invalid field')
end)

check('production inventory preserves current language tooling behavior', function()
  local tooling = require 'custom.language_tooling'

  assert_deep_equal({
    lsp_servers = tooling.lsp_servers(),
    mason_tools = tooling.mason_tools(),
    formatters_by_ft = tooling.formatters_by_ft(),
    linters_by_ft = tooling.linters_by_ft(),
  }, {
    lsp_servers = {
      'lua_ls',
      'ts_ls',
      'rust_analyzer',
      'gopls',
      'pyright',
      'jsonls',
      'yamlls',
      'html',
      'cssls',
      'hls',
      'jdtls',
      'kotlin_lsp',
    },
    mason_tools = {
      'lua-language-server',
      'stylua',
      'typescript-language-server',
      'prettier',
      'prettierd',
      'eslint_d',
      'rust-analyzer',
      'gopls',
      'pyright',
      'ruff',
      'json-lsp',
      'yaml-language-server',
      'html-lsp',
      'css-lsp',
      'haskell-language-server',
      'jdtls',
      'google-java-format',
      'kotlin-lsp',
      'ktlint',
    },
    formatters_by_ft = {
      lua = { 'stylua' },
      javascript = { 'prettierd', 'prettier', stop_after_first = true },
      javascriptreact = { 'prettierd', 'prettier', stop_after_first = true },
      typescript = { 'prettierd', 'prettier', stop_after_first = true },
      typescriptreact = { 'prettierd', 'prettier', stop_after_first = true },
      json = { 'prettierd', 'prettier', stop_after_first = true },
      jsonc = { 'prettierd', 'prettier', stop_after_first = true },
      css = { 'prettierd', 'prettier', stop_after_first = true },
      scss = { 'prettierd', 'prettier', stop_after_first = true },
      html = { 'prettierd', 'prettier', stop_after_first = true },
      markdown = { 'prettierd', 'prettier', stop_after_first = true },
      python = { 'ruff_fix', 'ruff_format', 'ruff_organize_imports' },
      java = { 'google-java-format' },
      kotlin = { 'ktlint' },
    },
    linters_by_ft = {
      javascript = { 'eslint_d' },
      javascriptreact = { 'eslint_d' },
      typescript = { 'eslint_d' },
      typescriptreact = { 'eslint_d' },
      python = { 'ruff' },
    },
  })
end)

if #failures > 0 then
  io.stderr:write(string.format('\n%d language_tooling regression check%s failed\n', #failures, #failures == 1 and '' or 's'))
  os.exit(1)
end

io.stdout:write '\nlanguage_tooling regression checks passed\n'
