-- type-hider: hide TypeScript type declarations so a .ts/.tsx buffer reads like
-- plain JavaScript. Nothing is removed from the file, the type syntax is only
-- *hidden* using Neovim's conceal feature. Press the commands (see
-- plugin/type-hider.lua) to show the types again at any time.
--
-- This file is the engine. It is written for readers who are new to Neovim
-- plugins, so here is a short glossary of the Neovim concepts used below:
--
--   buffer         an in-memory text file (roughly: what you see in a tab)
--   window         a viewport that shows a buffer (a buffer can be shown in
--                  several windows at once)
--   extmark        an annotation attached to a range of a buffer, set through
--                  the API with nvim_buf_set_extmark(). Extmarks move with the
--                  text and do not change the file contents.
--   namespace      an id that groups extmarks, so we can clear only our own
--                  marks (nvim_buf_clear_namespace) without touching others
--   conceal        an extmark attribute: `conceal = ""` hides the covered text,
--                  `conceal_lines = ""` hides the whole lines it covers. Both
--                  only take effect while 'conceallevel' >= 2.
--   'conceallevel' / 'concealcursor'  WINDOW-local options that decide whether
--                  conceal is drawn and in which modes it is drawn on the
--                  cursor line. Because they are window-local we set them per
--                  window (see apply_window_options).
--   autocommand    an event hook ("when a buffer is entered", "when the text
--                  changed", ...). We register ours in enable() and remove them
--                  in disable().
--   Treesitter     a parser that turns the buffer text into a syntax tree.
--                  A "query" (.scm file) selects interesting nodes; here it
--                  selects the TypeScript-only syntax we want to conceal.
--
-- The high level flow is:
--   setup()/enable()  -> register autocommands, hide types in open buffers
--   autocommand       -> set_conceal(buffer)            (on changes/entering)
--   set_conceal()     -> collect_marks()                (ask Treesitter)
--                     -> nvim_buf_set_extmark(conceal)  (draw the hiding)
--   disable()         -> remove autocommands + clear our extmarks

local M = {}

-- One namespace for all our extmarks. Keeping them in one namespace means
-- disable() can wipe exactly our conceal marks and nothing else.
local ns = vim.api.nvim_create_namespace("type-hider")

-- An augroup bundles our autocommands so we can add/remove them as a set.
-- `clear = true` removes leftovers from a previous (re)load of the plugin.
local refresh_group = vim.api.nvim_create_augroup("type-hider-refresh", { clear = true })

-- Filled in by setup() (see lua/type-hider/init.lua for the defaults).
---@type typehider.Config
local config = {}

-- Global on/off switch plus the set of buffers we currently concealed. The set
-- lets disable() find the buffers whose marks and options must be reset.
local state = {
  enabled = false,
  ---@type table<integer, boolean>
  buffers = {},
}

---Store the configuration and apply it right away.
---@param cfg typehider.Config
function M.setup(cfg)
  config = cfg
  if config.auto_enable then
    M.enable()
  else
    M.disable()
  end
end

---Normalise a buffer number.
---
---Neovim APIs accept `0` to mean "the current buffer", but our own lookups
---(for example windows_of) compare against real buffer numbers, so `0` must be
---turned into the actual id first.
---@param bufnr integer?
---@return integer
local function resolve(bufnr)
  if bufnr == nil or bufnr == 0 then
    return vim.api.nvim_get_current_buf()
  end
  return bufnr
end

---Treesitter language of a buffer, or nil when we should not touch it.
---
---`vim.bo[bufnr]` reads a buffer-local option; here the 'filetype'. We only act
---on the configured filetypes ("typescript", "typescriptreact"). The filetype
---is mapped to a parser name, e.g. "typescriptreact" -> "tsx".
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

---Turn conceal on for every window that shows the buffer.
---
---'conceallevel' and 'concealcursor' are window-local, so we iterate the
---windows. 'concealcursor' = "nvic" keeps the types hidden even on the cursor
---line and while selecting (n=normal, v=visual, i=insert, c=command-line),
---which prevents the types from popping back into view when you move the mouse.
---@param bufnr integer
local function apply_window_options(bufnr)
  for _, win in ipairs(windows_of(bufnr)) do
    vim.wo[win].conceallevel = config.conceallevel or 2
    vim.wo[win].concealcursor = config.concealcursor or "nvic"
  end
end

---Does the node occupy whole lines? (trailing `;` allowed)
---
---Used to decide between "fold the lines away" and "hide only the node text".
---`srow/scol` and `erow/ecol` are 0-based (row, column); `ecol` is exclusive.
---@param bufnr integer
---@param srow integer
---@param scol integer
---@param erow integer
---@param ecol integer
---@return boolean
local function covers_whole_line(bufnr, srow, scol, erow, ecol)
  -- Nothing but whitespace before the node on its first line...
  local first = vim.api.nvim_buf_get_lines(bufnr, srow, srow + 1, false)[1] or ""
  if first:sub(1, scol):find("%S") then
    return false
  end
  -- ...and nothing but whitespace (or a terminating `;`) after it on the last.
  local last = vim.api.nvim_buf_get_lines(bufnr, erow, erow + 1, false)[1] or ""
  if not last:sub(ecol + 1):match("^[;%s]*$") then
    return false
  end
  return true
end

---Conceal range for a type-only import/export specifier.
---
---`import { type A, b }` should read as `import { b }`, so the range must also
---cover the comma that follows the specifier (if any). `node:next_sibling()`
---gives the next node on the same level; if it is a comma we extend to its end.
---@param node TSNode
---@return table
local function specifier_mark(node)
  local srow, scol = node:range()
  -- range() returns four values: start row/col and end row/col. `select(3, ...)`
  -- picks the 3rd and 4th (the end position).
  local erow, ecol = select(3, node:range())

  local next_sibling = nil
  if node.next_sibling then
    next_sibling = node.next_sibling(node)
  end
  if next_sibling and next_sibling:type() == "," then
    erow, ecol = select(3, next_sibling:range())
  end

  return { srow, scol, erow, ecol, "inline" }
end

---Conceal range for an `as` / `satisfies` cast.
---
---We start at the keyword (`as`/`satisfies`) so the value on the left stays
---visible, and end at the end of the expression node. The cast type itself is
---not captured by the query because it can be an anonymous token (`as const`),
---which a generic node capture cannot match.
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
      -- Also swallow the space in front of the keyword ("x as T" -> "x").
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

---Grow a range forward over trailing whitespace on its last line.
---
---Used for type-only modifiers so `public x` becomes `x` and not `  x`.
---@param bufnr integer
---@param erow integer
---@param ecol integer
---@return integer ecol
local function swallow_trailing(bufnr, erow, ecol)
  local line = vim.api.nvim_buf_get_lines(bufnr, erow, erow + 1, false)[1] or ""
  local i = ecol + 1
  while i <= #line and line:sub(i, i):match("%s") do
    i = i + 1
  end
  return i - 1
end

---Grow a single-line range backward over leading whitespace.
---
---Used for `implements` so `Base implements I` becomes `Base` and not `Base `.
---@param bufnr integer
---@param srow integer
---@param scol integer
---@param erow integer
---@return integer srow
---@return integer scol
local function swallow_leading(bufnr, srow, scol, erow)
  if srow ~= erow or scol == 0 then
    return srow, scol
  end
  local line = vim.api.nvim_buf_get_lines(bufnr, srow, srow + 1, false)[1] or ""
  local i = scol
  while i >= 1 and line:sub(i, i):match("%s") do
    i = i - 1
  end
  return srow, i
end

---Ask Treesitter which ranges should be hidden.
---
---Returns a list of `{ srow, scol, erow, ecol, kind }` entries where `kind` is
---either "inline" (hide the text in the range) or "lines" (hide whole lines).
---@param bufnr integer
---@return table[]
local function collect_marks(bufnr)
  local marks = {}
  local lang = buffer_lang(bufnr)
  if not lang then
    return marks
  end

  -- get_parser() needs a parser for the language; if none is installed it
  -- errors, so we guard with pcall and simply do nothing in that case.
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, lang)
  if not ok or not parser then
    return marks
  end
  -- Make sure the tree matches the current text before we read ranges.
  pcall(parser.parse, parser)

  -- A buffer can contain several trees (for example injected languages). We
  -- visit each tree and load the query for its language. The "tsx" query
  -- inherits "typescript" (see queries/tsx/type-hider.scm), so both work.
  parser:for_each_tree(function(tree, lang_tree)
    local query = vim.treesitter.query.get(lang_tree:lang(), "type-hider")
    if not query then
      return
    end

    -- iter_captures walks every match of the query. `id` indexes the capture
    -- name (query.captures[id]); `node` is the matched syntax node.
    for id, node in query:iter_captures(tree:root(), bufnr) do
      local capture = query.captures[id]
      local srow, scol, erow, ecol = node:range()

      if capture == "type.block" then
        -- A whole declaration. If it fills its lines we hide the lines,
        -- otherwise we hide just the node text (so e.g. a trailing comment
        -- that shares the line is kept).
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
      elseif capture == "type.specifier" then
        marks[#marks + 1] = specifier_mark(node)
      elseif capture == "type.modifier" then
        -- Also hide the whitespace after the modifier to avoid double spaces.
        marks[#marks + 1] = { srow, scol, erow, swallow_trailing(bufnr, erow, ecol), "inline" }
      elseif capture == "type.clause" then
        local lrow, lcol = swallow_leading(bufnr, srow, scol, erow)
        marks[#marks + 1] = { lrow, lcol, erow, ecol, "inline" }
      elseif capture == "type" and not (srow == erow and scol == ecol) then
        marks[#marks + 1] = { srow, scol, erow, ecol, "inline" }
      end
    end
  end)

  return marks
end

---Recompute and apply the conceal extmarks for one buffer.
---
---This runs often (on every text change, buffer/window switch). It is cheap
---enough: it clears our previous marks and lays down fresh ones from the query.
---@param bufnr integer?
local function set_conceal(bufnr)
  bufnr = resolve(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
    return
  end

  -- Remove the extmarks from the previous run first, so stale ranges disappear.
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

  -- Not a file we handle: forget it and stop.
  if not buffer_lang(bufnr) then
    state.buffers[bufnr] = nil
    return
  end

  -- Translate each range into a conceal extmark.
  for _, mark in ipairs(collect_marks(bufnr)) do
    local srow, scol, erow, ecol, kind = mark[1], mark[2], mark[3], mark[4], mark[5]
    if kind == "lines" then
      -- conceal_lines hides whole lines; end_row/end_col mark the covered range.
      vim.api.nvim_buf_set_extmark(bufnr, ns, srow, 0, {
        end_row = erow,
        end_col = 0,
        conceal_lines = "",
      })
    else
      -- conceal = "" hides the text in the range without showing a placeholder.
      vim.api.nvim_buf_set_extmark(bufnr, ns, srow, scol, {
        end_row = erow,
        end_col = ecol,
        conceal = "",
      })
    end
  end

  state.buffers[bufnr] = true
  -- Extmarks alone do nothing visible; 'conceallevel' must be set to draw them.
  apply_window_options(bufnr)
end

---Hide the types in every matching buffer and keep them hidden.
---@return boolean
function M.enable()
  if state.enabled then
    return true
  end
  state.enabled = true

  -- Re-hide after edits. TextChanged/TextChangedI fire while typing, so the
  -- conceal follows the text.
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "InsertLeave" }, {
    group = refresh_group,
    callback = function(args)
      if state.enabled then
        set_conceal(args.buf)
      end
    end,
  })

  -- Re-hide when a buffer/window shows up (new split, switching files, ...).
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", "WinEnter", "FileType" }, {
    group = refresh_group,
    callback = function(args)
      if state.enabled then
        set_conceal(args.buf)
      end
    end,
  })

  -- Apply immediately to everything that is already open.
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      set_conceal(bufnr)
    end
  end

  return true
end

---Show the types again: drop the autocommands and every conceal mark.
---@return boolean
function M.disable()
  if not state.enabled then
    return false
  end
  state.enabled = false

  -- No more re-hiding.
  vim.api.nvim_clear_autocmds({ group = refresh_group })

  -- Clear our extmarks (this alone reveals the text) and reset 'conceallevel'.
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
