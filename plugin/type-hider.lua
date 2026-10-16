-- Registration of Neovim commands.
local type_hider = require("type-hider")

vim.api.nvim_create_user_command("TypeHiderEnable", function()
  type_hider.enable()
end, { desc = "Hide TypeScript type declarations", force = true })

vim.api.nvim_create_user_command("TypeHiderDisable", function()
  type_hider.disable()
end, { desc = "Show TypeScript type declarations", force = true })

vim.api.nvim_create_user_command("TypeHiderToggle", function()
  type_hider.toggle()
end, { desc = "Toggle hiding of TypeScript type declarations", force = true })
