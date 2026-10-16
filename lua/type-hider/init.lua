-- Public API and configuration for type-hider.
--
-- This module is what users require:
--
--   require("type-hider").setup({ ... })  -- optional
--   require("type-hider").enable()        -- same as :TypeHiderEnable
--
-- It only holds the configuration and forwards calls to the engine in
-- lua/type-hider/main.lua. See doc/architecture.md for the big picture.

-- The engine (all the real work lives there).
local impl = require("type-hider.main")

---Configuration options.
---@class typehider.Config
---@field formats string[] Filetypes whose types are hidden.
---@field conceallevel integer 'conceallevel' used while the types are hidden.
---@field concealcursor string 'concealcursor' used while the types are hidden.
---@field auto_enable boolean Hide types automatically for matching filetypes.

---The defaults. `setup()` deep-merges user options over these.
---@type typehider.Config
local config = {
  -- `typescript` is used for .ts, `typescriptreact` for .tsx.
  formats = { "typescript", "typescriptreact" },
  -- Conceal is only drawn when 'conceallevel' >= 2.
  conceallevel = 2,
  -- Hide even on the cursor line and while selecting; see main.lua.
  concealcursor = "nvic",
  -- Hide types as soon as a matching buffer is loaded.
  auto_enable = true,
}

---@class typehider.Module
local M = {}

---@type typehider.Config
M.config = config

---Merge user options into the defaults and apply them.
---@param args typehider.Config?
M.setup = function(args)
  M.config = vim.tbl_deep_extend("force", M.config, args or {})
  impl.setup(M.config)
end

-- A .tsx file gets the `typescriptreact` filetype, which normally maps to the
-- `tsx` Treesitter parser. nvim-treesitter registers that mapping; when no
-- provider has done it yet we register it ourselves so .tsx works standalone.
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

---Toggle hiding the types.
---@return boolean enabled
M.toggle = function()
  return impl.toggle()
end

---@return boolean enabled
M.is_enabled = function()
  return impl.is_enabled()
end

return M
