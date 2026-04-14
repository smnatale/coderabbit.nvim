local M = {}

local pass, fail = 0, 0

function M.test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    pass = pass + 1
    print("  PASS  " .. name)
  else
    fail = fail + 1
    print("  FAIL  " .. name .. "\n        " .. err)
  end
end

function M.eq(a, b)
  if a ~= b then
    error(string.format("expected %s, got %s", vim.inspect(b), vim.inspect(a)), 2)
  end
end

function M.summary()
  print(string.format("\n%d passed, %d failed", pass, fail))
  if fail > 0 then
    vim.cmd("cq1")
  end
end

-- Severity shortcuts
M.E = vim.diagnostic.severity.ERROR
M.W = vim.diagnostic.severity.WARN
M.I = vim.diagnostic.severity.INFO

M.severity_map = {
  critical = M.E,
  major = M.W,
  minor = M.I,
}

M.CWD = "/tmp/repo"

--- True if any line in `lines` contains `pattern` (plain match).
function M.has(lines, pattern)
  for _, line in ipairs(lines) do
    if line:find(pattern, 1, true) then
      return true
    end
  end
  return false
end

--- Count lines matching Lua pattern `pat`.
function M.count(lines, pat)
  local n = 0
  for _, line in ipairs(lines) do
    if line:match(pat) then
      n = n + 1
    end
  end
  return n
end

--- Build a { filepath, diagnostic } finding table.
function M.finding(path, lnum, sev, msg, suggestions, end_lnum)
  return {
    filepath = path,
    diagnostic = {
      lnum = lnum,
      end_lnum = end_lnum,
      col = 0,
      severity = sev,
      message = msg,
      source = "coderabbit",
      user_data = { suggestions = suggestions or {}, severity_raw = "minor" },
    },
  }
end

--- Build a vim.Diagnostic-shaped table.
function M.diag(lnum, sev, msg, suggestions, end_lnum)
  local d = { lnum = lnum, col = 0, severity = sev, message = msg, source = "coderabbit" }
  if end_lnum then
    d.end_lnum = end_lnum
  end
  if suggestions then
    d.user_data = { suggestions = suggestions }
  end
  return d
end

--- Build a review context table.
function M.context(branch)
  return {
    cwd = M.CWD,
    review_type = "all",
    current_branch = branch or "main",
    base_branch = "main",
    base_commit = "abc123",
  }
end

--- Create a scratch buffer with the given lines.
function M.make_buf(lines)
  local bufnr = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  return bufnr
end

--- Create a temp file, load it into a buffer, return (bufnr, filepath, tmpdir).
function M.make_temp_buf(relpath)
  local tmpdir = vim.fn.tempname()
  vim.fn.mkdir(tmpdir, "p")
  local filepath = tmpdir .. "/" .. relpath
  vim.fn.mkdir(vim.fn.fnamemodify(filepath, ":h"), "p")
  vim.fn.writefile({ "line1", "line2", "line3" }, filepath)
  vim.cmd("edit " .. vim.fn.fnameescape(filepath))
  return vim.fn.bufnr(filepath), filepath, tmpdir
end

return M
