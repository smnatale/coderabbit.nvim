local M = {}

local base_dir = vim.fn.stdpath("data") .. "/coderabbit"

--- Override the base directory (for testing only).
function M._set_base_dir(dir)
  base_dir = dir
end

--- Resolve the git root for the current repo.
--- @return string|nil
local function git_root()
  local out = vim.fn.systemlist({ "git", "rev-parse", "--show-toplevel" })
  if vim.v.shell_error ~= 0 or not out[1] or out[1] == "" then
    return nil
  end
  return out[1]
end

--- Turn a git root path into a safe directory name.
--- e.g. /Users/sam/projects/my-repo -> Users-sam-projects-my-repo
---      C:\Users\me\repo             -> Users-me-repo
local function repo_key(root)
  local key = root
  -- Strip Windows drive letter (e.g. "C:")
  key = key:gsub("^%a:", "")
  -- Strip leading separators
  key = key:gsub("^[\\/]+", "")
  -- Replace all path separators with dashes
  key = key:gsub("[\\/]+", "-")
  return key
end

--- Return the per-repo review storage directory.
--- @return string
local function repo_dir()
  local root = git_root()
  if not root then
    return base_dir .. "/_unknown"
  end
  return base_dir .. "/" .. repo_key(root)
end

local function ensure_dir(dir)
  vim.fn.mkdir(dir, "p")
end

--- Format a timestamp for use as a filename.
--- @param ts number epoch seconds
--- @return string e.g. "2026-04-14_15-30-00"
local function ts_filename(ts)
  return os.date("%Y-%m-%d_%H-%M-%S", ts)
end

--- Save a completed review to disk.
--- @param findings table[] Array of { diagnostic, filepath }
--- @param context table|nil Review context metadata
--- @return string|nil filename The review filename (without path), or nil if nothing saved
function M.save(findings, context)
  if #findings == 0 then
    return nil
  end
  local dir = repo_dir()
  ensure_dir(dir)
  local ts = os.time()
  local entry = {
    findings = findings,
    context = context,
    timestamp = ts,
  }
  local json = vim.json.encode(entry)
  -- Avoid collisions when multiple reviews finish in the same second
  local base = ts_filename(ts)
  local filename = base .. ".json"
  local path = dir .. "/" .. filename
  local suffix = 1
  while vim.fn.filereadable(path) == 1 do
    filename = base .. "_" .. suffix .. ".json"
    path = dir .. "/" .. filename
    suffix = suffix + 1
  end
  local file = io.open(path, "w")
  if not file then
    return nil
  end
  local ok = file:write(json)
  file:close()
  if not ok then
    return nil
  end
  return filename
end

--- List all saved reviews for the current repo (summary only, no findings).
--- Returns entries sorted chronologically (oldest first), each with an
--- ordinal `id` field for display / lookup.
--- @return table[] Array of { id, timestamp, context, finding_count, filename }
function M.list()
  local dir = repo_dir()
  ensure_dir(dir)
  local files = vim.fn.glob(dir .. "/*.json", false, true)
  table.sort(files)

  local entries = {}
  for i, path in ipairs(files) do
    local file = io.open(path, "r")
    if file then
      local content = file:read("*a")
      file:close()
      local ok, data = pcall(vim.json.decode, content)
      if ok and type(data) == "table" then
        table.insert(entries, {
          id = i,
          timestamp = data.timestamp,
          context = data.context,
          finding_count = data.findings and #data.findings or 0,
          filename = vim.fn.fnamemodify(path, ":t"),
        })
      end
    end
  end
  return entries
end

--- Load a review by ordinal ID (1-indexed position in chronological order).
--- @param id number
--- @return table|nil
function M.load(id)
  local dir = repo_dir()
  local files = vim.fn.glob(dir .. "/*.json", false, true)
  table.sort(files)

  local path = files[id]
  if not path then
    return nil
  end
  local file = io.open(path, "r")
  if not file then
    return nil
  end
  local content = file:read("*a")
  file:close()
  local ok, data = pcall(vim.json.decode, content)
  if not ok or type(data) ~= "table" then
    return nil
  end
  data.id = id
  return data
end

--- Return list of existing review IDs as strings (for command completion).
--- @return string[]
function M.ids()
  local dir = repo_dir()
  ensure_dir(dir)
  local files = vim.fn.glob(dir .. "/*.json", false, true)
  local ids = {}
  for i = 1, #files do
    table.insert(ids, tostring(i))
  end
  return ids
end

return M
