-- The checks: `nvim --headless -u NONE -i NONE --cmd "set rtp^=." -l tests/check.lua`
-- (from the repository's root). Each colorscheme loads; every group it sets
-- reads clearly (text 4.5:1, lines 3:1, against what it is drawn on); the
-- lualine themes too; the terminal has 16 colours; following 'background'
-- switches the variant once, not in a loop.
local failures, checks = {}, 0
local function check(ok, what)
  checks = checks + 1
  if not ok then
    table.insert(failures, what)
  end
end

local function lum(hex)
  local function lin(v)
    v = v / 255
    return v <= 0.03928 and v / 12.92 or ((v + 0.055) / 1.055) ^ 2.4
  end
  local r, g, b = tonumber(hex:sub(2, 3), 16), tonumber(hex:sub(4, 5), 16), tonumber(hex:sub(6, 7), 16)
  return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
end
local function ratio(a, b)
  local x, y = lum(a), lum(b)
  if x < y then
    x, y = y, x
  end
  return (x + 0.05) / (y + 0.05)
end
-- A table's keys in order, so the report is the same from run to run.
local function sorted(t)
  local keys = vim.tbl_keys(t)
  table.sort(keys)
  return keys
end
local function hex(n)
  return n and string.format("#%06x", n) or nil
end

-- Decoration that only has to show: the thinnest lines.
local seen_only = {
  EndOfBuffer = true, Whitespace = true, WinSeparator = true, VertSplit = true, SnacksIndent = true,
}
-- Lines and marks, not reading text: 3:1.
local lines = {
  LineNr = true, LineNrAbove = true, LineNrBelow = true, SignColumn = true, FoldColumn = true,
  NonText = true, SpecialKey = true, FloatBorder = true, SnacksIndentScope = true, LazyProgressTodo = true,
  Ignore = true, SnacksNotifierBorderDebug = true, SnacksNotifierBorderTrace = true,
}
-- Bars with no text on them: only seen against what is around them.
local bars = { PmenuThumb = true, PmenuSbar = true }
-- The group a link ends at: a border linked to FloatBorder is a line too.
local function root(group)
  for _ = 1, 10 do
    local link = vim.api.nvim_get_hl(0, { name = group }).link
    if not link then
      return group
    end
    group = link
  end
  return group
end

local paper = require("paper")

-- Every colour the groups and the lualine theme name is in both palettes:
-- a missing one would be nil, and the group silently without it.
for _, file in ipairs({ "lua/paper/groups.lua", "lua/paper/lualine.lua" }) do
  local path = vim.api.nvim_get_runtime_file(file, false)[1]
  local used = {}
  for key in table.concat(vim.fn.readfile(path), "\n"):gmatch("c%.([%a_][%w_]*)") do
    used[key] = true
  end
  for _, key in ipairs(sorted(used)) do
    for _, style in ipairs({ "dark", "light" }) do
      check(paper.palette(style)[key] ~= nil, string.format("%s: c.%s is not in the %s palette", file, key, style))
    end
  end
end

for _, name in ipairs({ "paper", "paper-dark" }) do
  local ok, err = pcall(vim.cmd.colorscheme, name)
  check(ok, name .. ": loads (" .. tostring(err) .. ")")
  check(vim.g.colors_name == name, name .. ": colors_name is " .. tostring(vim.g.colors_name))
  local style = name == "paper" and "light" or "dark"
  check(vim.o.background == style, name .. ": background is " .. vim.o.background)
  for i = 0, 15 do
    check(type(vim.g["terminal_color_" .. i]) == "string", name .. ": terminal_color_" .. i)
  end

  local normal = vim.api.nvim_get_hl(0, { name = "Normal" })
  local base_fg, base_bg = hex(normal.fg), hex(normal.bg)
  check(base_fg and base_bg, name .. ": Normal has fg and bg")
  local groups = require("paper.groups").get(paper.palette(style), paper.config)
  local measured = 0
  for _, group in ipairs(sorted(groups)) do
    local spec = vim.api.nvim_get_hl(0, { name = group, link = false })
    local fg, bg = hex(spec.fg), hex(spec.bg) or base_bg
    if spec.reverse then
      fg, bg = bg, fg or base_fg
    end
    -- A group with a background and no colour of its own draws Normal's
    -- text on it (CursorLine, Visual, Search's wash, a diff line).
    if not fg and spec.bg then
      fg = base_fg
    end
    local base = root(group)
    if bars[base] then
      -- The thumb against its track, and the track against the menu.
      fg, bg = hex(spec.bg), base == "PmenuThumb" and hex(vim.api.nvim_get_hl(0, { name = "PmenuSbar" }).bg) or hex(vim.api.nvim_get_hl(0, { name = "Pmenu" }).bg)
    end
    if fg and bg then
      measured = measured + 1
      local need = (seen_only[base] or bars[base]) and 1.15 or lines[base] and 3 or 4.5
      local r = ratio(fg, bg)
      check(r >= need, string.format("%s: %s %s on %s is %.2f:1 (needs %.2f)", name, group, fg, bg, r, need))
    end
  end
  check(measured > 250, name .. ": measured " .. measured .. " groups")
  print(string.format("%s: %d groups measured", name, measured))

  local theme = dofile(vim.api.nvim_get_runtime_file("lua/lualine/themes/" .. name .. ".lua", false)[1])
  for _, mode in ipairs(sorted(theme)) do
    local sections = theme[mode]
    for _, section in ipairs(sorted(sections)) do
      local s = sections[section]
      local r = ratio(s.fg, s.bg)
      check(r >= 4.5, string.format("%s: lualine %s.%s %s on %s is %.2f:1", name, mode, section, s.fg, s.bg, r))
    end
  end
end

-- A style that is neither: said so, and nothing changed.
vim.cmd.colorscheme("paper-dark")
local ok_night, err_night = pcall(paper.load, "night")
check(not ok_night and tostring(err_night):find('load%("dark"%) or load%("light"%), not "night"') ~= nil, "load: a wrong style is named (" .. tostring(err_night) .. ")")
check(vim.g.colors_name == "paper-dark", "load: a wrong style leaves the scheme as it was")

-- Transparent: the editor leaves its background to the terminal.
paper.setup({ transparent = true })
vim.cmd.colorscheme("paper-dark")
check(vim.api.nvim_get_hl(0, { name = "Normal" }).bg == nil, "transparent: Normal has no bg")
paper.setup({ transparent = false })

-- Following 'background' (auto): a change by hand switches the variant,
-- once; loading itself does not count as a change.
local loads = 0
local load = paper.load
paper.load = function(style)
  loads = loads + 1
  return load(style)
end
-- The system, as the test says it is: known at once, and asked later.
paper.state_file = vim.fn.tempname()
local known, answer = "dark", nil
local asked = 0
paper.now = function()
  return known
end
paper.system_async = function(cb)
  asked = asked + 1
  cb(answer)
end
paper.auto()
check(vim.g.colors_name == "paper-dark", "auto: the system's dark gives paper-dark")
-- The answer that comes later: the same, nothing drawn again; turned, the
-- other variant, and kept for the next start.
loads = 0
answer = "dark"
vim.api.nvim_exec_autocmds("FocusGained", {})
check(asked == 2 and loads == 0, "auto: the focus asks again; the same answer draws nothing (" .. asked .. ", " .. loads .. ")")
-- Kept for the next start where that start reads it (not on Windows, which
-- reads the registry): both sides, whatever this machine is.
local real_has = vim.fn.has
local function as(windows)
  vim.fn.has = function(what)
    if what == "win32" then
      return windows and 1 or 0
    end
    return real_has(what)
  end
end
as(true)
-- What a run off Windows kept above is not this step's.
vim.fn.delete(paper.state_file)
answer = "light"
vim.api.nvim_exec_autocmds("FocusGained", {})
check(vim.g.colors_name == "paper" and loads == 1, "auto: the system turned light: paper, once")
check(vim.fn.filereadable(paper.state_file) == 0, "auto: on Windows nothing is kept (the registry is read)")
as(false)
answer = "dark"
vim.api.nvim_exec_autocmds("FocusGained", {})
check(vim.fn.readfile(paper.state_file)[1] == "dark", "auto: elsewhere the answer is kept for the next start")
answer = "light"
vim.api.nvim_exec_autocmds("FocusGained", {})
vim.fn.has = real_has
-- Nothing known at start: 'background' decides.
known, answer = nil, nil
vim.o.background = "dark"
paper.auto()
check(vim.g.colors_name == "paper-dark", "auto: nothing known: background decides")
loads = 0
vim.o.background = "light"
check(vim.g.colors_name == "paper", "auto: background=light gives paper, not " .. tostring(vim.g.colors_name))
check(loads == 1, "auto: one load for one change, not " .. loads)
loads = 0
vim.o.background = "dark"
check(vim.g.colors_name == "paper-dark", "auto: background=dark gives paper-dark")
check(loads == 1, "auto: one load back, not " .. loads)
-- Another colorscheme is left alone.
vim.cmd.colorscheme("default")
loads = 0
vim.o.background = "light"
check(loads == 0 and vim.g.colors_name == "default", "auto: another colorscheme is not replaced")
paper.load = load

print(string.format("%d checks, %d failed", checks, #failures))
for _, f in ipairs(failures) do
  print("FAIL " .. f)
end
if #failures > 0 then
  vim.cmd("cquit 1")
end
