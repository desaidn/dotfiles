local failures = {}
local script_path = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p')
local nvim_root = vim.fs.normalize(vim.fs.dirname(script_path) .. '/../..')

package.path = table.concat({ nvim_root .. '/lua/?.lua', nvim_root .. '/lua/?/init.lua', package.path }, ';')

local function check(name, body)
  local ok, err = pcall(body)
  if ok then
    io.stdout:write('PASS ', name, '\n')
    return
  end
  failures[#failures + 1] = name
  io.stderr:write('FAIL ', name, '\n  ', tostring(err):gsub('\n', '\n  '), '\n')
end

local original_pack_add = vim.pack.add
local original_autocmd = vim.api.nvim_create_autocmd
local original_dap = package.loaded['custom.languages.dap']
local original_context = package.loaded['custom.languages.context']
local original_jdtls = package.loaded.jdtls
local original_registry = package.loaded['mason-registry']
local original_jvm_args = vim.env.JDTLS_JVM_ARGS
local package_spec
local java_autocmd
local registered_dap
local started
local starts = {}
local trace = {}
local fixture = vim.fn.tempname()
local debug_prefix = fixture .. '/java-debug-adapter'
local test_prefix = fixture .. '/java-test'
local gradle_root = fixture .. '/gradle'
local gradle_module = gradle_root .. '/module'
local maven_root = fixture .. '/maven'
local maven_module = maven_root .. '/module'
local standalone_root = fixture .. '/standalone'

assert(vim.fn.mkdir(debug_prefix .. '/extension/server', 'p') == 1, 'failed to create Java debug fixture')
assert(vim.fn.mkdir(test_prefix .. '/extension/server', 'p') == 1, 'failed to create Java test fixture')
assert(vim.fn.mkdir(gradle_module .. '/src/main/java', 'p') == 1, 'failed to create Gradle fixture')
assert(vim.fn.mkdir(maven_module .. '/src/main/java', 'p') == 1, 'failed to create Maven fixture')
assert(vim.fn.mkdir(standalone_root .. '/src/main/java', 'p') == 1, 'failed to create standalone fixture')
for _, path in ipairs {
  debug_prefix .. '/extension/server/com.microsoft.java.debug.plugin-0.53.2.jar',
  test_prefix .. '/extension/server/com.microsoft.java.test.plugin-0.43.1.jar',
  test_prefix .. '/extension/server/junit-jupiter-api.jar',
  test_prefix .. '/extension/server/com.microsoft.java.test.runner-jar-with-dependencies.jar',
  test_prefix .. '/extension/server/jacocoagent.jar',
} do
  assert(vim.fn.writefile({}, path) == 0, 'failed to create fixture jar')
end
assert(vim.fn.writefile({}, gradle_root .. '/gradlew') == 0, 'failed to create Gradle wrapper')
assert(vim.fn.writefile({}, gradle_module .. '/build.gradle') == 0, 'failed to create Gradle module')
assert(vim.fn.writefile({ '<project>', '  <modules>', '    <module>module</module>', '  </modules>', '</project>' }, maven_root .. '/pom.xml') == 0)
assert(vim.fn.writefile({ '<project />' }, maven_module .. '/pom.xml') == 0)
assert(vim.fn.writefile({ '<project />' }, standalone_root .. '/pom.xml') == 0)

vim.pack.add = function(spec) package_spec = spec end
vim.api.nvim_create_autocmd = function(event, opts)
  if event == 'FileType' then java_autocmd = opts end
  return 1
end
package.loaded['custom.languages.dap'] = {
  ensure = function() trace[#trace + 1] = 'dap' end,
  register_project = function(filetype, config) registered_dap = { filetype = filetype, config = config } end,
}
package.loaded['custom.languages.context'] = {
  for_buffer = function(bufnr, profile)
    local projects = {
      [42] = { root = '/work/alpha/service', path = '/work/alpha/service/src/Main.java' },
      [43] = { root = '/work/alpha/service', path = '/work/alpha/service/src/Other.java' },
      [44] = { root = '/work/beta/service', path = '/work/beta/service/src/Main.java' },
    }
    local project = assert(projects[bufnr], 'unexpected buffer')
    project.profile = profile
    return project
  end,
  workspace_data = function(consumer, root)
    assert(consumer == 'jdtls')
    return '/cache/jdtls/' .. vim.fs.basename(root) .. '-' .. vim.fn.sha256(root):sub(1, 12)
  end,
}
package.loaded['mason-registry'] = {
  get_package = function(name)
    return {
      get_install_path = function()
        if name == 'java-debug-adapter' then return debug_prefix end
        assert(name == 'java-test')
        return test_prefix
      end,
    }
  end,
}
package.loaded.jdtls = {
  start_or_attach = function(config, opts, start_opts)
    trace[#trace + 1] = 'jdtls'
    started = { config = config, opts = opts, start_opts = start_opts }
    starts[#starts + 1] = started
  end,
}
vim.env.JDTLS_JVM_ARGS = '-Xmx2G -javaagent:/tmp/lombok.jar'

local ok, adapter_or_err = xpcall(function() return dofile(nvim_root .. '/lua/custom/languages/adapters/java.lua') end, debug.traceback)

check('adds nvim-jdtls and keeps Java DAP routing in the Java adapter', function()
  assert(ok, adapter_or_err)
  assert(package_spec and package_spec[1].src == 'https://github.com/mfussenegger/nvim-jdtls', 'missing nvim-jdtls package')
  assert(registered_dap.filetype == 'java')
  assert(registered_dap.config.lsp_client == 'jdtls')
  assert(vim.deep_equal(registered_dap.config.launch_types, { 'java' }))
end)

check('prefers a Gradle workspace root over a nested module', function()
  local source = gradle_module .. '/src/main/java/Main.java'
  assert(vim.fn.writefile({}, source) == 0, 'failed to create Java source fixture')
  assert(ok and adapter_or_err.root_profile.resolve(source) == gradle_root)
end)

check('uses the Maven reactor rather than a nested module', function()
  local source = maven_module .. '/src/main/java/Main.java'
  assert(vim.fn.writefile({}, source) == 0, 'failed to create Java source fixture')
  assert(ok and adapter_or_err.root_profile.resolve(source) == maven_root)
end)

check('uses an isolated module when no Java workspace marker exists', function()
  local source = standalone_root .. '/src/main/java/Main.java'
  assert(vim.fn.writefile({}, source) == 0, 'failed to create Java source fixture')
  assert(ok and adapter_or_err.root_profile.resolve(source) == standalone_root)
end)

check('uses one JDTLS identity per root and isolates same-basename roots', function()
  trace = {}
  starts = {}
  for _, bufnr in ipairs { 42, 43, 44 } do
    java_autocmd.callback { buf = bufnr }
  end
  assert(#starts == 3)
  assert(starts[1].config.root_dir == starts[2].config.root_dir)
  assert(starts[1].config.cmd[3] == starts[2].config.cmd[3])
  assert(starts[1].config.root_dir ~= starts[3].config.root_dir)
  assert(starts[1].config.cmd[3] ~= starts[3].config.cmd[3])
end)

check('starts JDTLS after DAP with isolated data and valid Mason bundles', function()
  local cwd = vim.fn.getcwd()
  trace = {}
  assert(java_autocmd and java_autocmd.pattern == 'java', 'missing Java FileType lifecycle')
  java_autocmd.callback { buf = 42 }
  assert(vim.deep_equal(trace, { 'dap', 'jdtls' }), vim.inspect(trace))
  assert(started.config.root_dir == '/work/alpha/service')
  assert(
    vim.deep_equal(started.config.cmd, {
      'jdtls',
      '-data',
      '/cache/jdtls/service-' .. vim.fn.sha256('/work/alpha/service'):sub(1, 12),
      '--jvm-arg=-Xmx2G',
      '--jvm-arg=-javaagent:/tmp/lombok.jar',
    }),
    vim.inspect(started.config.cmd)
  )
  assert(
    vim.deep_equal(started.config.init_options.bundles, {
      debug_prefix .. '/extension/server/com.microsoft.java.debug.plugin-0.53.2.jar',
      test_prefix .. '/extension/server/com.microsoft.java.test.plugin-0.43.1.jar',
      test_prefix .. '/extension/server/junit-jupiter-api.jar',
    }),
    vim.inspect(started.config.init_options.bundles)
  )
  assert(started.opts.dap ~= nil, 'nvim-jdtls DAP integration must be enabled')
  assert(started.start_opts.bufnr == 42)
  assert(vim.fn.getcwd() == cwd, 'Java startup must not mutate Neovim cwd')

  local client = {
    server_capabilities = {
      documentFormattingProvider = true,
      documentRangeFormattingProvider = true,
    },
  }
  started.config.on_attach(client)
  assert(client.server_capabilities.documentFormattingProvider == false)
  assert(client.server_capabilities.documentRangeFormattingProvider == false)
end)

vim.pack.add = original_pack_add
vim.api.nvim_create_autocmd = original_autocmd
package.loaded['custom.languages.dap'] = original_dap
package.loaded['custom.languages.context'] = original_context
package.loaded.jdtls = original_jdtls
package.loaded['mason-registry'] = original_registry
vim.env.JDTLS_JVM_ARGS = original_jvm_args
vim.fn.delete(fixture, 'rf')

if #failures > 0 then error(string.format('%d Java configuration check(s) failed: %s', #failures, table.concat(failures, ', '))) end
io.stdout:write 'All Java configuration checks passed.\n'
