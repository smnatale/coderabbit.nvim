local M = {}

local function format_time(timestamp)
  if not timestamp then
    return "unknown"
  end
  return os.date("%Y-%m-%d %H:%M", timestamp)
end

--- Format a storage entry into a display string for the picker.
--- @param entry table { id, timestamp, context, finding_count }
--- @return string
function M.format_entry(entry)
  local ctx = entry.context or {}
  local parts = { string.format("#%d", entry.id) }
  table.insert(parts, format_time(entry.timestamp))
  if ctx.current_branch then
    table.insert(parts, ctx.current_branch)
  end
  if ctx.review_type then
    table.insert(parts, ctx.review_type)
  end
  table.insert(parts, string.format("%d finding%s", entry.finding_count, entry.finding_count == 1 and "" or "s"))
  return table.concat(parts, "  │  ")
end

function M.open()
  local storage = require("coderabbit.storage")
  local entries = storage.list()

  if #entries == 0 then
    vim.notify("CodeRabbit: No saved reviews yet", vim.log.levels.INFO)
    return
  end

  vim.ui.select(entries, {
    prompt = "CodeRabbit Review History",
    format_item = M.format_entry,
  }, function(entry)
    if entry then
      require("coderabbit.show").open(entry.id)
    end
  end)
end

return M
