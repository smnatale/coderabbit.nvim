local M = {}

local config = require("coderabbit.config")
local utils = require("coderabbit.utils")
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

local function review_file_parts(path)
  local name = vim.fn.fnamemodify(path, ":t")
  local stamp, suffix = name:match("^(%d%d%d%d%-%d%d%-%d%d_%d%d%-%d%d%-%d%d)_?(%d*)%.json$")
  if not stamp then
    return name, 0, name
  end
  return stamp, tonumber(suffix) or 0, name
end

local function sorted_review_files(dir)
  local files = vim.fn.glob(dir .. "/*.json", false, true)
  table.sort(files, function(a, b)
    local a_stamp, a_suffix, a_name = review_file_parts(a)
    local b_stamp, b_suffix, b_name = review_file_parts(b)

    if a_stamp ~= b_stamp then
      return a_stamp < b_stamp
    end
    if a_suffix ~= b_suffix then
      return a_suffix < b_suffix
    end
    return a_name < b_name
  end)
  return files
end

local function max_entries()
  local history_cfg = config.get().history
  if type(history_cfg) ~= "table" then
    return nil
  end

  local raw_max = history_cfg.max_entries
  if type(raw_max) ~= "number" and type(raw_max) ~= "string" then
    return nil
  end

  local max = tonumber(raw_max)
  if not max or max < 1 then
    return nil
  end
  return math.floor(max)
end

local function prune_old_reviews(dir)
  local max = max_entries()
  if not max then
    return
  end

  local files = sorted_review_files(dir)
  local remove_count = #files - max
  for i = 1, remove_count do
    vim.fn.delete(files[i])
  end
end

local function next_filename(dir, base)
  local prefix = base .. "_"
  local max_suffix = -1

  for _, path in ipairs(vim.fn.glob(dir .. "/" .. base .. "*.json", false, true)) do
    local name = vim.fn.fnamemodify(path, ":t")
    if name == base .. ".json" then
      max_suffix = math.max(max_suffix, 0)
    elseif name:sub(1, #prefix) == prefix and name:sub(-5) == ".json" then
      local suffix = tonumber(name:sub(#prefix + 1, -6))
      if suffix then
        max_suffix = math.max(max_suffix, suffix)
      end
    end
  end

  if max_suffix < 0 then
    return base .. ".json"
  end
  return base .. "_" .. (max_suffix + 1) .. ".json"
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
  local filename = next_filename(dir, base)
  local path = dir .. "/" .. filename
  if not utils.write_file(path, json) then
    return nil
  end
  prune_old_reviews(dir)
  return filename
end

--- List all saved reviews for the current repo (summary only, no findings).
--- Returns entries sorted chronologically (oldest first), each with an
--- ordinal `id` field for display / lookup.
--- @return table[] Array of { id, timestamp, context, finding_count, filename }
function M.list()
  local dir = repo_dir()
  ensure_dir(dir)
  local files = sorted_review_files(dir)

  local entries = {}
  for i, path in ipairs(files) do
    local content = utils.read_file(path)
    if content then
      local data = utils.json_decode(content)
      if data then
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
  local files = sorted_review_files(dir)

  local path = files[id]
  if not path then
    return nil
  end
  local content = utils.read_file(path)
  if not content then
    return nil
  end
  local data = utils.json_decode(content)
  if not data then
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
  local files = sorted_review_files(dir)
  local ids = {}
  for i = 1, #files do
    table.insert(ids, tostring(i))
  end
  return ids
end

return M
