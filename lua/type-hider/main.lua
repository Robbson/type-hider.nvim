-- Plugin implementation
---@class CustomModule
local M = {}

---@return string
M.enable = function(greeting)
  vim.notify("Start processing")
  return greeting
end

return M
