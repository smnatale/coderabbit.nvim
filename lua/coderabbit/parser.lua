local M = {}

--- Parse a single NDJSON line from `cr review --agent` output.
--- Returns a table with at least a `type` field, or nil on parse failure.
function M.parse_line(line)
  if not line or line == "" then
    return nil
  end
  local ok, data = pcall(vim.json.decode, line)
  if not ok or type(data) ~= "table" then
    return nil
  end
  return data
end

--- Strip the boilerplate prefix from codegenInstructions.
local PREFIX = "Verify each finding against the current code and only fix it if needed.\n\n"

function M.clean_message(raw)
  if not raw then
    return ""
  end
  if raw:sub(1, #PREFIX) == PREFIX then
    raw = raw:sub(#PREFIX + 1)
  end
  return raw
end

--- Convert a finding event into a vim.Diagnostic-compatible table.
--- @param finding table Raw finding from the CLI (type="finding")
--- @param cwd string Working directory for resolving relative paths
--- @param severity_map table Maps severity strings to vim.diagnostic.severity values
--- @return table|nil diagnostic The vim.Diagnostic table
--- @return string filepath Absolute file path for this diagnostic
function M.finding_to_diagnostic(finding, cwd, severity_map)
  if not finding.fileName then
    return nil, ""
  end

  local filepath = finding.fileName
  if not vim.startswith(filepath, "/") then
    filepath = cwd .. "/" .. filepath
  end

  local message = M.clean_message(finding.codegenInstructions)

  -- Extract line number from the message (e.g., "at line 42" or "around lines 65 - 71")
  local line = 0
  local end_line = nil

  local range_start, range_end = message:match("around lines (%d+)%s*%-%s*(%d+)")
  if range_start then
    line = tonumber(range_start) - 1
    end_line = tonumber(range_end) - 1
  else
    local single = message:match("at line (%d+)")
    if single then
      line = tonumber(single) - 1
    end
  end

  local severity = severity_map[finding.severity]
  if not severity then
    severity = vim.diagnostic.severity.INFO
  end

  local diagnostic = {
    lnum = line,
    end_lnum = end_line,
    col = 0,
    severity = severity,
    message = message,
    source = "coderabbit",
    user_data = {
      suggestions = finding.suggestions,
      severity_raw = finding.severity,
    },
  }

  return diagnostic, filepath
end

return M
