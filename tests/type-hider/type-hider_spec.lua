local plugin = require("type-hider")

local defaults = {
  formats = { "typescript", "typescriptreact" },
  conceallevel = 2,
  concealcursor = "nvic",
  auto_enable = false,
}

---@param lang string
---@return boolean
local function has_parser(lang)
  return pcall(vim.treesitter.language.inspect, lang)
end

---@param lines string[]
---@param filetype string
---@return integer
local function new_buffer(lines, filetype)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_current_buf(buf)
  vim.bo[buf].filetype = filetype
  plugin.enable()
  return buf
end

---@param buf integer
---@return table[]
local function extmarks(buf)
  local ns = vim.api.nvim_get_namespaces()["type-hider"]
  return vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
end

---@param buf integer
---@param field string
---@return integer
local function count_with(buf, field)
  local n = 0
  for _, m in ipairs(extmarks(buf)) do
    if m[4][field] ~= nil then
      n = n + 1
    end
  end
  return n
end

describe("type-hider", function()
  before_each(function()
    plugin.setup(defaults)
  end)

  after_each(function()
    plugin.disable()
    vim.cmd("silent! %bwipeout!")
  end)

  describe("setup", function()
    it("keeps the configured values", function()
      assert.are.same({ "typescript", "typescriptreact" }, plugin.config.formats)
      assert.are.equal(2, plugin.config.conceallevel)
      assert.are.equal("nvic", plugin.config.concealcursor)
      assert.is_false(plugin.config.auto_enable)
    end)

    it("merges user options", function()
      plugin.setup({ conceallevel = 1, auto_enable = true })
      assert.are.equal(1, plugin.config.conceallevel)
      assert.is_true(plugin.config.auto_enable)
      assert.are.same({ "typescript", "typescriptreact" }, plugin.config.formats)
    end)
  end)

  describe("enable/disable", function()
    it("ignores unsupported filetypes", function()
      local buf = new_buffer({ "print('hi')" }, "lua")
      assert.are.equal(0, #extmarks(buf))
      assert.is_true(plugin.is_enabled())
    end)

    it("conceals and reveals via the commands", function()
      if not has_parser("typescript") then
        pending("typescript parser is not installed")
        return
      end

      local buf = new_buffer({ "let x: number = 1;" }, "typescript")
      assert.is_true(plugin.is_enabled())
      assert.are.equal(2, vim.wo.conceallevel)
      assert.are.equal("nvic", vim.wo.concealcursor)
      assert.are.equal(1, count_with(buf, "conceal"))

      plugin.disable()
      assert.is_false(plugin.is_enabled())
      assert.are.equal(0, vim.wo.conceallevel)
      assert.are.equal(0, #extmarks(buf))

      plugin.enable()
      assert.is_true(plugin.is_enabled())
      assert.are.equal(1, count_with(buf, "conceal"))
    end)

    it("toggles between hidden and shown", function()
      if not has_parser("typescript") then
        pending("typescript parser is not installed")
        return
      end

      local buf = new_buffer({ "let x: number = 1;" }, "typescript")
      assert.is_true(plugin.is_enabled())
      assert.is_false(plugin.toggle())
      assert.are.equal(0, #extmarks(buf))
      assert.is_true(plugin.toggle())
      assert.are.equal(1, count_with(buf, "conceal"))
    end)
  end)

  describe("conceal query", function()
    it("conceals inline type annotations", function()
      if not has_parser("typescript") then
        pending("typescript parser is not installed")
        return
      end

      local buf = new_buffer({ "let x: number = 1;" }, "typescript")
      local marks = extmarks(buf)
      assert.are.same({ 0, 5, 0, 13 }, { marks[1][2], marks[1][3], marks[1][4].end_row, marks[1][4].end_col })
      assert.are.equal("", marks[1][4].conceal)
    end)

    it("folds whole interface declarations away", function()
      if not has_parser("typescript") then
        pending("typescript parser is not installed")
        return
      end

      local buf = new_buffer({ "interface P {", "  name: string;", "}" }, "typescript")
      local folded = false
      for _, m in ipairs(extmarks(buf)) do
        if m[4].conceal_lines ~= nil and m[2] == 0 and m[4].end_row == 2 then
          folded = true
        end
      end
      assert.is_true(folded)
    end)

    it("keeps text sharing a line with a type declaration", function()
      if not has_parser("typescript") then
        pending("typescript parser is not installed")
        return
      end

      local buf = new_buffer({ "type N = P['name']; // keep me" }, "typescript")
      assert.are.equal(0, count_with(buf, "conceal_lines"))
      assert.are.equal(1, count_with(buf, "conceal"))
    end)

    it("conceals types in tsx as well", function()
      if not has_parser("tsx") then
        pending("tsx parser is not installed")
        return
      end

      local buf = new_buffer({ "let x: number = 1;" }, "typescriptreact")
      assert.are.equal(1, count_with(buf, "conceal"))
    end)
  end)
end)
