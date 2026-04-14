local history = require("coderabbit.history")
local h = require("tests.helpers")
local test, eq = h.test, h.eq

-- ──────────────────────────────────────────────────────────
-- Tests: format_entry
-- ──────────────────────────────────────────────────────────

local sample = {
  { id = 1, timestamp = os.time(), context = { review_type = "all", current_branch = "main" }, finding_count = 5 },
  {
    id = 2,
    timestamp = os.time(),
    context = { review_type = "committed", current_branch = "feat/x" },
    finding_count = 1,
  },
  { id = 3, timestamp = os.time(), context = {}, finding_count = 0 },
}

test("format_entry: includes review ID", function()
  assert(history.format_entry(sample[1]):find("#1", 1, true), "expected #1")
end)

test("format_entry: includes branch", function()
  assert(history.format_entry(sample[1]):find("main", 1, true), "expected branch")
end)

test("format_entry: includes review type", function()
  assert(history.format_entry(sample[2]):find("committed", 1, true), "expected type")
end)

test("format_entry: includes finding count", function()
  assert(history.format_entry(sample[1]):find("5 findings", 1, true), "expected count")
end)

test("format_entry: singular finding", function()
  assert(history.format_entry(sample[2]):find("1 finding", 1, true), "expected singular")
  assert(not history.format_entry(sample[2]):find("1 findings", 1, true), "unexpected plural")
end)

test("format_entry: handles missing context fields", function()
  local s = history.format_entry(sample[3])
  assert(s:find("#3", 1, true), "expected ID")
  assert(s:find("0 findings", 1, true), "expected count")
end)

-- ──────────────────────────────────────────────────────────
-- Tests: open
-- ──────────────────────────────────────────────────────────

test("open: notifies when no reviews", function()
  local storage = require("coderabbit.storage")
  local orig_list = storage.list
  storage.list = function()
    return {}
  end
  local notified = false
  local orig_notify = vim.notify
  vim.notify = function(msg)
    if msg:find("No saved reviews") then
      notified = true
    end
  end
  history.open()
  vim.notify = orig_notify
  storage.list = orig_list
  assert(notified, "expected notification")
end)

test("open: calls vim.ui.select with entries", function()
  local storage = require("coderabbit.storage")
  local orig_list = storage.list
  storage.list = function()
    return { sample[1] }
  end
  local called_items
  local orig_select = vim.ui.select
  vim.ui.select = function(items)
    called_items = items
  end
  history.open()
  vim.ui.select = orig_select
  storage.list = orig_list
  assert(called_items, "expected vim.ui.select to be called")
  eq(#called_items, 1)
  eq(called_items[1].id, 1)
end)

h.summary()
