local M = {}

local languages = { 'html', 'javascript', 'tsx', 'typescript' }
local relevant_plugins = { 'nvim-lspconfig', 'nvim-treesitter' }
local relevant_mason_packages = { 'html-lsp', 'typescript-language-server' }

M.fixture_tokens = {
  {
    file = 'palette.ts',
    language = 'typescript',
    expected_client = 'ts_ls',
    tokens = {
      { label = 'interface', needle = 'WebPalette', occurrence = 1 },
      { label = 'property', needle = 'accent', occurrence = 1 },
      { label = 'constant', needle = 'webPalette', occurrence = 1 },
      { label = 'function', needle = 'formatColor', occurrence = 1 },
      { label = 'parameter', needle = 'input', occurrence = 1 },
      { label = 'string', needle = '#ffb86c', occurrence = 1 },
    },
  },
  {
    file = 'palette.js',
    language = 'javascript',
    expected_client = 'ts_ls',
    tokens = {
      { label = 'constant', needle = 'webPalette', occurrence = 1 },
      { label = 'property', needle = 'accent', occurrence = 1 },
      { label = 'function', needle = 'formatColor', occurrence = 1 },
      { label = 'parameter', needle = 'input', occurrence = 1 },
      { label = 'string', needle = '#ffb86c', occurrence = 1 },
    },
  },
  {
    file = 'card.tsx',
    language = 'tsx',
    expected_client = 'ts_ls',
    tokens = {
      { label = 'type', needle = 'ColorCardProps', occurrence = 1 },
      { label = 'component', needle = 'ColorCard', occurrence = 1 },
      { label = 'builtin-tag', needle = 'section', occurrence = 1 },
      { label = 'attribute', needle = 'data-color', occurrence = 1 },
      { label = 'component-tag', needle = 'ColorSwatch', occurrence = 2 },
      { label = 'string', needle = 'peach', occurrence = 1 },
    },
  },
  {
    file = 'card.jsx',
    language = 'jsx',
    expected_client = 'ts_ls',
    tokens = {
      { label = 'component', needle = 'ColorCard', occurrence = 1 },
      { label = 'builtin-tag', needle = 'section', occurrence = 1 },
      { label = 'attribute', needle = 'data-color', occurrence = 1 },
      { label = 'string', needle = 'peach', occurrence = 1 },
    },
  },
  {
    file = 'card.html',
    language = 'html',
    expected_client = 'html',
    tokens = {
      { label = 'doctype', needle = 'doctype', occurrence = 1 },
      { label = 'tag', needle = 'main', occurrence = 1 },
      { label = 'attribute', needle = 'data-color', occurrence = 1 },
      { label = 'attribute-value', needle = 'peach', occurrence = 1 },
      { label = 'text', needle = 'Consistent color', occurrence = 1 },
    },
  },
}

local function read_file(path)
  local fd = assert(vim.uv.fs_open(path, 'r', 438))
  local stat = assert(vim.uv.fs_fstat(fd))
  local data = assert(vim.uv.fs_read(fd, stat.size, 0))
  assert(vim.uv.fs_close(fd))
  return data
end

local function hash_file(path) return vim.fn.sha256(read_file(path)) end

local function normalize_path(path)
  local replacements = {
    { vim.fn.stdpath 'config', '$NVIM_CONFIG' },
    { vim.fn.stdpath 'data', '$NVIM_DATA' },
    { vim.env.VIMRUNTIME, '$VIMRUNTIME' },
    { vim.env.HOME, '$HOME' },
  }

  for _, replacement in ipairs(replacements) do
    local prefix, name = unpack(replacement)
    if prefix and path:sub(1, #prefix) == prefix then return name .. path:sub(#prefix + 1) end
  end
  return path
end

local function system_line(command, cwd)
  local result = vim.system(command, { cwd = cwd, text = true }):wait()
  if result.code ~= 0 then return nil end
  return vim.trim(result.stdout)
end

local function stable_value(value)
  if type(value) ~= 'table' then return tostring(value) end
  local keys = vim.tbl_keys(value)
  table.sort(keys, function(left, right) return tostring(left) < tostring(right) end)
  local parts = {}
  for _, key in ipairs(keys) do
    parts[#parts + 1] = string.format('%s=%s', key, stable_value(value[key]))
  end
  return '{' .. table.concat(parts, '+') .. '}'
end

local function highlight_definition(group)
  if not group or group == '' then return 'none' end
  local definition = vim.api.nvim_get_hl(0, { name = group, link = false, create = false })
  if vim.tbl_isempty(definition) then return 'none' end

  local parts = {}
  for key, value in pairs(definition) do
    if key == 'fg' or key == 'bg' or key == 'sp' then value = string.format('#%06x', value) end
    parts[#parts + 1] = string.format('%s=%s', key, stable_value(value))
  end
  table.sort(parts)
  return table.concat(parts, ',')
end

local function screen_definition(attributes)
  local key_names = {
    foreground = 'fg',
    background = 'bg',
    special = 'sp',
  }
  local parts = {}
  for key, value in pairs(attributes) do
    local normalized_key = key_names[key] or key
    if key_names[key] then value = string.format('#%06x', value) end
    parts[#parts + 1] = string.format('%s=%s', normalized_key, stable_value(value))
  end
  table.sort(parts)
  return #parts > 0 and table.concat(parts, ',') or 'none'
end

function M.screen_render(buf, row, col)
  local win = vim.fn.bufwinid(buf)
  assert(win ~= -1, 'buffer must be visible to inspect its rendered color')
  vim.api.nvim_win_set_cursor(win, { row + 1, col })
  vim.cmd.redraw { bang = true }

  local position = vim.fn.screenpos(win, row + 1, col + 1)
  assert(position.row > 0 and position.col > 0, string.format('buffer position %d:%d is not visible', row + 1, col + 1))
  local cell = vim.api.nvim__inspect_cell(1, position.row - 1, position.col - 1)
  assert(type(cell[1]) == 'string' and type(cell[2]) == 'table', 'Neovim did not return a rendered grid cell')
  return {
    text = cell[1],
    definition = screen_definition(cell[2]),
  }
end

local function treesitter_priority(item)
  return item.metadata.priority or (item.metadata[item.id] and item.metadata[item.id].priority) or vim.hl.priorities.treesitter
end

local function contributor(layer, group, link, priority)
  return {
    layer = layer,
    group = group,
    link = link,
    priority = tonumber(priority) or 0,
    definition = highlight_definition(link),
  }
end

local function inspect_token(buf, row, col)
  local inspected = vim.inspect_pos(buf, row, col)
  local contributors = {}
  local function add(layer, group, link, priority) contributors[#contributors + 1] = contributor(layer, group, link, priority) end

  for _, item in ipairs(inspected.syntax) do
    add('syntax', item.hl_group, item.hl_group_link, 0)
  end
  for _, item in ipairs(inspected.treesitter) do
    add('treesitter', item.hl_group, item.hl_group_link, treesitter_priority(item))
  end
  for _, item in ipairs(inspected.semantic_tokens) do
    add('semantic_token', item.opts.hl_group, item.opts.hl_group_link, item.opts.priority)
  end
  for _, item in ipairs(inspected.extmarks) do
    if item.opts.hl_group then add('extmark', item.opts.hl_group, item.opts.hl_group_link, item.opts.priority or vim.hl.priorities.user) end
  end

  table.sort(contributors, function(left, right)
    if left.priority == right.priority then
      if left.layer == right.layer then return left.group < right.group end
      return left.layer < right.layer
    end
    return left.priority < right.priority
  end)

  local rendered_attributes = {}
  for _, item in ipairs(contributors) do
    if item.definition ~= 'none' then
      for part in item.definition:gmatch '[^,]+' do
        local key, value = part:match '^([^=]+)=(.*)$'
        rendered_attributes[key] = value
      end
    end
  end
  local rendered_parts = {}
  for key, value in pairs(rendered_attributes) do
    rendered_parts[#rendered_parts + 1] = key .. '=' .. value
  end
  table.sort(rendered_parts)
  local rendered = #rendered_parts > 0 and table.concat(rendered_parts, ',') or 'none'
  return contributors, rendered
end

local function find_token(buf, token)
  local matches = {}
  for row, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    local start = 1
    while true do
      local col = line:find(token.needle, start, true)
      if not col then break end
      matches[#matches + 1] = { row = row - 1, col = col - 1 }
      start = col + #token.needle
    end
  end

  local occurrence = token.occurrence or 1
  assert(matches[occurrence], string.format('could not find occurrence %d of %q', occurrence, token.needle))
  return matches[occurrence]
end

local function wait_for_highlighting(buf, expected_client, semantic_probe, file)
  local ready = vim.wait(5000, function()
    local highlighter = vim.treesitter.highlighter.active[buf]
    local clients = vim.lsp.get_clients { bufnr = buf, name = expected_client }
    return highlighter ~= nil and #clients > 0
  end, 20)
  local has_highlighter = vim.treesitter.highlighter.active[buf] ~= nil
  local clients = vim.lsp.get_clients { bufnr = buf, name = expected_client }
  assert(
    ready,
    string.format(
      'timed out waiting for Treesitter=%s and %s=%s in %s (filetype=%s)',
      has_highlighter,
      expected_client,
      #clients > 0,
      file,
      vim.bo[buf].filetype
    )
  )

  vim.lsp.semantic_tokens.force_refresh(buf)
  local semantic_ready = vim.wait(5000, function()
    local clients = vim.lsp.get_clients { bufnr = buf, name = expected_client }
    for _, client in ipairs(clients) do
      if next(client.requests) ~= nil then return false end
    end
    if expected_client ~= 'ts_ls' then return true end
    return #(vim.lsp.semantic_tokens.get_at_pos(buf, semantic_probe.row, semantic_probe.col) or {}) > 0
  end, 20)
  assert(semantic_ready, string.format('timed out waiting for semantic tokens from %s in %s', expected_client, file))
end

local function capture_tokens(fixture_root)
  local result = {}
  for _, fixture in ipairs(M.fixture_tokens) do
    local path = fixture_root .. '/' .. fixture.file
    vim.cmd.edit(vim.fn.fnameescape(path))
    local buf = vim.api.nvim_get_current_buf()
    if vim.bo[buf].filetype == '' then vim.cmd.setfiletype(assert(vim.filetype.match { filename = path, buf = buf })) end
    local positions = {}
    for _, token in ipairs(fixture.tokens) do
      positions[#positions + 1] = find_token(buf, token)
    end

    wait_for_highlighting(buf, fixture.expected_client, positions[1], fixture.file)

    local clients = vim.lsp.get_clients { bufnr = buf }
    local client_names = vim.tbl_map(function(client) return client.name end, clients)
    table.sort(client_names)

    for index, token in ipairs(fixture.tokens) do
      local position = positions[index]
      local contributors, resolved_stack = inspect_token(buf, position.row, position.col)
      local rendered = M.screen_render(buf, position.row, position.col)
      result[#result + 1] = {
        file = fixture.file,
        language = fixture.language,
        label = token.label,
        text = token.needle,
        row = position.row + 1,
        col = position.col + 1,
        clients = client_names,
        semantic_tokens_enabled = vim.lsp.semantic_tokens.is_enabled { bufnr = buf },
        contributors = contributors,
        resolved_stack = resolved_stack,
        rendered = rendered.definition,
        rendered_text = rendered.text,
      }
    end
  end
  return result
end

local function capture_plugins()
  local result = {}
  if not vim.pack or not vim.pack.get then return result end
  for _, plugin in ipairs(vim.pack.get(relevant_plugins, { info = false })) do
    result[#result + 1] = {
      name = plugin.spec.name,
      revision = plugin.rev,
      active = plugin.active,
    }
  end
  table.sort(result, function(left, right) return left.name < right.name end)
  return result
end

local function capture_parsers()
  local result = {}
  for _, language in ipairs(languages) do
    local paths = vim.api.nvim_get_runtime_file('parser/' .. language .. '.*', true)
    local entries = {}
    for _, path in ipairs(paths) do
      entries[#entries + 1] = { path = normalize_path(path), sha256 = hash_file(path) }
    end
    result[#result + 1] = { language = language, files = entries }
  end
  return result
end

local function capture_queries()
  local result = {}
  for _, language in ipairs(languages) do
    local entries = {}
    for _, path in ipairs(vim.api.nvim_get_runtime_file('queries/' .. language .. '/highlights.scm', true)) do
      entries[#entries + 1] = { path = normalize_path(path), sha256 = hash_file(path) }
    end
    result[#result + 1] = { language = language, files = entries }
  end
  return result
end

local function capture_mason_receipts()
  local result = {}
  local packages_root = vim.fn.stdpath 'data' .. '/mason/packages'
  for _, name in ipairs(relevant_mason_packages) do
    local path = packages_root .. '/' .. name .. '/mason-receipt.json'
    local stat = vim.uv.fs_stat(path)
    if stat then
      local receipt = vim.json.decode(read_file(path))
      result[#result + 1] = {
        name = name,
        source = receipt.source and receipt.source.id or 'unknown',
        registry = receipt.registry and receipt.registry.version or 'unknown',
        sha256 = hash_file(path),
      }
      if name == 'typescript-language-server' then
        local typescript_package = packages_root .. '/' .. name .. '/node_modules/typescript/package.json'
        if vim.uv.fs_stat(typescript_package) then
          local typescript = vim.json.decode(read_file(typescript_package))
          result[#result].typescript_version = typescript.version
          result[#result].typescript_sha256 = hash_file(typescript_package)
        end
      end
    else
      result[#result + 1] = { name = name, missing = true }
    end
  end
  return result
end

local function capture_config(nvim_root)
  local result = {}
  for _, path in ipairs {
    'colors/custom.lua',
    'nvim-pack-lock.json',
    'lua/kickstart/plugins/lsp.lua',
    'lua/kickstart/plugins/treesitter.lua',
  } do
    result[#result + 1] = { path = path, sha256 = hash_file(nvim_root .. '/' .. path) }
  end
  return result
end

function M.capture(nvim_root, fixture_root, typescript_root)
  local typescript_package = typescript_root .. '/node_modules/typescript/package.json'
  local tsserver_path = typescript_root .. '/node_modules/typescript/lib/tsserver.js'
  assert(vim.uv.fs_stat(typescript_package), 'project TypeScript package is missing: ' .. typescript_package)
  assert(vim.uv.fs_stat(tsserver_path), 'project TypeScript server is missing: ' .. tsserver_path)
  local typescript = vim.json.decode(read_file(typescript_package))
  vim.lsp.config('ts_ls', { init_options = { tsserver = { fallbackPath = tsserver_path } } })
  local headless_termguicolors = vim.o.termguicolors
  vim.o.termguicolors = true
  vim.cmd.colorscheme(vim.g.colors_name)

  return {
    schema_version = 1,
    environment = {
      repo_revision = system_line({ 'git', 'rev-parse', 'HEAD' }, vim.fs.dirname(nvim_root)),
      nvim = tostring(vim.version()),
      luajit = jit and jit.version or 'none',
      os = vim.uv.os_uname().sysname .. ' ' .. vim.uv.os_uname().machine,
      colors_name = vim.g.colors_name,
      headless_termguicolors = headless_termguicolors,
      render_mode = 'rgb-grid',
      background = vim.o.background,
      term = vim.env.TERM or '',
      colorterm = vim.env.COLORTERM or '',
      term_program = vim.env.TERM_PROGRAM or '',
    },
    artifacts = {
      config = capture_config(nvim_root),
      plugins = capture_plugins(),
      parsers = capture_parsers(),
      queries = capture_queries(),
      mason = capture_mason_receipts(),
      project_typescript = {
        version = typescript.version,
        package_sha256 = hash_file(typescript_package),
        tsserver_sha256 = hash_file(tsserver_path),
      },
    },
    tokens = capture_tokens(fixture_root),
  }
end

local function is_list(value)
  if type(value) ~= 'table' then return false end
  local count = 0
  for key in pairs(value) do
    if type(key) ~= 'number' then return false end
    count = count + 1
  end
  return count == #value
end

local function encode_json(value, depth)
  depth = depth or 0
  local kind = type(value)
  if kind ~= 'table' then return vim.json.encode(value) end

  local indent = string.rep('  ', depth)
  local child_indent = string.rep('  ', depth + 1)
  local parts = {}
  if is_list(value) then
    for _, item in ipairs(value) do
      parts[#parts + 1] = child_indent .. encode_json(item, depth + 1)
    end
    if #parts == 0 then return '[]' end
    return '[\n' .. table.concat(parts, ',\n') .. '\n' .. indent .. ']'
  end

  local keys = vim.tbl_keys(value)
  table.sort(keys)
  for _, key in ipairs(keys) do
    parts[#parts + 1] = child_indent .. vim.json.encode(key) .. ': ' .. encode_json(value[key], depth + 1)
  end
  if #parts == 0 then return '{}' end
  return '{\n' .. table.concat(parts, ',\n') .. '\n' .. indent .. '}'
end

function M.write(path, snapshot) vim.fn.writefile(vim.split(encode_json(snapshot), '\n', { plain = true }), path) end

function M.read(path) return vim.json.decode(read_file(path)) end

local function diff_values(left, right, path, differences)
  if type(left) ~= type(right) then
    differences[#differences + 1] = string.format('%s: %s != %s', path, type(left), type(right))
    return
  end
  if type(left) ~= 'table' then
    if left ~= right then differences[#differences + 1] = string.format('%s: %s != %s', path, tostring(left), tostring(right)) end
    return
  end

  local keys = {}
  for key in pairs(left) do
    keys[key] = true
  end
  for key in pairs(right) do
    keys[key] = true
  end
  local sorted = vim.tbl_keys(keys)
  table.sort(sorted, function(a, b) return tostring(a) < tostring(b) end)
  for _, key in ipairs(sorted) do
    local child_path = type(key) == 'number' and string.format('%s[%d]', path, key) or path .. '.' .. key
    if left[key] == nil or right[key] == nil then
      differences[#differences + 1] = child_path .. ': missing on one side'
    else
      diff_values(left[key], right[key], child_path, differences)
    end
  end
end

function M.compare(left, right)
  local color_differences = {}
  local evidence_differences = {}
  local left_colors, right_colors = {}, {}
  for index, token in ipairs(left.tokens) do
    left_colors[index] = { file = token.file, label = token.label, rendered = token.rendered }
  end
  for index, token in ipairs(right.tokens) do
    right_colors[index] = { file = token.file, label = token.label, rendered = token.rendered }
  end
  diff_values(left_colors, right_colors, 'colors', color_differences)
  diff_values(left, right, 'snapshot', evidence_differences)
  return color_differences, evidence_differences
end

function M.summary(snapshot)
  local lines = {
    string.format(
      'Neovim %s | colorscheme=%s | render_mode=%s | headless_termguicolors=%s',
      snapshot.environment.nvim,
      snapshot.environment.colors_name,
      snapshot.environment.render_mode,
      tostring(snapshot.environment.headless_termguicolors)
    ),
  }
  for _, token in ipairs(snapshot.tokens) do
    lines[#lines + 1] = string.format('%-10s %-16s %-16s %s', token.language, token.file, token.label, token.rendered)
  end
  return lines
end

return M
