local M = {}

--- Safely decode a JSON string into a table.
--- @param raw string
--- @return table|nil
function M.json_decode(raw)
  local ok, data = pcall(vim.json.decode, raw)
  if not ok or type(data) ~= "table" then
    return nil
  end
  return data
end

--- Read an entire file into a string.
--- @param path string
--- @return string|nil
function M.read_file(path)
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  local content = file:read("*a")
  file:close()
  return content
end

--- Write a string to a file, replacing its contents.
--- @param path string
--- @param content string
--- @return boolean success
function M.write_file(path, content)
  local file = io.open(path, "w")
  if not file then
    return false
  end
  local ok = file:write(content)
  file:close()
  return ok ~= nil
end

--- Show a notification prefixed with "CodeRabbit: ".
--- @param msg string
--- @param level number|nil vim.log.levels value (default: INFO)
function M.notify(msg, level)
  vim.notify("CodeRabbit: " .. msg, level or vim.log.levels.INFO)
end

--- Format a count with a word, adding "s" for plurals.
--- e.g. pluralize(1, "finding") -> "1 finding"
---      pluralize(3, "finding") -> "3 findings"
--- @param n number
--- @param word string
--- @return string
function M.pluralize(n, word)
  return string.format("%d %s", n, n == 1 and word or word .. "s")
end

return M
