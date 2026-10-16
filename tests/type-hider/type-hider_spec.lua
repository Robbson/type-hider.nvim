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

---Text hidden by inline conceal marks.
---@param buf integer
---@return string[]
local function concealed_texts(buf)
  local texts = {}
  for _, m in ipairs(extmarks(buf)) do
    if m[4].conceal ~= nil then
      local line = vim.api.nvim_buf_get_lines(buf, m[2], m[2] + 1, false)[1]
      texts[#texts + 1] = line:sub(m[3] + 1, m[4].end_col)
    end
  end
  return texts
end

---True when a folded range covers `row`.
---@param buf integer
---@param row integer
---@return boolean
local function folded_at(buf, row)
  for _, m in ipairs(extmarks(buf)) do
    if m[4].conceal_lines ~= nil and m[2] <= row and m[4].end_row >= row then
      return true
    end
  end
  return false
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

    it("conceals as / satisfies casts", function()
      if not has_parser("typescript") then
        pending("typescript parser is not installed")
        return
      end

      local cases = {
        { "let a = x as Foo;", " as Foo" },
        { "let b = x as const;", " as const" },
        { "let c = x as Foo<Bar>;", " as Foo<Bar>" },
        { "let d = x satisfies Foo;", " satisfies Foo" },
        { "let e = x as readonly string[];", " as readonly string[]" },
      }

      for _, case in ipairs(cases) do
        local buf = new_buffer({ case[1] }, "typescript")
        local texts = {}
        for _, m in ipairs(extmarks(buf)) do
          if m[4].conceal ~= nil then
            local line = vim.api.nvim_buf_get_lines(buf, m[2], m[2] + 1, false)[1]
            texts[#texts + 1] = line:sub(m[3] + 1, m[4].end_col)
          end
        end
        assert.is_true(vim.tbl_contains(texts, case[2]), case[1] .. " -> " .. vim.inspect(texts))
      end
    end)

    it("swallows one blank line after a folded declaration", function()
      if not has_parser("typescript") then
        pending("typescript parser is not installed")
        return
      end

      local function folded_end(lines)
        local buf = new_buffer(lines, "typescript")
        local last
        for _, m in ipairs(extmarks(buf)) do
          if m[4].conceal_lines ~= nil then
            last = m[4].end_row
          end
        end
        return last
      end

      assert.are.equal(2, folded_end({ "interface P {", "}", "", "let x = 1;" }))
      assert.are.equal(1, folded_end({ "interface P {", "}", "let x = 1;" }))
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

  describe("declaration coverage", function()
    local inline_cases = {
      { "class C implements I, J {}", "implements I, J" },
      { "class C { public x = 1; }", "public " },
      { "class C { private static x = 1; }", "private " },
      { "class C { override m() {} }", "override " },
      { "class C { readonly x = 1; }", "readonly " },
      { "abstract class C {}", "abstract " },
      { "function f(a?: number) {}", "?" },
      { "let v!: string;", "!" },
      { "const y = x!;", "!" },
      { "function f(x: unknown): x is Foo {}", ": x is Foo" },
      { "function f(x: unknown): asserts x is Foo {}", ": asserts x is Foo" },
    }

    for _, case in ipairs(inline_cases) do
      it("conceals: " .. case[1], function()
        if not has_parser("typescript") then
          pending("typescript parser is not installed")
          return
        end

        local buf = new_buffer({ case[1] }, "typescript")
        local texts = concealed_texts(buf)
        local found = false
        for _, text in ipairs(texts) do
          if text:find(case[2], 1, true) then
            found = true
          end
        end
        assert.is_true(found, case[1] .. " -> " .. vim.inspect(texts))
      end)
    end

    local fold_cases = {
      { "enum E { A, B }" },
      { "const enum E { A, B }" },
      { "declare const x: number;" },
      { "declare function f(a: string): number;" },
      { "function f(a: string): number;" },
      { "import type { T } from './m';" },
      { "export type { T } from './m';" },
    }

    for _, case in ipairs(fold_cases) do
      it("folds: " .. case[1], function()
        if not has_parser("typescript") then
          pending("typescript parser is not installed")
          return
        end

        local buf = new_buffer({ case[1] }, "typescript")
        assert.is_true(folded_at(buf, case[2] or 0), case[1])
      end)
    end

    it("conceals type-only import specifiers with their comma", function()
      if not has_parser("typescript") then
        pending("typescript parser is not installed")
        return
      end

      local buf = new_buffer({ "import { type A, b } from './m';" }, "typescript")
      local texts = concealed_texts(buf)
      local found = false
      for _, text in ipairs(texts) do
        if text:find("type A,", 1, true) then
          found = true
        end
      end
      assert.is_true(found, vim.inspect(texts))
    end)
  end)

  describe("navigation", function()
    it("registers the cursor hook while enabled", function()
      plugin.enable()
      assert.is_true(#vim.api.nvim_get_autocmds({ group = "type-hider-refresh", event = "CursorMoved" }) >= 1)

      plugin.disable()
      assert.are.equal(0, #vim.api.nvim_get_autocmds({ group = "type-hider-refresh", event = "CursorMoved" }))
    end)

    it("moves the cursor off hidden lines", function()
      if not has_parser("typescript") then
        pending("typescript parser is not installed")
        return
      end

      local buf = new_buffer(
        { "let a = 1;", "interface P {", "  x: number;", "}", "let b = 2;" },
        "typescript"
      )

      -- Land on the first hidden line while moving down; the hook should push
      -- the cursor to the first visible line below the block.
      vim.api.nvim_win_set_cursor(0, { 2, 0 })
      vim.api.nvim_exec_autocmds("CursorMoved", { buffer = buf })
      assert.are.equal(5, vim.api.nvim_win_get_cursor(0)[1])

      -- Land on the last hidden line while moving up; the hook should push the
      -- cursor to the first visible line above the block.
      vim.api.nvim_win_set_cursor(0, { 4, 0 })
      vim.api.nvim_exec_autocmds("CursorMoved", { buffer = buf })
      assert.are.equal(1, vim.api.nvim_win_get_cursor(0)[1])
    end)
  end)
end)
