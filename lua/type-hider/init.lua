-- Public API and configuration.
local impl = require("type-hider.main")

---@class typehider.Config
---@field formats string[] Filetypes whose types are hidden.
---@field conceallevel integer 'conceallevel' used while the types are hidden.
---@field concealcursor string 'concealcursor' used while the types are hidden.
---@field auto_enable boolean Hide types automatically for matching filetypes.

---@type typehider.Config
local config = {
  formats = { "typescript", "typescriptreact" },
  conceallevel = 2,
  concealcursor = "nvic",
  auto_enable = true,
}

---@class typehider.Module
local M = {}

---@type typehider.Config
M.config = config

---@param args typehider.Config?
M.setup = function(args)
  M.config = vim.tbl_deep_extend("force", M.config, args or {})
  impl.setup(M.config)
end

-- A `.tsx` file gets the `typescriptreact` filetype, which normally maps to the
-- `tsx` Treesitter parser. Register the mapping when no parser provider (such as
-- nvim-treesitter) has done it already.
if vim.treesitter.language.get_lang("typescriptreact") == "typescriptreact" then
  vim.treesitter.language.register("tsx", { "typescriptreact", "typescript.tsx" })
end

-- Apply the configuration (and auto-enable) even when `setup()` is never called.
impl.setup(M.config)

---Hide the types in every matching buffer.
---@return boolean ok
M.enable = function()
  return impl.enable()
end

---Show the types again.
---@return boolean ok
M.disable = function()
  return impl.disable()
end

---@return boolean enabled
M.toggle = function()
  return impl.toggle()
end

---@return boolean enabled
M.is_enabled = function()
  return impl.is_enabled()
end

return M
