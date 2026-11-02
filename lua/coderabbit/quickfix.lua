local M = {}

local utils = require("coderabbit.utils")
local severity_filter = require("coderabbit.severity")

local severity_types = {
  [vim.diagnostic.severity.ERROR] = "E",
  [vim.diagnostic.severity.WARN] = "W",
}

--- Map vim.diagnostic.severity to quickfix type character.
--- @param severity number
--- @return string "E", "W", or "I"
function M.severity_to_type(severity)
  return severity_types[severity] or "I"
end

--- Convert findings to quickfix items (pure function, no side effects).
--- @param findings table[] Array of { diagnostic, filepath }
--- @param opts table|nil { severity_filter = table }
--- @return table[] Array of { filename, lnum, col, text, type } for setqflist()
function M.findings_to_qf_items(findings, opts)
  opts = opts or {}
  findings = severity_filter.filter_findings(findings, opts.severity_filter)

  local items = {}
  for _, f in ipairs(findings) do
    local d = f.diagnostic
    local raw = d.user_data and d.user_data.severity_raw
    local prefix = raw and ("[" .. raw .. "] ") or ""
    local first_line = d.message:match("^([^\n]*)") or d.message
    table.insert(items, {
      filename = f.filepath,
      lnum = d.lnum + 1,
      col = d.col + 1,
      text = prefix .. first_line,
      type = M.severity_to_type(d.severity),
    })
  end
  return items
end

--- Populate the quickfix list from findings and open the window.
--- @param findings table[] Array of { diagnostic, filepath }
--- @param opts table|nil { title = string, severity_filter = table|string|string[] }
function M.set(findings, opts)
  opts = opts or {}
  local filter, err = severity_filter.parse_filter(opts.severity_filter)
  if err then
    utils.notify("Invalid severity filter: " .. err, vim.log.levels.ERROR)
    return
  end

  local title = opts.title or "CodeRabbit Review"
  local filter_label = severity_filter.describe(filter)
  if filter_label then
    title = title .. " (" .. filter_label .. ")"
  end

  local items = M.findings_to_qf_items(findings, { severity_filter = filter })
  vim.fn.setqflist({}, "r", {
    title = title,
    items = items,
  })
  vim.cmd("copen")
end

--- Populate quickfix from current review or a saved review by ID.
--- @param id number|nil Review ID (nil = current in-memory findings)
--- @param opts table|nil { severity_filter = table|string|string[] }
function M.populate(id, opts)
  opts = opts or {}
  local findings, title

  local review = require("coderabbit.review")

  if id then
    local entry = review.get_review(id)
    if not entry then
      utils.notify("Review #" .. id .. " not found", vim.log.levels.WARN)
      return
    end
    findings = type(entry.findings) == "table" and entry.findings or {}
    title = "CodeRabbit Review #" .. id
  else
    findings = review.get_results()
    if #findings == 0 and not review.get_context() then
      utils.notify("No review results. Run :CodeRabbitReview first", vim.log.levels.WARN)
      return
    end
    title = "CodeRabbit Review"
  end

  local filter_arg
  if opts.severity_filter ~= nil then
    filter_arg = opts.severity_filter
  else
    filter_arg = require("coderabbit.config").get().quickfix.severity_filter
  end

  M.set(findings, { title = title, severity_filter = filter_arg })
end

return M
