vim.cmd.highlight 'clear'
vim.g.colors_name = 'custom'

-- Load default colorscheme as base
vim.cmd.runtime 'colors/default.lua'

local colors = {
  white = '#ffffff', -- text, tag attributes
  peach = '#ffb86c', -- accent, tags, functions, statusline insert mode
  blue = '#a6dbff', -- statusline normal mode
  green = '#b4f6c0', -- statusline command mode
  -- Good alternative(s):
  -- yellow = '#5f5a2a', -- - Less saturated, blends nicely with syntax colors.
  yellow = '#6a4f1f', -- muted highlighter-style search and visual selection
  grey = '#7a8a9e', -- tag delimiters
  charcoal = '#2a2e38', -- floats, statusline, popups
  midnight = '#1e1e2e', -- statusline foreground
  light_green = '#2e5e3e', -- diff additions
  dark_green = '#1e3d2a', -- diff changes
  mid_green = '#2a4d35', -- diff changed text
  dark_red = '#3d1e1e', -- diff deletions
}

-- Transparent backgrounds
local transparent_groups = {
  'Normal',
  'NormalNC',
  'SignColumn',
  'EndOfBuffer',
  'WinBar',
  'WinBarNC',
  'CursorLine',
  'CursorColumn',
  'ColorColumn',
  'Folded',
  'NormalFloat',
  'FloatBorder',
  'Pmenu',
  'PmenuSbar',
  'TelescopeNormal',
  'TelescopeBorder',
  'WhichKeyFloat',
  'TabLineFill',
}

for _, group in ipairs(transparent_groups) do
  local hl = vim.api.nvim_get_hl(0, { name = group })
  vim.api.nvim_set_hl(0, group, vim.tbl_extend('force', hl, { bg = 'NONE' }))
end

-- Accent color
local accent_groups = {
  'Function',
  'Special',
  'Changed',
  'MoreMsg',
  'Question',
  'Directory',
  'QuickFixLine',
  'DiagnosticInfo',
}

for _, group in ipairs(accent_groups) do
  local hl = vim.api.nvim_get_hl(0, { name = group })
  vim.api.nvim_set_hl(0, group, vim.tbl_extend('force', hl, { fg = colors.peach }))
end

-- Diff colors
vim.api.nvim_set_hl(0, 'DiffAdd', { bg = colors.light_green })
vim.api.nvim_set_hl(0, 'DiffChange', { bg = colors.dark_green })
vim.api.nvim_set_hl(0, 'DiffDelete', { bg = colors.dark_red })
vim.api.nvim_set_hl(0, 'DiffText', { bg = colors.mid_green, fg = colors.white })
vim.api.nvim_set_hl(0, 'DiffTextAdd', { bg = colors.light_green, fg = colors.white })

-- Keep search matches and visual selection consistently yellow-ish without overriding syntax foregrounds.
local selection = { bg = colors.yellow }
for _, group in ipairs { 'Search', 'IncSearch', 'CurSearch', 'Visual', 'VisualNOS' } do
  vim.api.nvim_set_hl(0, group, selection)
end

-- Popup menu border (used when pumborder = 'rounded')
vim.api.nvim_set_hl(0, 'PmenuBorder', { fg = colors.grey, bg = 'NONE' })

-- Statusline background (matches float windows)
vim.api.nvim_set_hl(0, 'StatusLine', { bg = colors.charcoal })
vim.api.nvim_set_hl(0, 'StatusLineNC', { bg = colors.charcoal })

-- Sticky treesitter context background
vim.api.nvim_set_hl(0, 'TreesitterContext', { bg = colors.charcoal })
vim.api.nvim_set_hl(0, 'TreesitterContextLineNumber', { fg = colors.grey, bg = colors.charcoal })
vim.api.nvim_set_hl(0, 'TreesitterContextBottom', { bg = colors.charcoal, underline = true, sp = colors.grey })
vim.api.nvim_set_hl(0, 'TreesitterContextLineNumberBottom', { fg = colors.grey, bg = colors.charcoal, underline = true, sp = colors.grey })

-- Markup tag colors (HTML, XML, JSX, TSX)
vim.api.nvim_set_hl(0, '@tag', { fg = colors.peach })
vim.api.nvim_set_hl(0, '@tag.builtin', { fg = colors.peach })
vim.api.nvim_set_hl(0, '@tag.delimiter', { fg = colors.grey })
vim.api.nvim_set_hl(0, '@tag.attribute', { fg = colors.white, italic = true })

-- Tabline
vim.api.nvim_set_hl(0, 'TabLineSel', { fg = colors.white, bg = colors.charcoal, bold = true })
vim.api.nvim_set_hl(0, 'TabLine', { fg = colors.grey, bg = 'NONE' })

-- Mini statusline mode colors
vim.api.nvim_set_hl(0, 'MiniStatuslineModeNormal', { fg = colors.midnight, bg = colors.blue, bold = true })
vim.api.nvim_set_hl(0, 'MiniStatuslineModeInsert', { fg = colors.midnight, bg = colors.peach, bold = true })
vim.api.nvim_set_hl(0, 'MiniStatuslineModeCommand', { fg = colors.midnight, bg = colors.green, bold = true })
