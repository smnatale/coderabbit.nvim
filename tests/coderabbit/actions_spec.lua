local actions = require("coderabbit.actions")
local diagnostics = require("coderabbit.diagnostics")
local h = require("tests.helpers")
local test, eq = h.test, h.eq

local W, E, I = vim.diagnostic.severity.WARN, vim.diagnostic.severity.ERROR, vim.diagnostic.severity.INFO

local function reset()
  diagnostics.clear()
end

local function make_buf(lines)
  local bufnr = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  return bufnr
end

local function diag(lnum, sev, msg, suggestions, end_lnum)
  local d = { lnum = lnum, col = 0, severity = sev, message = msg, source = "coderabbit" }
  if end_lnum then d.end_lnum = end_lnum end
  if suggestions then d.user_data = { suggestions = suggestions } end
  return d
end

local function range(start_line, end_line)
  return { start = { line = start_line }, ["end"] = { line = end_line or start_line } }
end

local function with_lsp_client(lines, command_args, fn)
  reset()
  local bufnr = make_buf(lines)
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
-- Tests: apply
-- ──────────────────────────────────────────────────────────

test("apply: replaces a single line", function()
  reset()
  local bufnr = make_buf({ "line0", "line1", "line2", "line3" })
  vim.diagnostic.set(diagnostics.ns, bufnr, { diag(1, W, "fix this", { "fixed_line1" }) })
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
  vim.diagnostic.set(diagnostics.ns, bufnr, { diag(1, E, "replace these", { "new1\nnew2" }, 3) })
  actions.apply(bufnr, 1, 3, "new1\nnew2", "replace these")
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  eq(#lines, 4)
  eq(lines[1], "line0")
  eq(lines[2], "new1")
  eq(lines[3], "new2")
  eq(lines[4], "line4")
end)

test("apply: removes the applied diagnostic", function()
  reset()
  local bufnr = make_buf({ "line0", "line1", "line2" })
  vim.diagnostic.set(diagnostics.ns, bufnr, { diag(1, W, "fix this", { "fixed" }) })
  eq(#vim.diagnostic.get(bufnr, { namespace = diagnostics.ns }), 1)
  actions.apply(bufnr, 1, nil, "fixed", "fix this")
  eq(#vim.diagnostic.get(bufnr, { namespace = diagnostics.ns }), 0)
end)

test("apply: preserves other diagnostics", function()
  reset()
  local bufnr = make_buf({ "line0", "line1", "line2", "line3" })
  vim.diagnostic.set(diagnostics.ns, bufnr, {
    diag(1, W, "first issue", { "fix1" }),
    diag(3, I, "second issue", { "fix2" }),
  })
  eq(#vim.diagnostic.get(bufnr, { namespace = diagnostics.ns }), 2)
  actions.apply(bufnr, 1, nil, "fix1", "first issue")
  local remaining = vim.diagnostic.get(bufnr, { namespace = diagnostics.ns })
  eq(#remaining, 1)
  eq(remaining[1].message, "second issue")
end)

test("apply: shifts later diagnostics when suggestion changes line count", function()
  reset()
  local bufnr = make_buf({ "line0", "line1", "line2", "line3", "line4" })
  vim.diagnostic.set(diagnostics.ns, bufnr, {
    diag(1, W, "replace this", { "new1\nnew2\nnew3" }),
    diag(3, I, "later issue", { "fix_later" }, 4),
  })
  actions.apply(bufnr, 1, nil, "new1\nnew2\nnew3", "replace this")
  local remaining = vim.diagnostic.get(bufnr, { namespace = diagnostics.ns })
  eq(#remaining, 1)
  eq(remaining[1].message, "later issue")
  eq(remaining[1].lnum, 5)
  eq(remaining[1].end_lnum, 6)
end)

-- ──────────────────────────────────────────────────────────
-- Tests: get_actions
-- ──────────────────────────────────────────────────────────

test("get_actions: no actions for empty suggestions", function()
  reset()
  local bufnr = make_buf({ "line0", "line1" })
  vim.diagnostic.set(diagnostics.ns, bufnr, { diag(0, I, "no fix available", {}) })
  eq(#actions.get_actions(bufnr, range(0)), 0)
end)

test("get_actions: no actions when user_data has no suggestions", function()
  reset()
  local bufnr = make_buf({ "line0" })
  vim.diagnostic.set(diagnostics.ns, bufnr, { diag(0, I, "bare diagnostic") })
  eq(#actions.get_actions(bufnr, range(0)), 0)
end)

test("get_actions: one action per suggestion", function()
  reset()
  local bufnr = make_buf({ "line0", "line1" })
  vim.diagnostic.set(diagnostics.ns, bufnr, { diag(0, W, "issue here", { "fix_a", "fix_b" }) })
  local result = actions.get_actions(bufnr, range(0))
  eq(#result, 2)
  assert(result[1].title:match("1/2"), "first action should say 1/2")
  assert(result[2].title:match("2/2"), "second action should say 2/2")
end)

test("get_actions: only returns actions for diagnostics in range", function()
  reset()
  local bufnr = make_buf({ "line0", "line1", "line2", "line3" })
  vim.diagnostic.set(diagnostics.ns, bufnr, {
    diag(0, W, "issue at 0", { "fix0" }),
    diag(3, W, "issue at 3", { "fix3" }),
  })
  local result = actions.get_actions(bufnr, range(0))
  eq(#result, 1)
  eq(result[1].command.arguments[1].lnum, 0)
end)

test("get_actions: multi-line diagnostic found when cursor is in the middle", function()
  reset()
  local bufnr = make_buf({ "a", "b", "c", "d", "e" })
  vim.diagnostic.set(diagnostics.ns, bufnr, { diag(1, E, "spans 1-3", { "replacement" }, 3) })
  eq(#actions.get_actions(bufnr, range(2)), 1)
end)

-- ──────────────────────────────────────────────────────────
-- Tests: apply – end_lnum disambiguation
-- ──────────────────────────────────────────────────────────

test("apply: removes only the diagnostic whose end_lnum matches", function()
  reset()
  local bufnr = make_buf({ "line0", "line1", "line2", "line3", "line4" })
  vim.diagnostic.set(diagnostics.ns, bufnr, {
    diag(1, W, "same message", { "fix_single" }, 1),
    diag(1, W, "same message", { "fix_multi" }, 3),
  })
  eq(#vim.diagnostic.get(bufnr, { namespace = diagnostics.ns }), 2)
  actions.apply(bufnr, 1, 3, "fix_multi", "same message")
  local remaining = vim.diagnostic.get(bufnr, { namespace = diagnostics.ns })
  eq(#remaining, 1)
  eq(remaining[1].end_lnum, 1)
end)

test("apply: removes single-line diagnostic when end_lnum is nil", function()
  reset()
  local bufnr = make_buf({ "line0", "line1", "line2", "line3" })
  vim.diagnostic.set(diagnostics.ns, bufnr, {
    diag(1, W, "same message", { "fix_single" }),
    diag(1, W, "same message", { "fix_multi" }, 3),
  })
  eq(#vim.diagnostic.get(bufnr, { namespace = diagnostics.ns }), 2)
  actions.apply(bufnr, 1, nil, "fix_single", "same message")
  local remaining = vim.diagnostic.get(bufnr, { namespace = diagnostics.ns })
  eq(#remaining, 1)
  eq(remaining[1].end_lnum, 3)
end)

-- ──────────────────────────────────────────────────────────
-- Tests: executeCommand – argument validation
-- ──────────────────────────────────────────────────────────

test("executeCommand: does not crash with nil arguments", function()
  with_lsp_client({ "line0", "line1" }, nil, function(bufnr)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    eq(lines[1], "line0")
    eq(lines[2], "line1")
  end)
end)

test("executeCommand: does not crash with empty arguments table", function()
  with_lsp_client({ "line0", "line1" }, {}, function(bufnr)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    eq(lines[1], "line0")
    eq(lines[2], "line1")
  end)
end)

test("executeCommand: does not crash with incomplete argument fields", function()
  with_lsp_client({ "line0", "line1" }, function(bufnr)
    return { { bufnr = bufnr, lnum = 0 } }
  end, function(bufnr)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    eq(lines[1], "line0")
    eq(lines[2], "line1")
  end)
end)

h.summary()
