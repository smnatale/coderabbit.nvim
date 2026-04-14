local M = {}

local buf_id = nil
local line_map = {}

local function format_time(timestamp)
  if not timestamp then
    return "unknown"
  end
  return os.date("%Y-%m-%d %H:%M", timestamp)
end

--- Render the history list into markdown lines.
--- @param entries table[] Array of { id, timestamp, context, finding_count }
--- @return string[]
function M.render(entries)
  local lines = {}

  table.insert(lines, "# CodeRabbit Review History")
  table.insert(lines, "")

  if #entries == 0 then
    table.insert(lines, "*No saved reviews yet.*")
    return lines
  end

  table.insert(lines, string.format("%d review%s saved.", #entries, #entries == 1 and "" or "s"))
  table.insert(lines, "Press `<CR>` on a review to open it, or `q` to close.")
  table.insert(lines, "")
  table.insert(lines, "---")
  table.insert(lines, "")

  for _, entry in ipairs(entries) do
    local ctx = entry.context or {}
    local parts = { string.format("### Review #%d", entry.id) }
    table.insert(lines, parts[1])
    table.insert(lines, "")

    local meta = {}
    table.insert(meta, "**Date:** " .. format_time(entry.timestamp))
    if ctx.review_type then
      table.insert(meta, "**Type:** " .. ctx.review_type)
    end
    if ctx.current_branch then
      table.insert(meta, "**Branch:** " .. ctx.current_branch)
    end
    table.insert(meta, string.format("**Findings:** %d", entry.finding_count))
    table.insert(lines, table.concat(meta, " | "))
    table.insert(lines, "")
  end

  return lines
end

--- Map review IDs to their header line numbers for <CR> navigation.
--- @param entries table[]
--- @param lines string[]
--- @return table<number, number> Map of line number (1-indexed) -> review ID
local function build_line_map(entries, lines)
  local map = {}
  for lnum, line in ipairs(lines) do
    local id = line:match("^### Review #(%d+)")
    if id then
      map[lnum] = tonumber(id)
    end
  end
  return map
end

function M.open()
  local storage = require("coderabbit.storage")
  local entries = storage.list()
  local lines = M.render(entries)
  line_map = build_line_map(entries, lines)

  -- Reuse existing buffer if visible
  if buf_id and vim.api.nvim_buf_is_valid(buf_id) then
    local winid = vim.fn.bufwinid(buf_id)
    if winid ~= -1 then
      vim.api.nvim_set_current_win(winid)
    else
      vim.cmd("vsplit")
      vim.api.nvim_win_set_buf(0, buf_id)
    end
    vim.api.nvim_set_option_value("modifiable", true, { buf = buf_id })
    vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
    vim.api.nvim_set_option_value("modifiable", false, { buf = buf_id })
    return
  end

  buf_id = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf_id, "coderabbit://history")
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf_id })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf_id })
  vim.api.nvim_set_option_value("swapfile", false, { buf = buf_id })
  vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf_id })

  vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, lines)
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf_id })

  vim.cmd("vsplit")
  vim.api.nvim_win_set_buf(0, buf_id)

  vim.api.nvim_set_option_value("number", false, { win = 0 })
  vim.api.nvim_set_option_value("relativenumber", false, { win = 0 })
  vim.api.nvim_set_option_value("signcolumn", "no", { win = 0 })
  vim.api.nvim_set_option_value("wrap", true, { win = 0 })
  vim.api.nvim_set_option_value("linebreak", true, { win = 0 })
  vim.api.nvim_set_option_value("spell", false, { win = 0 })
  vim.api.nvim_set_option_value("conceallevel", 2, { win = 0 })

  vim.keymap.set("n", "q", function()
    M.close()
  end, { buffer = buf_id, nowait = true, silent = true })

  vim.keymap.set("n", "<CR>", function()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local lnum = cursor[1]
    -- Find the nearest header at or above the cursor
    local id = nil
    for l = lnum, 1, -1 do
      if line_map[l] then
        id = line_map[l]
        break
      end
    end
    if id then
      M.close()
      require("coderabbit.show").open(id)
    end
  end, { buffer = buf_id, nowait = true, silent = true })

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf_id,
    once = true,
    callback = function()
      buf_id = nil
    end,
  })
end

function M.close()
  local id = buf_id
  buf_id = nil
  if not id or not vim.api.nvim_buf_is_valid(id) then
    return
  end
  local winid = vim.fn.bufwinid(id)
  if winid ~= -1 then
    vim.api.nvim_win_close(winid, true)
  end
  if vim.api.nvim_buf_is_valid(id) then
    vim.api.nvim_buf_delete(id, { force = true })
  end
end

function M.is_open()
  return buf_id ~= nil and vim.api.nvim_buf_is_valid(buf_id) and vim.fn.bufwinid(buf_id) ~= -1
end

--- Exposed for testing.
M._get_buf_id = function()
  return buf_id
end

M._reset = function()
  if buf_id and vim.api.nvim_buf_is_valid(buf_id) then
    vim.api.nvim_buf_delete(buf_id, { force = true })
  end
  buf_id = nil
end

return M
