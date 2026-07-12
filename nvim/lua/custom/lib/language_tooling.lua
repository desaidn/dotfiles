local M = {}

local options_fields = { languages = true }
local language_fields = {
  name = true,
  lsps = true,
  tools = true,
  filetypes = true,
  formatters = true,
  linters = true,
}
local lsp_fields = { server = true, install = true }

---@param value unknown
---@return boolean
local function is_plain_table(value) return type(value) == 'table' and getmetatable(value) == nil end

---@param value table
---@param allowed_fields table<string, boolean>
---@param context string
local function validate_fields(value, allowed_fields, context)
  for field in pairs(value) do
    if not allowed_fields[field] then error(string.format('%s has unknown field %q', context, tostring(field)), 3) end
  end
end

---@generic T: table
---@param value T
---@return T
local function copy_table(value)
  local copied = {}
  for key, item in pairs(value) do
    copied[key] = type(item) == 'table' and copy_table(item) or item
  end
  return copied
end

---@param value unknown
---@return boolean
local function is_array(value)
  if not is_plain_table(value) then return false end

  local count = 0
  local max_key = 0
  for key in pairs(value) do
    if type(key) ~= 'number' or key < 1 or key % 1 ~= 0 then return false end
    count = count + 1
    if key > max_key then max_key = key end
  end
  return count == max_key
end

---@param value unknown
---@return boolean
local function is_formatter_list(value)
  if not is_plain_table(value) then return false end

  local count = 0
  local max_key = 0
  for key, item in pairs(value) do
    if key == 'stop_after_first' then
      if type(item) ~= 'boolean' then return false end
    else
      if type(key) ~= 'number' or key < 1 or key % 1 ~= 0 then return false end
      count = count + 1
      if key > max_key then max_key = key end
    end
  end
  return count == max_key
end

---@class (exact) LanguageToolingLsp
---@field server string nvim-lspconfig server name.
---@field install? string Mason package name; defaults to `server`.

---An ordered Conform formatter chain with the inventory-owned fallback policy.
---@class (exact) LanguageToolingFormatterList
---@field [integer] string
---@field stop_after_first? boolean

---@class (exact) LanguageToolingLanguage
---@field name string Stable Language Family name used in validation errors.
---@field lsps? LanguageToolingLsp[] Ordered LSP declarations for this family.
---@field tools? string[] Ordered non-LSP Mason package names.
---@field filetypes? string[] Filetypes that share this family's formatter and linter declarations.
---@field formatters? LanguageToolingFormatterList Ordered formatter chain; no plugin metadata other than `stop_after_first` is accepted.
---@field linters? string[] Native nvim-lint linter names.

---@class (exact) LanguageToolingOptions
---@field languages LanguageToolingLanguage[]

---@class (exact) LanguageTooling
---@field lsp_servers fun(): string[] Ordered nvim-lspconfig server names.
---@field mason_tools fun(): string[] Ordered, first-seen-deduplicated Mason package names.
---@field formatters_by_ft fun(): table<string, LanguageToolingFormatterList> Conform's native filetype map.
---@field linters_by_ft fun(): table<string, string[]> nvim-lint's native filetype map.

---@param options LanguageToolingOptions
---@return LanguageTooling
function M.create(options)
  if not is_plain_table(options) then error('Language Tooling options must be a plain table', 2) end
  validate_fields(options, options_fields, 'Language Tooling options')
  if not is_array(options.languages) then error('languages must be a plain table containing an ordered array', 2) end

  local languages = options.languages
  local filetype_owners = {}
  local language_names = {}

  for index, language in ipairs(languages) do
    if not is_plain_table(language) then error(string.format('Language Family #%d must be a plain table', index), 2) end
    if type(language.name) ~= 'string' or language.name == '' then error(string.format('Language Family #%d must declare a non-empty name', index), 2) end
    validate_fields(language, language_fields, string.format('Language Family %q', language.name))
    if language_names[language.name] then error(string.format('duplicate Language Family name %q', language.name), 2) end
    language_names[language.name] = true
    if language.lsps ~= nil and not is_array(language.lsps) then
      error(string.format('Language Family %q lsps must be a plain table containing an ordered array', language.name), 2)
    end
    for lsp_index, lsp in ipairs(language.lsps or {}) do
      if not is_plain_table(lsp) then error(string.format('Language Family %q LSP #%d must be a plain table', language.name, lsp_index), 2) end
      validate_fields(lsp, lsp_fields, string.format('Language Family %q LSP #%d', language.name, lsp_index))
      if type(lsp.server) ~= 'string' or lsp.server == '' then
        error(string.format('Language Family %q LSP #%d must declare a non-empty server', language.name, lsp_index), 2)
      end
      if lsp.install ~= nil and (type(lsp.install) ~= 'string' or lsp.install == '') then
        error(string.format('Language Family %q LSP #%d install must be a non-empty string', language.name, lsp_index), 2)
      end
    end
    if language.tools ~= nil and not is_array(language.tools) then
      error(string.format('Language Family %q tools must be a plain table containing an ordered array', language.name), 2)
    end
    for tool_index, tool in ipairs(language.tools or {}) do
      if type(tool) ~= 'string' or tool == '' then
        error(string.format('Language Family %q install tool #%d must be a non-empty string', language.name, tool_index), 2)
      end
    end
    if language.filetypes ~= nil and not is_array(language.filetypes) then
      error(string.format('Language Family %q filetypes must be a plain table containing an ordered array', language.name), 2)
    end
    for filetype_index, filetype in ipairs(language.filetypes or {}) do
      if type(filetype) ~= 'string' or filetype == '' then
        error(string.format('Language Family %q filetypes #%d must be a non-empty string', language.name, filetype_index), 2)
      end
    end
    if language.formatters ~= nil and not is_formatter_list(language.formatters) then
      error(
        string.format('Language Family %q formatters must be a plain table containing an ordered list with optional boolean stop_after_first', language.name),
        2
      )
    end
    for formatter_index, formatter in ipairs(language.formatters or {}) do
      if type(formatter) ~= 'string' or formatter == '' then
        error(string.format('Language Family %q formatters #%d must be a non-empty string', language.name, formatter_index), 2)
      end
    end
    if language.linters ~= nil and not is_array(language.linters) then
      error(string.format('Language Family %q linters must be a plain table containing an ordered array', language.name), 2)
    end
    for linter_index, linter in ipairs(language.linters or {}) do
      if type(linter) ~= 'string' or linter == '' then
        error(string.format('Language Family %q linters #%d must be a non-empty string', language.name, linter_index), 2)
      end
    end
    if language.formatters or language.linters then
      if not language.filetypes or #language.filetypes == 0 then
        error(string.format('Language Family %q must declare filetypes when it declares formatters or linters', language.name), 2)
      end
      for _, filetype in ipairs(language.filetypes) do
        local owner = filetype_owners[filetype]
        if owner then error(string.format('filetype %q is owned by both Language Families %q and %q', filetype, owner, language.name), 2) end
        filetype_owners[filetype] = language.name
      end
    end
  end

  languages = copy_table(languages)

  return {
    lsp_servers = function()
      local servers = {}
      for _, language in ipairs(languages) do
        for _, lsp in ipairs(language.lsps or {}) do
          servers[#servers + 1] = lsp.server
        end
      end
      return servers
    end,
    mason_tools = function()
      local tools = {}
      local seen = {}

      local function append(tool)
        if seen[tool] then return end
        seen[tool] = true
        tools[#tools + 1] = tool
      end

      for _, language in ipairs(languages) do
        for _, lsp in ipairs(language.lsps or {}) do
          append(lsp.install or lsp.server)
        end
        for _, tool in ipairs(language.tools or {}) do
          append(tool)
        end
      end

      return tools
    end,
    formatters_by_ft = function()
      local formatters_by_ft = {}
      for _, language in ipairs(languages) do
        if language.formatters then
          for _, filetype in ipairs(language.filetypes or {}) do
            formatters_by_ft[filetype] = copy_table(language.formatters)
          end
        end
      end
      return formatters_by_ft
    end,
    linters_by_ft = function()
      local linters_by_ft = {}
      for _, language in ipairs(languages) do
        if language.linters then
          for _, filetype in ipairs(language.filetypes or {}) do
            linters_by_ft[filetype] = copy_table(language.linters)
          end
        end
      end
      return linters_by_ft
    end,
  }
end

return M
