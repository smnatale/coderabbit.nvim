local actions = require("coderabbit.actions")
local diagnostics = require("coderabbit.diagnostics")

local pass, fail = 0, 0

local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    pass = pass + 1
    print("  PASS  " .. name)
  else
    fail = fail + 1
    print("  FAIL  " .. name .. "\n        " .. err)
  end
end

local function eq(a, b)
  if a ~= b then
    error(string.format("expected %s, got %s", vim.inspect(b), vim.inspect(a)), 2)
  end
end

local function reset()
  diagnostics.clear()
end

-- Helper: create a scratch buffer with given lines
local function make_buf(lines)
  local bufnr = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  return bufnr
end

-- ──────────────────────────────────────────────────────────
-- Tests: apply
-- ──────────────────────────────────────────────────────────

test("apply: replaces a single line", function()
  reset()
  local bufnr = make_buf({ "line0", "line1", "line2", "line3" })

  vim.diagnostic.set(diagnostics.ns, bufnr, {
    {
      lnum = 1,
      col = 0,
      severity = vim.diagnostic.severity.WARN,
      message = "fix this",
      source = "coderabbit",
      user_data = { suggestions = { "fixed_line1" } },
    },
  })

  actions.apply(bufnr, 1, nil, "fixed_line1", "fix this")

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  eq(#lines, 4)
  eq(lines[1], "line0")
  eq(lines[2], "fixed_line1")
  eq(lines[3], "line2")
  eq(lines[4], "line3")
end)

test("apply: replaces a multi-line range", function()
  reset()
  local bufnr = make_buf({ "line0", "line1", "line2", "line3", "line4" })

  vim.diagnostic.set(diagnostics.ns, bufnr, {
    {
      lnum = 1,
      end_lnum = 3,
      col = 0,
      severity = vim.diagnostic.severity.ERROR,
      message = "replace these",
      source = "coderabbit",
      user_data = { suggestions = { "new1\nnew2" } },
    },
  })

  actions.apply(bufnr, 1, 3, "new1\nnew2", "replace these")

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  -- 5 original lines, replaced 3 (index 1-3) with 2 = 4 lines
  eq(#lines, 4)
  eq(lines[1], "line0")
  eq(lines[2], "new1")
  eq(lines[3], "new2")
  eq(lines[4], "line4")
end)

test("apply: removes the applied diagnostic", function()
  reset()
  local bufnr = make_buf({ "line0", "line1", "line2" })

  vim.diagnostic.set(diagnostics.ns, bufnr, {
    {
      lnum = 1,
      col = 0,
      severity = vim.diagnostic.severity.WARN,
      message = "fix this",
      source = "coderabbit",
      user_data = { suggestions = { "fixed" } },
    },
  })
  eq(#vim.diagnostic.get(bufnr, { namespace = diagnostics.ns }), 1)

  actions.apply(bufnr, 1, nil, "fixed", "fix this")

  eq(#vim.diagnostic.get(bufnr, { namespace = diagnostics.ns }), 0)
end)

test("apply: preserves other diagnostics", function()
  reset()
  local bufnr = make_buf({ "line0", "line1", "line2", "line3" })

  vim.diagnostic.set(diagnostics.ns, bufnr, {
    {
      lnum = 1,
      col = 0,
      severity = vim.diagnostic.severity.WARN,
      message = "first issue",
      source = "coderabbit",
      user_data = { suggestions = { "fix1" } },
    },
    {
      lnum = 3,
      col = 0,
      severity = vim.diagnostic.severity.INFO,
      message = "second issue",
      source = "coderabbit",
      user_data = { suggestions = { "fix2" } },
    },
  })
  eq(#vim.diagnostic.get(bufnr, { namespace = diagnostics.ns }), 2)

  actions.apply(bufnr, 1, nil, "fix1", "first issue")

  local remaining = vim.diagnostic.get(bufnr, { namespace = diagnostics.ns })
  eq(#remaining, 1)
  eq(remaining[1].message, "second issue")
end)

-- ──────────────────────────────────────────────────────────
-- Tests: get_actions
-- ──────────────────────────────────────────────────────────

test("get_actions: no actions for empty suggestions", function()
  reset()
  local bufnr = make_buf({ "line0", "line1" })

  vim.diagnostic.set(diagnostics.ns, bufnr, {
    {
      lnum = 0,
      col = 0,
      severity = vim.diagnostic.severity.INFO,
      message = "no fix available",
      source = "coderabbit",
      user_data = { suggestions = {} },
    },
  })

  local result = actions.get_actions(bufnr, {
    start = { line = 0 },
    ["end"] = { line = 0 },
  })
  eq(#result, 0)
end)

test("get_actions: no actions when user_data has no suggestions", function()
  reset()
  local bufnr = make_buf({ "line0" })

  vim.diagnostic.set(diagnostics.ns, bufnr, {
    {
      lnum = 0,
      col = 0,
      severity = vim.diagnostic.severity.INFO,
      message = "bare diagnostic",
      source = "coderabbit",
    },
  })

  local result = actions.get_actions(bufnr, {
    start = { line = 0 },
    ["end"] = { line = 0 },
  })
  eq(#result, 0)
end)

test("get_actions: one action per suggestion", function()
  reset()
  local bufnr = make_buf({ "line0", "line1" })

  vim.diagnostic.set(diagnostics.ns, bufnr, {
    {
      lnum = 0,
      col = 0,
      severity = vim.diagnostic.severity.WARN,
      message = "issue here",
      source = "coderabbit",
      user_data = { suggestions = { "fix_a", "fix_b" } },
    },
  })

  local result = actions.get_actions(bufnr, {
    start = { line = 0 },
    ["end"] = { line = 0 },
  })
  eq(#result, 2)
  assert(result[1].title:match("1/2"), "first action should say 1/2")
  assert(result[2].title:match("2/2"), "second action should say 2/2")
end)

test("get_actions: only returns actions for diagnostics in range", function()
  reset()
  local bufnr = make_buf({ "line0", "line1", "line2", "line3" })

  vim.diagnostic.set(diagnostics.ns, bufnr, {
    {
      lnum = 0,
      col = 0,
      severity = vim.diagnostic.severity.WARN,
      message = "issue at 0",
      source = "coderabbit",
      user_data = { suggestions = { "fix0" } },
    },
    {
      lnum = 3,
      col = 0,
      severity = vim.diagnostic.severity.WARN,
      message = "issue at 3",
      source = "coderabbit",
      user_data = { suggestions = { "fix3" } },
    },
  })

  -- Query only line 0
  local result = actions.get_actions(bufnr, {
    start = { line = 0 },
    ["end"] = { line = 0 },
  })
  eq(#result, 1)
  eq(result[1].command.arguments[1].lnum, 0)
end)

test("get_actions: multi-line diagnostic found when cursor is in the middle", function()
  reset()
  local bufnr = make_buf({ "a", "b", "c", "d", "e" })

  vim.diagnostic.set(diagnostics.ns, bufnr, {
    {
      lnum = 1,
      end_lnum = 3,
      col = 0,
      severity = vim.diagnostic.severity.ERROR,
      message = "spans 1-3",
      source = "coderabbit",
      user_data = { suggestions = { "replacement" } },
    },
  })

  -- Cursor on line 2 (middle of the diagnostic range)
  local result = actions.get_actions(bufnr, {
    start = { line = 2 },
    ["end"] = { line = 2 },
  })
  eq(#result, 1)
end)

-- summary
print(string.format("\n%d passed, %d failed", pass, fail))
if fail > 0 then
  vim.cmd("cq1")
end
