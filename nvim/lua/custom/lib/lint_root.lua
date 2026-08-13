local M = {}

-- Keep all supported ESLint config names at equal priority so the nearest
-- config wins regardless of whether a project uses flat or legacy config.
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

---@param source integer|string Buffer number or file path
---@return string?
function M.eslint_root(source) return vim.fs.root(source, eslint_config_markers) end

return M
