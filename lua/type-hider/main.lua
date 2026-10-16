-- Plugin implementation: hide TypeScript types by managing conceal extmarks.
local M = {}

local ns = vim.api.nvim_create_namespace("type-hider")
local refresh_group = vim.api.nvim_create_augroup("type-hider-refresh", { clear = true })

---@type typehider.Config
local config = {}

local state = {
  enabled = false,
  ---@type table<integer, boolean>
  buffers = {},
}

---@param cfg typehider.Config
function M.setup(cfg)
  config = cfg
  if config.auto_enable then
    M.enable()
  else
    M.disable()
  end
end

---Resolve `0` / nil to the current buffer.
---@param bufnr integer?
---@return integer
local function resolve(bufnr)
  if bufnr == nil or bufnr == 0 then
    return vim.api.nvim_get_current_buf()
  end
  return bufnr
end

---@param bufnr integer
---@return string? lang
local function buffer_lang(bufnr)
  local filetype = vim.bo[bufnr].filetype
  if not vim.tbl_contains(config.formats or {}, filetype) then
    return nil
  end
  return vim.treesitter.language.get_lang(filetype)
end

---All windows currently displaying a buffer.
---@param bufnr integer
---@return integer[]
local function windows_of(bufnr)
  local wins = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == bufnr then
      wins[#wins + 1] = win
    end
  end
  return wins
end

---'conceallevel' and 'concealcursor' are window-local options.
---@param bufnr integer
local function apply_window_options(bufnr)
  for _, win in ipairs(windows_of(bufnr)) do
    vim.wo[win].conceallevel = config.conceallevel or 2
    vim.wo[win].concealcursor = config.concealcursor or "nvic"
  end
end

---True when a node's first/last line contain nothing but the node itself.
---@param bufnr integer
---@param srow integer
---@param scol integer
---@param erow integer
---@param ecol integer
---@return boolean
local function covers_whole_line(bufnr, srow, scol, erow, ecol)
  local first = vim.api.nvim_buf_get_lines(bufnr, srow, srow + 1, false)[1] or ""
  if first:sub(1, scol):find("%S") then
    return false
  end
  local last = vim.api.nvim_buf_get_lines(bufnr, erow, erow + 1, false)[1] or ""
  if last:sub(ecol + 1):find("%S") then
    return false
  end
  return true
end

---Conceal range for an `as` / `satisfies` cast, starting at the keyword (and
---swallowing the whitespace before it on the same line). The cast type may be
---an anonymous node (`as const`), so it is not captured in the query; instead
---the range is computed from the keyword to the node end.
---@param node TSNode
---@return table?
local function cast_mark(node)
  ---@type TSNode?
  local prev = nil
  for child in node:iter_children() do
    local kind = child:type()
    if kind == "as" or kind == "satisfies" then
      local srow, scol = child:range()
      local _, _, erow, ecol = node:range()
      if prev then
        local _, _, prow, pcol = prev:range()
        if prow == srow then
          scol = pcol
        end
      end
      if srow == erow and scol == ecol then
        return nil
      end
      return { srow, scol, erow, ecol, "inline" }
    end
    prev = child
  end
  return nil
end

---Ranges to conceal, as `{ srow, scol, erow, ecol, kind }`.
---@param bufnr integer
---@return table[]
local function collect_marks(bufnr)
  local marks = {}
  local lang = buffer_lang(bufnr)
  if not lang then
    return marks
  end

  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, lang)
  if not ok or not parser then
    return marks
  end
  pcall(parser.parse, parser)

  parser:for_each_tree(function(tree, lang_tree)
    local query = vim.treesitter.query.get(lang_tree:lang(), "type-hider")
    if not query then
      return
    end

    for id, node in query:iter_captures(tree:root(), bufnr) do
      local capture = query.captures[id]
      local srow, scol, erow, ecol = node:range()

      if capture == "type.block" then
        if erow > srow or covers_whole_line(bufnr, srow, scol, erow, ecol) then
          -- Also swallow one blank line right after the declaration so folded
          -- blocks do not pile up empty separator lines.
          local last = erow
          local next_line = vim.api.nvim_buf_get_lines(bufnr, erow + 1, erow + 2, false)[1]
          if next_line ~= nil and next_line:find("%S") == nil then
            last = erow + 1
          end
          marks[#marks + 1] = { srow, 0, last, 0, "lines" }
        else
          marks[#marks + 1] = { srow, scol, erow, ecol, "inline" }
        end
      elseif capture == "type.cast" then
        local mark = cast_mark(node)
        if mark then
          marks[#marks + 1] = mark
        end
      elseif capture == "type" and not (srow == erow and scol == ecol) then
        marks[#marks + 1] = { srow, scol, erow, ecol, "inline" }
      end
    end
  end)

  return marks
end

---Recompute and apply the conceal extmarks for one buffer.
---@param bufnr integer?
local function set_conceal(bufnr)
  bufnr = resolve(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
    return
  end

  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

  if not buffer_lang(bufnr) then
    state.buffers[bufnr] = nil
    return
  end

  for _, mark in ipairs(collect_marks(bufnr)) do
    local srow, scol, erow, ecol, kind = mark[1], mark[2], mark[3], mark[4], mark[5]
    if kind == "lines" then
      vim.api.nvim_buf_set_extmark(bufnr, ns, srow, 0, {
        end_row = erow,
        end_col = 0,
        conceal_lines = "",
      })
    else
      vim.api.nvim_buf_set_extmark(bufnr, ns, srow, scol, {
        end_row = erow,
        end_col = ecol,
        conceal = "",
      })
    end
  end

  state.buffers[bufnr] = true
  apply_window_options(bufnr)
end

---Hide the types in every matching buffer.
---@return boolean
function M.enable()
  if state.enabled then
    return true
  end
  state.enabled = true

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "InsertLeave" }, {
    group = refresh_group,
    callback = function(args)
      if state.enabled then
        set_conceal(args.buf)
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", "WinEnter", "FileType" }, {
    group = refresh_group,
    callback = function(args)
      if state.enabled then
        set_conceal(args.buf)
      end
    end,
  })

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      set_conceal(bufnr)
    end
  end

  return true
end

---Show the types again and remove every conceal.
---@return boolean
function M.disable()
  if not state.enabled then
    return false
  end
  state.enabled = false

  vim.api.nvim_clear_autocmds({ group = refresh_group })

  for bufnr in pairs(state.buffers) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
      for _, win in ipairs(windows_of(bufnr)) do
        vim.wo[win].conceallevel = 0
      end
    end
  end
  state.buffers = {}

  return true
end

---@return boolean enabled
function M.toggle()
  if state.enabled then
    M.disable()
    return state.enabled
  end
  M.enable()
  return state.enabled
end

---@return boolean
function M.is_enabled()
  return state.enabled
end

return M
