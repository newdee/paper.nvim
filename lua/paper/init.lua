-- paper.nvim: Paper (ink on white) and Paper Dark (ink on dark paper), the
-- code blocks of dfine.tech in Neovim. Vitesse's colours on the paper of
-- the page, one accent in cinnabar; every text colour reads at 4.5:1 or
-- more on the editor, the cursor line, the floats and the selection.
local M = {}

---@class paper.Config
---@field transparent? boolean leave the editor's background to the terminal
---@field italic_comments? boolean
---@field on_highlights? fun(hl: table<string, vim.api.keyset.highlight>, c: table) change groups before they are set
M.config = {
  transparent = false,
  italic_comments = true,
  on_highlights = nil,
}

---@param opts? paper.Config
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

--- The colours of one variant: "dark" or "light".
---@param style "dark"|"light"
function M.palette(style)
  return require("paper.palette")[style]
end

local function scheme(style)
  return style == "light" and "paper" or "paper-dark"
end

--- Sets the colorscheme: `paper` for "light", `paper-dark` for "dark".
---
--- Neovim loads the current colorscheme again when 'background' changes:
--- then 'background' no longer matches the variant already shown, and the
--- other one is drawn (`:set bg=light` in Paper Dark gives Paper).
---@param style "dark"|"light"
function M.load(style)
  if style ~= "dark" and style ~= "light" then
    error(string.format('paper: load("dark") or load("light"), not %s', vim.inspect(style)), 2)
  end
  if vim.g.colors_name == scheme(style) and vim.o.background ~= style then
    style = vim.o.background == "light" and "light" or "dark"
  end
  local c = M.palette(style)
  -- Cleared first (that also forgets colors_name), so setting 'background'
  -- below does not make Neovim load the old scheme again.
  if vim.g.colors_name then
    vim.cmd("highlight clear")
  end
  vim.o.termguicolors = true
  vim.o.background = style
  local hl = require("paper.groups").get(c, M.config)
  if M.config.on_highlights then
    M.config.on_highlights(hl, c)
  end
  for name, spec in pairs(hl) do
    vim.api.nvim_set_hl(0, name, spec)
  end
  for i, colour in ipairs(c.terminal) do
    vim.g["terminal_color_" .. (i - 1)] = colour
  end
  vim.g.colors_name = scheme(style)
end

-- The system's light or dark ----------------------------------------------
--
-- Windows: read in this process, through the registry (0.9 ms the first
-- time, advapi32 loaded with it, then 0.02 ms; starting reg.exe took about
-- 190 ms, at every start). macOS and Linux have no such call: a program
-- answers (`defaults`, `gsettings`), so it runs in the background, and the
-- start draws what it said last time.

local function windows()
  local ok, ffi = pcall(require, "ffi")
  if not ok then
    return nil
  end
  pcall(ffi.cdef, [[
    long RegGetValueW(void *hkey, const uint16_t *sub, const uint16_t *value, unsigned long flags,
                      unsigned long *type, void *data, unsigned long *size);
  ]])
  local function wide(s)
    local w = ffi.new("uint16_t[?]", #s + 1)
    for i = 1, #s do
      w[i - 1] = s:byte(i)
    end
    return w
  end
  -- HKEY_CURRENT_USER is (HKEY)(LONG)0x80000001, sign-extended on 64 bits.
  local hkcu = ffi.cast("void *", ffi.cast("intptr_t", -0x7fffffff))
  local data, size = ffi.new("unsigned long[1]"), ffi.new("unsigned long[1]", 4)
  local RRF_RT_REG_DWORD = 0x10
  -- Where RegGetValueW is: advapi32 (kernel32 forwards it on Windows 8 and
  -- later, but that is not promised). Looking a symbol up can throw.
  local okl, lib = pcall(ffi.load, "advapi32")
  local okf, fn = pcall(function()
    return (okl and lib or ffi.C).RegGetValueW
  end)
  if not okf then
    return nil
  end
  local okc, rc = pcall(
    fn,
    hkcu,
    wide([[Software\Microsoft\Windows\CurrentVersion\Themes\Personalize]]),
    wide("AppsUseLightTheme"),
    RRF_RT_REG_DWORD,
    nil,
    data,
    size
  )
  if not okc or rc ~= 0 then
    return nil
  end
  return data[0] == 0 and "dark" or "light"
end

-- The program that answers elsewhere, and how to read its answer.
local function probe()
  if vim.fn.has("mac") == 1 then
    -- The key exists only in dark mode: no key is light.
    return { "defaults", "read", "-g", "AppleInterfaceStyle" }, function(code, out)
      return (code == 0 and out:match("Dark")) and "dark" or "light"
    end
  elseif vim.fn.executable("gsettings") == 1 then
    return { "gsettings", "get", "org.gnome.desktop.interface", "color-scheme" }, function(code, out)
      if code ~= 0 then
        return nil
      end
      return out:match("dark") and "dark" or "light"
    end
  end
end

--- The system's light or dark (Windows' AppsUseLightTheme, macOS's
--- AppleInterfaceStyle, GNOME's color-scheme), or nil when it cannot be
--- told. Off Windows this waits for a program (up to a second).
---@return "dark"|"light"|nil
function M.system()
  if vim.fn.has("win32") == 1 then
    return windows()
  end
  local cmd, read = probe()
  if not cmd then
    return nil
  end
  local ok, r = pcall(vim.system, cmd, { text = true })
  local done = ok and r:wait(1000) or nil
  return done and done.code and read(done.code, done.stdout or "") or nil
end

--- The same, without waiting: `cb` gets the answer on the main loop.
---@param cb fun(style: "dark"|"light"|nil)
function M.system_async(cb)
  if vim.fn.has("win32") == 1 then
    return cb(windows())
  end
  local cmd, read = probe()
  if not cmd then
    return cb(nil)
  end
  local ok = pcall(vim.system, cmd, { text = true }, function(done)
    vim.schedule(function()
      cb(read(done.code, done.stdout or ""))
    end)
  end)
  if not ok then
    cb(nil)
  end
end

-- What the system said last time, for a start that does not wait.
--- Where that is kept (nil: `stdpath("state")/paper-system`).
---@type string?
M.state_file = nil
local function kept_path()
  return M.state_file or (vim.fn.stdpath("state") .. "/paper-system")
end
local function kept()
  local f = io.open(kept_path(), "r")
  local s = f and f:read("*l")
  if f then
    f:close()
  end
  return (s == "dark" or s == "light") and s or nil
end
local function keep(style)
  if style and style ~= kept() then
    vim.fn.mkdir(vim.fn.fnamemodify(kept_path(), ":h"), "p")
    local f = io.open(kept_path(), "w")
    if f then
      f:write(style, "\n")
      f:close()
    end
  end
end

--- What is known of the system's look without waiting: Windows' registry,
--- elsewhere the answer kept from last time; nil when nothing is.
---@return "dark"|"light"|nil
function M.now()
  if vim.fn.has("win32") == 1 then
    return windows()
  end
  return kept()
end

local following = false

-- The system's answer, when it came: the other variant if it turned.
local function follow(style)
  -- Kept only where the next start reads it (Windows reads the registry).
  if vim.fn.has("win32") == 0 then
    keep(style)
  end
  if style and (vim.g.colors_name or ""):match("^paper") and style ~= vim.o.background then
    M.load(style)
  end
end

--- Paper or Paper Dark as the system is, and again whenever Neovim gets the
--- focus back and the system has turned in the meantime. Starting does not
--- wait: on Windows the registry is read at once; elsewhere the last answer
--- (or 'background') is drawn and the system asked in the background.
--- (A change of 'background' by hand switches too, as with `:colorscheme`.)
function M.auto()
  M.load(M.now() or (vim.o.background == "light" and "light" or "dark"))
  M.system_async(follow)
  if following then
    return
  end
  following = true
  vim.api.nvim_create_autocmd("FocusGained", {
    group = vim.api.nvim_create_augroup("paper_auto", { clear = true }),
    callback = function()
      M.system_async(follow)
    end,
  })
end

return M