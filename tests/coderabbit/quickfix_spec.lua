local quickfix = require("coderabbit.quickfix")
local h = require("tests.helpers")
local test, eq = h.test, h.eq
local E, W, I = h.E, h.W, h.I

-- ──────────────────────────────────────────────────────────
-- Tests: severity_to_type
-- ──────────────────────────────────────────────────────────

test("severity_to_type: ERROR -> E", function()
  eq(quickfix.severity_to_type(E), "E")
end)

test("severity_to_type: WARN -> W", function()
  eq(quickfix.severity_to_type(W), "W")
end)

test("severity_to_type: INFO -> I", function()
  eq(quickfix.severity_to_type(I), "I")
end)

test("severity_to_type: HINT -> I (fallback)", function()
  eq(quickfix.severity_to_type(vim.diagnostic.severity.HINT), "I")
end)

-- ──────────────────────────────────────────────────────────
-- Tests: findings_to_qf_items
-- ──────────────────────────────────────────────────────────

test("findings_to_qf_items: empty findings returns empty", function()
  local items = quickfix.findings_to_qf_items({})
  eq(#items, 0)
end)

test("findings_to_qf_items: single finding produces correct entry", function()
  local findings = { h.finding("/tmp/repo/foo.lua", 41, E, "null check", {}) }
  local items = quickfix.findings_to_qf_items(findings)
  eq(#items, 1)
  eq(items[1].filename, "/tmp/repo/foo.lua")
  eq(items[1].lnum, 42) -- 0-indexed -> 1-indexed
  eq(items[1].col, 1) -- col 0 -> 1
  eq(items[1].type, "E")
end)

test("findings_to_qf_items: lnum 0 becomes 1", function()
  local findings = { h.finding("/tmp/repo/a.lua", 0, I, "file-level issue") }
  local items = quickfix.findings_to_qf_items(findings)
  eq(items[1].lnum, 1)
end)

test("findings_to_qf_items: severity maps correctly", function()
  local findings = {
    h.finding("/tmp/repo/a.lua", 0, E, "error"),
    h.finding("/tmp/repo/b.lua", 0, W, "warn"),
    h.finding("/tmp/repo/c.lua", 0, I, "info"),
  }
  local items = quickfix.findings_to_qf_items(findings)
  eq(items[1].type, "E")
  eq(items[2].type, "W")
  eq(items[3].type, "I")
end)

test("findings_to_qf_items: text includes severity_raw prefix", function()
  local findings = { h.finding("/tmp/repo/a.lua", 10, W, "missing import") }
  local items = quickfix.findings_to_qf_items(findings)
  -- helpers.finding sets severity_raw = "minor" by default
  eq(items[1].text, "[minor] missing import")
end)

test("findings_to_qf_items: multi-line message uses first line only", function()
  local findings = { h.finding("/tmp/repo/a.lua", 5, E, "first line\nsecond line\nthird") }
  local items = quickfix.findings_to_qf_items(findings)
  eq(items[1].text, "[minor] first line")
end)

test("findings_to_qf_items: missing severity_raw omits prefix", function()
  local findings = {
    {
      filepath = "/tmp/repo/a.lua",
      diagnostic = {
        lnum = 0,
        col = 0,
        severity = E,
        message = "bare finding",
        source = "coderabbit",
      },
    },
  }
  local items = quickfix.findings_to_qf_items(findings)
  eq(items[1].text, "bare finding")
end)

test("findings_to_qf_items: multiple findings produce correct count", function()
  local findings = {
    h.finding("/tmp/repo/a.lua", 1, E, "one"),
    h.finding("/tmp/repo/b.lua", 2, W, "two"),
    h.finding("/tmp/repo/c.lua", 3, I, "three"),
  }
  local items = quickfix.findings_to_qf_items(findings)
  eq(#items, 3)
end)

-- ──────────────────────────────────────────────────────────
-- Tests: populate
-- ──────────────────────────────────────────────────────────

local storage = require("coderabbit.storage")
local populate_test_dir = vim.fn.tempname() .. "/coderabbit_populate_test"
storage._set_base_dir(populate_test_dir)

-- Save a review so storage.load(1) returns it.
local saved_findings = {
  h.finding("/tmp/repo/a.lua", 10, E, "error here"),
  h.finding("/tmp/repo/b.lua", 20, W, "warning here"),
}
storage.save(saved_findings, h.context())

test("populate: valid id populates quickfix from stored review", function()
  quickfix.populate(1)
  vim.cmd("cclose")
  local qf = vim.fn.getqflist({ title = 1, items = 1 })
  eq(qf.title, "CodeRabbit Review #1")
  eq(#qf.items, 2)
end)

test("populate: invalid id does not error and leaves quickfix unchanged", function()
  -- Set a known state first
  quickfix.set({ h.finding("/tmp/repo/x.lua", 0, I, "baseline") }, { title = "Baseline" })
  vim.cmd("cclose")
  -- Call with non-existent id
  quickfix.populate(999)
  local qf = vim.fn.getqflist({ title = 1, items = 1 })
  -- Should remain unchanged (populate returns early with a warning)
  eq(qf.title, "Baseline")
  eq(#qf.items, 1)
end)

test("populate: nil id with no review context warns and leaves quickfix unchanged", function()
  -- Set a known state first
  quickfix.set({ h.finding("/tmp/repo/x.lua", 0, I, "baseline") }, { title = "Baseline" })
  vim.cmd("cclose")
  -- Clear review state so get_results() returns {} and get_context() returns nil
  require("coderabbit.review").clear()
  quickfix.populate(nil)
  local qf = vim.fn.getqflist({ title = 1, items = 1 })
  -- Should remain unchanged (populate returns early with a warning)
  eq(qf.title, "Baseline")
  eq(#qf.items, 1)
end)

-- ──────────────────────────────────────────────────────────
-- Tests: set
-- ──────────────────────────────────────────────────────────

test("set: populates quickfix list with items", function()
  local findings = {
    h.finding("/tmp/repo/a.lua", 10, E, "error here"),
    h.finding("/tmp/repo/b.lua", 20, W, "warning here"),
  }
  quickfix.set(findings, { title = "Test Review" })
  vim.cmd("cclose")
  local qf = vim.fn.getqflist({ title = 1, items = 1 })
  eq(qf.title, "Test Review")
  eq(#qf.items, 2)
end)

test("set: empty findings clears quickfix list", function()
  quickfix.set({ h.finding("/tmp/repo/a.lua", 0, E, "x") })
  quickfix.set({})
  vim.cmd("cclose")
  local qf = vim.fn.getqflist({ items = 1 })
  eq(#qf.items, 0)
end)

test("set: replaces existing quickfix content", function()
  quickfix.set({ h.finding("/tmp/repo/a.lua", 0, E, "first") })
  quickfix.set({ h.finding("/tmp/repo/b.lua", 1, W, "second") })
  vim.cmd("cclose")
  local qf = vim.fn.getqflist({ items = 1 })
  eq(#qf.items, 1)
end)

h.summary()

-- Clean up temp dir after all tests complete
vim.fn.delete(populate_test_dir, "rf")
