-- Registration of the user commands.
--
-- Files in a plugin/ directory are sourced automatically by Neovim at startup
-- (after other plugins are loaded, before you open a file), so this is the
-- right place to define commands. The heavy lifting happens in
-- lua/type-hider/main.lua; requiring "type-hider" also applies the config.
local type_hider = require("type-hider")

-- `force = true` lets the commands be redefined when the plugin is reloaded
-- during development instead of erroring with "command already exists".
vim.api.nvim_create_user_command("TypeHiderEnable", function()
  type_hider.enable()
end, { desc = "Hide TypeScript type declarations", force = true })

vim.api.nvim_create_user_command("TypeHiderDisable", function()
  type_hider.disable()
end, { desc = "Show TypeScript type declarations", force = true })

vim.api.nvim_create_user_command("TypeHiderToggle", function()
  type_hider.toggle()
end, { desc = "Toggle hiding of TypeScript type declarations", force = true })
