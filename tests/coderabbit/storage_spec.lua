local storage = require("coderabbit.storage")
local h = require("tests.helpers")
local test, eq = h.test, h.eq

local test_dir = vim.fn.tempname() .. "/coderabbit_test"
storage._set_base_dir(test_dir)

local function cleanup()
  vim.fn.delete(test_dir, "rf")
end

local function make_findings(n)
  local findings = {}
  for i = 1, n do
    table.insert(findings, h.finding(h.CWD .. "/file" .. i .. ".ts", i * 10, h.W, "finding " .. i))
  end
  return findings
end

-- ──────────────────────────────────────────────────────────
-- Tests (table-driven where possible)
-- ──────────────────────────────────────────────────────────

test("save: returns nil when findings empty", function()
  cleanup()
  eq(storage.save({}, h.context()), nil)
end)

test("save: returns filename for non-empty findings", function()
  cleanup()
  local result = storage.save(make_findings(2), h.context())
  assert(result ~= nil, "expected filename")
  assert(result:match("%.json$"), "expected .json extension")
end)

test("list: returns empty table when no reviews", function()
  cleanup()
  eq(#storage.list(), 0)
end)

test("list: returns saved reviews with ordinal IDs", function()
  cleanup()
  storage.save(make_findings(1), h.context("feat/a"))
  storage.save(make_findings(3), h.context("feat/b"))
  local entries = storage.list()
  eq(#entries, 2)
  eq(entries[1].id, 1)
  eq(entries[2].id, 2)
  eq(entries[1].finding_count, 1)
  eq(entries[2].finding_count, 3)
end)

test("load: returns nil for non-existent ID", function()
  cleanup()
  eq(storage.load(999), nil)
end)

test("load: returns full review data by ordinal ID", function()
  cleanup()
  storage.save(make_findings(2), h.context("main"))
  local entry = storage.load(1)
  assert(entry ~= nil, "expected entry")
  eq(#entry.findings, 2)
  eq(entry.context.current_branch, "main")
  eq(entry.id, 1)
end)

test("ids: returns string IDs for completion", function()
  cleanup()
  storage.save(make_findings(1), h.context())
  storage.save(make_findings(1), h.context())
  local ids = storage.ids()
  eq(#ids, 2)
  eq(ids[1], "1")
  eq(ids[2], "2")
end)

test("ids: returns empty when no reviews", function()
  cleanup()
  eq(#storage.ids(), 0)
end)

cleanup()
h.summary()
