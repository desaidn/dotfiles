-- nvim-jdtls owns Java's project lifecycle and its JDT-specific DAP surface.

local gh = require('custom.lib.pack').gh
local capabilities = require 'custom.languages.capabilities'
local context = require 'custom.languages.context'
local dap = require 'custom.languages.dap'

local workspace_markers = { 'gradlew', 'gradlew.bat', 'settings.gradle', 'settings.gradle.kts', 'mvnw', 'mvnw.cmd' }
local module_markers = { 'build.gradle', 'build.gradle.kts', 'pom.xml' }

local function maven_reactor_root(path)
  local directory = vim.fs.dirname(path)
  while directory do
    local pom = vim.fs.joinpath(directory, 'pom.xml')
    if vim.uv.fs_stat(pom) then
      local xml = table.concat(vim.fn.readfile(pom), '\n'):gsub('<!%-%-.-%-%->', '')
      if xml:find '<modules%s*>' then return directory end
    end
    local parent = vim.fs.dirname(directory)
    if parent == directory then return nil end
    directory = parent
  end
end

local function java_root(path)
  return vim.fs.root(path, workspace_markers) or maven_reactor_root(path) or vim.fs.root(path, module_markers) or vim.fs.root(path, { '.git' })
end

local root_profile = {
  markers = { workspace_markers, module_markers, '.git' },
  resolve = java_root,
}

local function jdtls_command(root)
  local command = { 'jdtls', '-data', context.workspace_data('jdtls', root) }
  for argument in (vim.env.JDTLS_JVM_ARGS or ''):gmatch '%S+' do
    command[#command + 1] = '--jvm-arg=' .. argument
  end
  return command
end

local excluded_test_jars = {
  ['com.microsoft.java.test.runner-jar-with-dependencies.jar'] = true,
  ['jacocoagent.jar'] = true,
}

local function mason_path(package_name) return require('mason-registry').get_package(package_name):get_install_path() end

local function bundles()
  local debug_pattern = vim.fs.joinpath(mason_path 'java-debug-adapter', 'extension', 'server', 'com.microsoft.java.debug.plugin*.jar')
  local result = vim.fn.glob(debug_pattern, false, true)
  local test_pattern = vim.fs.joinpath(mason_path 'java-test', 'extension', 'server', '*.jar')
  for _, path in ipairs(vim.fn.glob(test_pattern, false, true)) do
    if not excluded_test_jars[vim.fs.basename(path)] then result[#result + 1] = path end
  end
  return result
end

dap.register_project('java', {
  lsp_client = 'jdtls',
  root_profile = root_profile,
  launch_types = { 'java' },
})

vim.pack.add { { src = gh 'mfussenegger/nvim-jdtls' } }

vim.api.nvim_create_autocmd('FileType', {
  group = vim.api.nvim_create_augroup('java-jdtls', { clear = true }),
  pattern = 'java',
  callback = function(event)
    local project = context.for_buffer(event.buf, root_profile)
    if not project then return end

    -- nvim-jdtls registers the Java adapter and generated-main provider only
    -- when nvim-dap is already loaded.
    dap.ensure()
    require('jdtls').start_or_attach({
      cmd = jdtls_command(project.root),
      root_dir = project.root,
      init_options = { bundles = bundles() },
      on_attach = capabilities.disable_formatting,
    }, { dap = {} }, { bufnr = event.buf })
  end,
})

return { root_profile = root_profile }
