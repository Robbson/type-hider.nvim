-- Driver script for the README demo recording (scripts/record-demo.sh).
--
-- It opens samples/demo.ts with the types visible, types ":TypeHiderEnable"
-- after a short pause, and quits. Run through asciinema, the recorded output
-- becomes assets/demo.gif. Nothing here is part of the plugin itself.
local root = vim.env.TYPE_HIDER_ROOT or vim.fn.getcwd()

vim.opt.rtp:append(root)
vim.cmd("runtime plugin/type-hider.lua")
local type_hider = require("type-hider")
-- Start with the types visible; the demo switches them off by typing a command.
type_hider.setup({ auto_enable = false })

vim.cmd("edit " .. vim.fn.fnameescape(root .. "/samples/demo.ts"))
vim.bo.filetype = "typescript"

-- A clean, presentation-friendly window.
vim.opt.number = false
vim.opt.relativenumber = false
vim.opt.signcolumn = "no"
vim.opt.foldcolumn = "0"
vim.opt.laststatus = 0
vim.opt.showcmd = false
vim.opt.ruler = false
vim.opt.cursorline = false
vim.opt.scrolloff = 0
vim.opt.termguicolors = true
vim.opt.background = "dark"
vim.cmd("normal! gg")

-- A pty without a real terminal makes nvim probe the background color and
-- print "E1568: Terminal did not respond to DSR request for 'background'
-- color'". Wipe that message so it does not show up in the recording.
vim.cmd("silent! messages clear")
vim.api.nvim_echo({}, false, {})
vim.cmd("redraw!")

-- A queue of timed steps; each entry is { delay_ms, fn }.
local steps = {}
local function wait(ms)
  steps[#steps + 1] = { ms, function() end }
end
local function do_(fn)
  steps[#steps + 1] = { 0, fn }
end
local function type_chars(text, per_char)
  for i = 1, #text do
    local ch = text:sub(i, i)
    steps[#steps + 1] = {
      per_char,
      function()
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(ch, true, false, true), "n", false)
      end,
    }
  end
end

wait(1200) -- let the viewer read the type-heavy "before"
type_chars(":TypeHiderEnable", 30) -- type the command
do_(function()
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("\r", true, false, true), "n", false)
end)
wait(2600) -- show the clean "after"
do_(function()
  vim.cmd("qa!")
end)

local i = 0
local function tick()
  i = i + 1
  local step = steps[i]
  if not step then
    return
  end
  vim.defer_fn(function()
    step[2]()
    tick()
  end, step[1])
end
tick()
