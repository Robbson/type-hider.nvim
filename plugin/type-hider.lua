-- Registration of Neovim Commands
local plugin = require("type-hider")

vim.api.nvim_create_user_command("TypeHiderEnable", plugin.enable, {})

vim.api.nvim_clear_autocmds({ group = plugin.augroup })

vim.api.nvim_create_autocmd({ "BufEnter" }, {
  group = plugin.augroup,
  pattern = "*.ts",
  callback = function(args)
    plugin.on_buf_enter(args)
  end,
})

vim.notify("type-hider loaded successfully!", vim.log.levels.INFO)
