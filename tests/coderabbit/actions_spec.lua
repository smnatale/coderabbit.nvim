local actions = require("coderabbit.actions")
local diagnostics = require("coderabbit.diagnostics")
local h = require("tests.helpers")
local test, eq = h.test, h.eq
local W, E, I = h.W, h.E, h.I

local function reset()
  diagnostics.clear()
end

local function range(start_line, end_line)
  return { start = { line = start_line }, ["end"] = { line = end_line or start_line } }
end

local function with_lsp_client(lines, command_args, fn)
  reset()
  local bufnr = h.make_buf(lines)
  actions.attach(bufnr)
  local client
  vim.wait(2000, function()
    local clients = vim.lsp.get_clients({ name = "coderabbit", bufnr = bufnr })
    if #clients > 0 then
      client = clients[1]
      return true
    end
    return false
  end)
  assert(client, "coderabbit client should be attached")
  local args = type(command_args) == "function" and command_args(bufnr) or command_args
  local responded = false
  client.request("workspace/executeCommand", {
    command = "coderabbit.apply",
    arguments = args,
  }, function()
    responded = true
  end, bufnr)
  vim.wait(2000, function()
    return responded
  end)
  assert(responded, "handler should respond without crashing")
  fn(bufnr)
  client.stop()
end

-- ──────────────────────────────────────────────────────────
-- Tests: apply (table-driven where possible)
-- ──────────────────────────────────────────────────────────

test("apply: replaces a single line", function()
  reset()
  local bufnr = h.make_buf({ "line0", "line1", "line2", "line3" })
  vim.diagnostic.set(diagnostics.ns, bufnr, { h.diag(1, W, "fix this", { "fixed_line1" }) })
  actions.apply(bufnr, 1, nil, "fixed_line1", "fix this")
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  eq(#lines, 4)
  eq(lines[2], "fixed_line1")
end)

test("apply: replaces a multi-line range", function()
  reset()
  local bufnr = h.make_buf({ "line0", "line1", "line2", "line3", "line4" })
  vim.diagnostic.set(diagnostics.ns, bufnr, { h.diag(1, E, "replace these", { "new1\nnew2" }, 3) })
  actions.apply(bufnr, 1, 3, "new1\nnew2", "replace these")
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  eq(#lines, 4)
  eq(lines[2], "new1")
  eq(lines[3], "new2")
  eq(lines[4], "line4")
end)

test("apply: removes the applied diagnostic", function()
  reset()
  local bufnr = h.make_buf({ "line0", "line1", "line2" })
  vim.diagnostic.set(diagnostics.ns, bufnr, { h.diag(1, W, "fix this", { "fixed" }) })
  eq(#vim.diagnostic.get(bufnr, { namespace = diagnostics.ns }), 1)
  actions.apply(bufnr, 1, nil, "fixed", "fix this")
  eq(#vim.diagnostic.get(bufnr, { namespace = diagnostics.ns }), 0)
end)

test("apply: preserves other diagnostics", function()
  reset()
  local bufnr = h.make_buf({ "line0", "line1", "line2", "line3" })
  vim.diagnostic.set(diagnostics.ns, bufnr, {
    h.diag(1, W, "first issue", { "fix1" }),
    h.diag(3, I, "second issue", { "fix2" }),
  })
  eq(#vim.diagnostic.get(bufnr, { namespace = diagnostics.ns }), 2)
  actions.apply(bufnr, 1, nil, "fix1", "first issue")
  local remaining = vim.diagnostic.get(bufnr, { namespace = diagnostics.ns })
  eq(#remaining, 1)
  eq(remaining[1].message, "second issue")
end)

test("apply: shifts later diagnostics when suggestion changes line count", function()
  reset()
  local bufnr = h.make_buf({ "line0", "line1", "line2", "line3", "line4" })
  vim.diagnostic.set(diagnostics.ns, bufnr, {
    h.diag(1, W, "replace this", { "new1\nnew2\nnew3" }),
    h.diag(3, I, "later issue", { "fix_later" }, 4),
  })
  actions.apply(bufnr, 1, nil, "new1\nnew2\nnew3", "replace this")
  local remaining = vim.diagnostic.get(bufnr, { namespace = diagnostics.ns })
  eq(#remaining, 1)
  eq(remaining[1].message, "later issue")
  eq(remaining[1].lnum, 5)
  eq(remaining[1].end_lnum, 6)
end)

-- ──────────────────────────────────────────────────────────
-- Tests: get_actions (table-driven)
-- ──────────────────────────────────────────────────────────

for _, case in ipairs({
  { "no actions for empty suggestions", { h.diag(0, I, "no fix available", {}) }, range(0), 0 },
  { "no actions when user_data has no suggestions", { h.diag(0, I, "bare diagnostic") }, range(0), 0 },
  { "one action per suggestion", { h.diag(0, W, "issue here", { "fix_a", "fix_b" }) }, range(0), 2 },
  {
    "multi-line diagnostic found when cursor is in the middle",
    { h.diag(1, E, "spans 1-3", { "replacement" }, 3) },
    range(2),
    1,
  },
}) do
  test("get_actions: " .. case[1], function()
    reset()
    local bufnr = h.make_buf({ "a", "b", "c", "d", "e" })
    vim.diagnostic.set(diagnostics.ns, bufnr, case[2])
    eq(#actions.get_actions(bufnr, case[3]), case[4])
  end)
end

test("get_actions: only returns actions for diagnostics in range", function()
  reset()
  local bufnr = h.make_buf({ "line0", "line1", "line2", "line3" })
  vim.diagnostic.set(diagnostics.ns, bufnr, {
    h.diag(0, W, "issue at 0", { "fix0" }),
    h.diag(3, W, "issue at 3", { "fix3" }),
  })
  local result = actions.get_actions(bufnr, range(0))
  eq(#result, 1)
  eq(result[1].command.arguments[1].lnum, 0)
end)

-- ──────────────────────────────────────────────────────────
-- Tests: cleanup
-- ──────────────────────────────────────────────────────────

test("cleanup: removes matching diagnostic", function()
  reset()
  local bufnr = h.make_buf({ "line0", "line1", "line2" })
  vim.diagnostic.set(diagnostics.ns, bufnr, { h.diag(1, W, "fix this", { "fixed" }) })
  eq(#vim.diagnostic.get(bufnr, { namespace = diagnostics.ns }), 1)
  actions.cleanup(bufnr, 1, nil, "fix this", 0)
  eq(#vim.diagnostic.get(bufnr, { namespace = diagnostics.ns }), 0)
end)

test("cleanup: shifts later diagnostics by delta", function()
  reset()
  local bufnr = h.make_buf({ "line0", "line1", "line2", "line3", "line4" })
  vim.diagnostic.set(diagnostics.ns, bufnr, {
    h.diag(1, W, "replace this", { "new1\nnew2\nnew3" }),
    h.diag(3, I, "later issue", { "fix_later" }, 4),
  })
  -- delta = 3 new lines - 1 old line = +2
  actions.cleanup(bufnr, 1, nil, "replace this", 2)
  local remaining = vim.diagnostic.get(bufnr, { namespace = diagnostics.ns })
  eq(#remaining, 1)
  eq(remaining[1].lnum, 5)
  eq(remaining[1].end_lnum, 6)
end)

-- ──────────────────────────────────────────────────────────
-- Tests: get_actions – WorkspaceEdit
-- ──────────────────────────────────────────────────────────

test("get_actions: returns edit with WorkspaceEdit", function()
  reset()
  local bufnr = h.make_buf({ "line0", "line1", "line2" })
  vim.diagnostic.set(diagnostics.ns, bufnr, { h.diag(1, W, "issue", { "fixed_line" }) })
  local result = actions.get_actions(bufnr, range(1))
  eq(#result, 1)
  assert(result[1].edit ~= nil, "action should have edit field")
  assert(result[1].edit.changes ~= nil, "edit should have changes")
  -- Verify TextEdit structure
  local uri = vim.uri_from_bufnr(bufnr)
  local edits = result[1].edit.changes[uri]
  assert(edits ~= nil, "changes should contain buffer URI")
  eq(#edits, 1)
  eq(edits[1].range.start.line, 1)
  eq(edits[1].range["end"].line, 2)
  eq(edits[1].newText, "fixed_line\n")
end)

test("get_actions: multi-line edit has correct range and newText", function()
  reset()
  local bufnr = h.make_buf({ "line0", "line1", "line2", "line3", "line4" })
  vim.diagnostic.set(diagnostics.ns, bufnr, { h.diag(1, E, "replace", { "new1\nnew2" }, 3) })
  local result = actions.get_actions(bufnr, range(2))
  eq(#result, 1)
  local uri = vim.uri_from_bufnr(bufnr)
  local edit = result[1].edit.changes[uri][1]
  eq(edit.range.start.line, 1)
  eq(edit.range["end"].line, 4)
  eq(edit.newText, "new1\nnew2\n")
end)

test("get_actions: cleanup command has correct delta", function()
  reset()
  local bufnr = h.make_buf({ "line0", "line1", "line2" })
  vim.diagnostic.set(diagnostics.ns, bufnr, { h.diag(1, W, "issue", { "a\nb\nc" }) })
  local result = actions.get_actions(bufnr, range(1))
  eq(result[1].command.command, "coderabbit.cleanup")
  eq(result[1].command.arguments[1].delta, 2) -- 3 new lines - 1 old = +2
end)

-- ──────────────────────────────────────────────────────────
-- Tests: resolve / dismiss
-- ──────────────────────────────────────────────────────────

local function ref_diag(lnum, msg, suggestions, end_lnum)
  local d = h.diag(lnum, W, msg, suggestions or {}, end_lnum)
  d.user_data.ref = { file = "review.json", index = 1 }
  return d
end

--- Stub review.set_status, recording calls and returning `result`.
local function with_set_status(result, fn)
  local review = require("coderabbit.review")
  local orig = review.set_status
  local calls = {}
  review.set_status = function(ref, status)
    table.insert(calls, { ref = ref, status = status })
    return result
  end
  local ok, err = pcall(fn, calls)
  review.set_status = orig
  if not ok then
    error(err, 2)
  end
end

test("get_actions: adds resolve and dismiss actions for diagnostics with a ref", function()
  reset()
  local bufnr = h.make_buf({ "line0", "line1" })
  vim.diagnostic.set(diagnostics.ns, bufnr, { ref_diag(1, "issue", { "fix" }) })
  local result = actions.get_actions(bufnr, range(1))
  eq(#result, 3)
  eq(result[1].title, "CodeRabbit: Apply fix")
  eq(result[1].command.arguments[1].ref.file, "review.json")
  eq(result[2].title, "CodeRabbit: Mark resolved")
  eq(result[2].command.command, "coderabbit.set_status")
  eq(result[2].command.arguments[1].status, "resolved")
  eq(result[2].edit, nil)
  eq(result[3].title, "CodeRabbit: Dismiss")
  eq(result[3].command.arguments[1].status, "dismissed")
end)

test("mark: removes the diagnostic when status is saved", function()
  reset()
  local bufnr = h.make_buf({ "line0", "line1", "line2" })
  vim.diagnostic.set(diagnostics.ns, bufnr, { ref_diag(1, "issue"), h.diag(2, W, "other") })
  with_set_status(true, function(calls)
    local diag = vim.diagnostic.get(bufnr, { namespace = diagnostics.ns, lnum = 1 })[1]
    eq(actions.mark(bufnr, diag, "dismissed"), true)
    eq(#calls, 1)
    eq(calls[1].status, "dismissed")
    eq(calls[1].ref.index, 1)
  end)
  local remaining = vim.diagnostic.get(bufnr, { namespace = diagnostics.ns })
  eq(#remaining, 1)
  eq(remaining[1].message, "other")
end)

test("mark: keeps the diagnostic when status cannot be saved", function()
  reset()
  local bufnr = h.make_buf({ "line0", "line1" })
  vim.diagnostic.set(diagnostics.ns, bufnr, { ref_diag(1, "issue") })
  with_set_status(false, function()
    local diag = vim.diagnostic.get(bufnr, { namespace = diagnostics.ns })[1]
    eq(actions.mark(bufnr, diag, "resolved"), false)
  end)
  eq(#vim.diagnostic.get(bufnr, { namespace = diagnostics.ns }), 1)
end)

for _, case in ipairs({
  { "finds diagnostic on its line", 1, "issue" },
  { "finds multi-line diagnostic from a middle line", 3, "range" },
  { "ignores lines without a finding", 0, nil },
}) do
  test("at_line: " .. case[1], function()
    reset()
    local bufnr = h.make_buf({ "a", "b", "c", "d", "e" })
    vim.diagnostic.set(diagnostics.ns, bufnr, {
      ref_diag(1, "issue"),
      ref_diag(2, "range", {}, 4),
      h.diag(0, W, "no ref"),
    })
    local d = actions.at_line(bufnr, case[2])
    eq(d and d.message, case[3])
  end)
end

local function with_command(command, command_args, fn)
  reset()
  local bufnr = h.make_buf({ "line0", "line1", "line2" })
  actions.attach(bufnr)
  local client
  vim.wait(2000, function()
    client = vim.lsp.get_clients({ name = "coderabbit", bufnr = bufnr })[1]
    return client ~= nil
  end)
  assert(client, "coderabbit client should be attached")
  vim.diagnostic.set(diagnostics.ns, bufnr, { ref_diag(1, "issue", { "fix" }) })
  local responded = false
  client.request("workspace/executeCommand", {
    command = command,
    arguments = { command_args(bufnr) },
  }, function()
    responded = true
  end, bufnr)
  vim.wait(2000, function()
    return responded
  end)
  -- Let the scheduled handler run
  vim.wait(10, function()
    return false
  end)
  fn(bufnr)
  client.stop()
end

test("executeCommand: set_status saves status and removes diagnostic", function()
  with_set_status(true, function(calls)
    with_command("coderabbit.set_status", function(bufnr)
      return {
        bufnr = bufnr,
        lnum = 1,
        message = "issue",
        ref = { file = "review.json", index = 1 },
        status = "dismissed",
      }
    end, function(bufnr)
      eq(#calls, 1)
      eq(calls[1].status, "dismissed")
      eq(#vim.diagnostic.get(bufnr, { namespace = diagnostics.ns }), 0)
    end)
  end)
end)

test("executeCommand: cleanup after applying a fix marks finding resolved", function()
  with_set_status(true, function(calls)
    with_command("coderabbit.cleanup", function(bufnr)
      return { bufnr = bufnr, lnum = 1, message = "issue", delta = 0, ref = { file = "review.json", index = 1 } }
    end, function()
      eq(#calls, 1)
      eq(calls[1].status, "resolved")
      eq(calls[1].ref.file, "review.json")
    end)
  end)
end)

-- ──────────────────────────────────────────────────────────
-- Tests: apply – end_lnum disambiguation
-- ──────────────────────────────────────────────────────────

test("apply: removes only the diagnostic whose end_lnum matches", function()
  reset()
  local bufnr = h.make_buf({ "line0", "line1", "line2", "line3", "line4" })
  vim.diagnostic.set(diagnostics.ns, bufnr, {
    h.diag(1, W, "same message", { "fix_single" }, 1),
    h.diag(1, W, "same message", { "fix_multi" }, 3),
  })
  eq(#vim.diagnostic.get(bufnr, { namespace = diagnostics.ns }), 2)
  actions.apply(bufnr, 1, 3, "fix_multi", "same message")
  local remaining = vim.diagnostic.get(bufnr, { namespace = diagnostics.ns })
  eq(#remaining, 1)
  eq(remaining[1].end_lnum, 1)
end)

test("apply: removes single-line diagnostic when end_lnum is nil", function()
  reset()
  local bufnr = h.make_buf({ "line0", "line1", "line2", "line3" })
  vim.diagnostic.set(diagnostics.ns, bufnr, {
    h.diag(1, W, "same message", { "fix_single" }),
    h.diag(1, W, "same message", { "fix_multi" }, 3),
  })
  eq(#vim.diagnostic.get(bufnr, { namespace = diagnostics.ns }), 2)
  actions.apply(bufnr, 1, nil, "fix_single", "same message")
  local remaining = vim.diagnostic.get(bufnr, { namespace = diagnostics.ns })
  eq(#remaining, 1)
  eq(remaining[1].end_lnum, 3)
end)

-- ──────────────────────────────────────────────────────────
-- Tests: executeCommand – argument validation (table-driven)
-- ──────────────────────────────────────────────────────────

for _, case in ipairs({
  { "does not crash with nil arguments", nil },
  { "does not crash with empty arguments table", {} },
}) do
  test("executeCommand: " .. case[1], function()
    with_lsp_client({ "line0", "line1" }, case[2], function(bufnr)
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      eq(lines[1], "line0")
    end)
  end)
end

test("executeCommand: does not crash with incomplete argument fields", function()
  with_lsp_client({ "line0", "line1" }, function(bufnr)
    return { { bufnr = bufnr, lnum = 0 } }
  end, function(bufnr)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    eq(lines[1], "line0")
  end)
end)

h.summary()
