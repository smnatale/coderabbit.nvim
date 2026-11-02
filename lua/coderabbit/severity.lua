local M = {}

M.names = { "critical", "major", "minor" }

local valid = {
  critical = true,
  major = true,
  minor = true,
}

local aliases = {
  error = "critical",
  err = "critical",
  warn = "major",
  warning = "major",
  info = "minor",
  information = "minor",
}

local diagnostic_to_raw = {
  [vim.diagnostic.severity.ERROR] = "critical",
  [vim.diagnostic.severity.WARN] = "major",
  [vim.diagnostic.severity.INFO] = "minor",
  [vim.diagnostic.severity.HINT] = "minor",
}

--- Normalize a user-facing severity name.
--- @param value string
--- @return string|nil
function M.normalize(value)
  if type(value) ~= "string" then
    return nil
  end
  value = value:lower()
  return valid[value] and value or aliases[value]
end

local function append_filter_values(values, out)
  local all = false
  for _, value in ipairs(values) do
    if type(value) ~= "string" then
      return "severity filters must be strings"
    end
    for part in value:gmatch("[^,%s]+") do
      local lower = part:lower()
      if lower == "all" or lower == "*" then
        all = true
      else
        local normalized = M.normalize(lower)
        if not normalized then
          return "invalid severity: " .. part
        end
        out[normalized] = true
      end
    end
  end
  return nil, all
end

--- Parse a severity filter from nil, string, or string array.
--- Returns nil for no filter / "all".
--- @param value string|string[]|table|nil
--- @return table|nil, string|nil
function M.parse_filter(value)
  if value == nil or value == false or value == "" then
    return nil
  end

  local filter = {}
  local err, all
  if type(value) == "string" then
    err, all = append_filter_values({ value }, filter)
  elseif type(value) == "table" then
    local has_named_keys = false
    for _, name in ipairs(M.names) do
      if value[name] ~= nil then
        has_named_keys = true
        if value[name] then
          filter[name] = true
        end
      end
    end
    if not has_named_keys then
      err, all = append_filter_values(value, filter)
    end
  else
    return nil, "severity filter must be a string or list"
  end

  if err then
    return nil, err
  end
  if all or not next(filter) then
    return nil
  end
  return filter
end

--- Human-readable filter label, sorted by CodeRabbit severity order.
--- @param filter table|nil
--- @return string|nil
function M.describe(filter)
  if not filter then
    return nil
  end
  local parts = {}
  for _, name in ipairs(M.names) do
    if filter[name] then
      table.insert(parts, name)
    end
  end
  return #parts > 0 and table.concat(parts, ", ") or nil
end

local function raw_severity(finding)
  local diagnostic = finding and finding.diagnostic
  local user_data = diagnostic and diagnostic.user_data
  local raw = user_data and user_data.severity_raw
  local normalized = M.normalize(raw)
  if normalized then
    return normalized
  end
  return diagnostic and diagnostic_to_raw[diagnostic.severity] or nil
end

--- Check whether a finding matches a parsed severity filter.
--- @param finding table
--- @param filter table|nil
--- @return boolean
function M.matches(finding, filter)
  if not filter then
    return true
  end
  local raw = raw_severity(finding)
  return raw ~= nil and filter[raw] == true
end

--- Return findings matching a parsed severity filter.
--- @param findings table[]
--- @param filter table|nil
--- @return table[]
function M.filter_findings(findings, filter)
  if not filter then
    return findings
  end

  local filtered = {}
  for _, finding in ipairs(findings or {}) do
    if M.matches(finding, filter) then
      table.insert(filtered, finding)
    end
  end
  return filtered
end

return M
