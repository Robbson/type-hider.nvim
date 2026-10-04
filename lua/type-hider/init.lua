-- Public API and Configuration
local module = require("type-hider.main")

---@class Config
---@field opt string Your config option
---@field formats table Activated language extensions
local config = {
  opt = "Hello!",
  formats = { "ts", "tsx" },
}

---@class MyModule
local M = {}

---@type Config
M.config = config

---@param args Config?
-- you can define your setup function here. Usually configurations can be merged, accepting outside params and
-- you can also put some validation here for those.
M.setup = function(args)
  M.config = vim.tbl_deep_extend("force", M.config, args or {})
end

M.namespace = vim.api.nvim_create_namespace("typehider")
M.augroup = vim.api.nvim_create_augroup("typehider", {})

M.on_buf_enter = function(args)
  -- eigentliche Implementierung
  vim.notify("type-hider: Buffer entered", vim.log.levels.INFO)
end

M.enable = function()
  return module.enable(M.config.opt)
end

return M
