local history = require("coderabbit.history")
local h = require("tests.helpers")
local test, eq, has = h.test, h.eq, h.has

-- ──────────────────────────────────────────────────────────
-- Tests: render (table-driven)
-- ──────────────────────────────────────────────────────────

local sample = {
  { id = 1, timestamp = os.time(), context = { review_type = "all", current_branch = "main" }, finding_count = 5 },
  {
    id = 2,
    timestamp = os.time(),
    context = { review_type = "committed", current_branch = "feat/x" },
    finding_count = 2,
  },
}

for _, case in ipairs({
  { "empty history shows no-reviews message", {}, { "No saved reviews yet" } },
  { "header is present", {}, { "# CodeRabbit Review History" } },
  {
    "entries show review ID and metadata",
    sample,
    { "Review #1", "Review #2", "**Branch:** main", "**Branch:** feat/x", "**Findings:** 5", "**Findings:** 2" },
  },
  { "shows review count", sample, { "2 reviews saved" } },
  { "single review uses singular form", { sample[1] }, { "1 review saved" } },
}) do
  test("render: " .. case[1], function()
    local lines = history.render(case[2])
    for _, s in ipairs(case[3]) do
      assert(has(lines, s), "expected: " .. s)
    end
  end)
end

-- ──────────────────────────────────────────────────────────
-- Tests: buffer management
-- ──────────────────────────────────────────────────────────

local _orig_list

local function with_storage(entries, fn)
  history._reset()
  local storage = require("coderabbit.storage")
  _orig_list = _orig_list or storage.list
  storage.list = function()
    return entries
  end
  local ok, err = pcall(fn)
  storage.list = _orig_list
  history._reset()
  if not ok then
    error(err, 2)
  end
end

local one_entry = { sample[1] }

test("open: creates scratch buffer with correct options", function()
  with_storage(one_entry, function()
    history.open()
    local bufnr = history._get_buf_id()
    assert(bufnr and vim.api.nvim_buf_is_valid(bufnr), "expected valid buffer")
    eq(vim.api.nvim_get_option_value("buftype", { buf = bufnr }), "nofile")
    eq(vim.api.nvim_get_option_value("filetype", { buf = bufnr }), "markdown")
    eq(vim.api.nvim_get_option_value("modifiable", { buf = bufnr }), false)
  end)
end)

test("open: buffer content contains history", function()
  with_storage(one_entry, function()
    history.open()
    local buf_lines = vim.api.nvim_buf_get_lines(history._get_buf_id(), 0, -1, false)
    assert(has(buf_lines, "Review History"), "expected header")
    assert(has(buf_lines, "Review #1"), "expected review entry")
  end)
end)

test("close: removes buffer", function()
  with_storage(one_entry, function()
    history.open()
    local bufnr = history._get_buf_id()
    history.close()
    eq(history._get_buf_id(), nil)
    assert(not vim.api.nvim_buf_is_valid(bufnr), "expected buffer deleted")
  end)
end)

test("is_open: false when no buffer, true when visible", function()
  eq(history.is_open(), false)
  with_storage(one_entry, function()
    history.open()
    eq(history.is_open(), true)
  end)
end)

h.summary()
