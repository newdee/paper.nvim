-- The lualine theme of one variant, drawn as keepane's paper status line:
-- soft ink on the bar, the mode in a block (cinnabar in normal mode, as
-- keepane's session; Vitesse's own colours in the others), the rest quiet.
return function(style)
  local c = require("paper.palette")[style]
  local function mode(colour)
    return {
      a = { fg = c.on_accent, bg = colour, gui = "bold" },
      b = { fg = c.fg, bg = c.bg_sel },
      c = { fg = c.soft, bg = c.bg_dim },
    }
  end
  return {
    normal = mode(c.cinnabar),
    insert = mode(c.keyword),
    visual = mode(c.namespace),
    replace = mode(c.builtin),
    command = mode(c.info),
    terminal = mode(c.type),
    inactive = {
      a = { fg = c.muted, bg = c.bg_dim, gui = "bold" },
      b = { fg = c.muted, bg = c.bg_dim },
      c = { fg = c.muted, bg = c.bg_dim },
    },
  }
end
