local show = require("coderabbit.show")
local h = require("tests.helpers")
local test, eq, has, count = h.test, h.eq, h.has, h.count
local E, W, I, CWD = h.E, h.W, h.I, h.CWD

local function f(path, lnum, sev, msg, suggestions, end_lnum)
  return h.finding(path, lnum, sev, msg, suggestions, end_lnum)
end

local function render(findings, ctx, cwd)
  return show.render(findings, ctx, { cwd = cwd or CWD })
end

-- ──────────────────────────────────────────────────────────
-- Tests: render (table-driven)
-- ──────────────────────────────────────────────────────────

local render_cases = {
  { "empty findings shows no-findings message", {}, nil, nil, { "No findings" } },
  { "header is present", {}, nil, nil, { "# CodeRabbit Review" } },
  {
    "single finding renders file, severity, line, message",
    { f(CWD .. "/src/foo.ts", 41, E, "null check needed") },
    nil,
    nil,
    { "## src/foo.ts", "[ERROR]", "Line 42", "null check needed" },
  },
  {
    "line range renders Lines N-M",
    { f(CWD .. "/a.ts", 98, W, "fix this", {}, 102) },
    nil,
    nil,
    { "Lines 99-103" },
  },
  {
    "suggestions rendered as code blocks",
    { f(CWD .. "/app.ts", 5, W, "fix it", { "const x = 1" }) },
    nil,
    nil,
    { "```ts", "const x = 1", "Suggested fix" },
  },
  {
    "no suggestions omits code block",
    { f(CWD .. "/app.ts", 5, W, "just a note", {}) },
    nil,
    nil,
    { "just a note" },
    { "```", "Suggested fix" },
  },
  {
    "context metadata appears in header",
    {},
    { review_type = "committed", current_branch = "feat/x", base_branch = "main", base_commit = "abc1234" },
    nil,
    { "**Type:** committed", "**Branch:** feat/x", "**Base:** main", "**Commit:** abc1234", "**Findings:** 0" },
  },
  { "nil context omits metadata", {}, nil, nil, { "# CodeRabbit Review" }, { "**Type:**" } },
  {
    "relative paths when cwd provided",
    { f("/home/user/project/src/index.ts", 0, I, "note") },
    nil,
    "/home/user/project",
    { "## src/index.ts" },
  },
  {
    "absolute paths kept when cwd does not match",
    { f("/other/path/foo.ts", 0, I, "note") },
    nil,
    "/home/user/project",
    { "## /other/path/foo.ts" },
  },
  {
    "multi-line suggestion preserves newlines",
    { f(CWD .. "/a.ts", 5, W, "fix", { "line1\nline2\nline3" }) },
    nil,
    nil,
    { "line1", "line2", "line3" },
  },
}

for _, case in ipairs(render_cases) do
  test("render: " .. case[1], function()
    local lines = render(case[2], case[3], case[4])
    for _, s in ipairs(case[5] or {}) do
      assert(has(lines, s), "expected: " .. s)
    end
    for _, s in ipairs(case[6] or {}) do
      assert(not has(lines, s), "unexpected: " .. s)
    end
  end)
end

test("render: lnum 0 omits line number", function()
  local lines = render({ f(CWD .. "/a.ts", 0, I, "general note") })
  assert(has(lines, "### [INFO]"), "expected severity")
  eq(count(lines, "Line %d"), 0)
end)

test("render: findings grouped by file", function()
  local lines = render({
    f(CWD .. "/a.ts", 10, W, "first"),
    f(CWD .. "/a.ts", 20, I, "second"),
  })
  eq(count(lines, "^## a%.ts"), 1)
end)

test("render: multiple files sorted alphabetically", function()
  local lines = render({
    f(CWD .. "/z.ts", 0, I, "z"),
    f(CWD .. "/a.ts", 0, I, "a"),
  })
  local files = {}
  for _, line in ipairs(lines) do
    if line:match("^## ") then
      table.insert(files, line)
    end
  end
  eq(files[1], "## a.ts")
  eq(files[2], "## z.ts")
end)

test("render: multiple suggestions each get a code block", function()
  local lines = render({ f(CWD .. "/app.ts", 5, W, "pick one", { "A", "B" }) })
  eq(count(lines, "^```ts"), 2)
end)

test("render: file extension to language mapping", function()
  for _, c in ipairs({
    { ".py", "```py" },
    { ".js", "```js" },
    { ".go", "```go" },
    { ".lua", "```lua" },
    { ".rs", "```rs" },
    { ".xyz", "```xyz" },
  }) do
    local lines = render({ f("/tmp/r/a" .. c[1], 0, I, "x", { "code" }) }, nil, "/tmp/r")
    assert(has(lines, c[2]), "expected " .. c[2] .. " for " .. c[1])
  end
end)

-- ──────────────────────────────────────────────────────────
-- Tests: buffer management
-- ──────────────────────────────────────────────────────────

local _originals = {}

local function with_review(findings, ctx, running, fn)
  show._reset()
  local review = require("coderabbit.review")
  if not _originals.get_results then
    _originals = { get_results = review.get_results, get_context = review.get_context, is_running = review.is_running }
  end
  review.get_results = function()
    return findings or {}
  end
  review.get_context = function()
    return ctx
  end
  review.is_running = function()
    return running or false
  end
  local ok, err = pcall(fn)
  review.get_results, review.get_context, review.is_running =
    _originals.get_results, _originals.get_context, _originals.is_running
  show._reset()
  if not ok then
    error(err, 2)
  end
end

local one_finding = { f(CWD .. "/a.ts", 5, W, "test finding") }
local one_ctx = { cwd = CWD, review_type = "all" }

test("open: creates scratch buffer with correct options", function()
  with_review(one_finding, one_ctx, false, function()
    show.open()
    local bufnr = show._get_buf_id()
    assert(bufnr and vim.api.nvim_buf_is_valid(bufnr), "expected valid buffer")
    eq(vim.api.nvim_get_option_value("buftype", { buf = bufnr }), "nofile")
    eq(vim.api.nvim_get_option_value("filetype", { buf = bufnr }), "markdown")
    eq(vim.api.nvim_get_option_value("modifiable", { buf = bufnr }), false)
  end)
end)

test("open: focuses existing buffer instead of creating duplicate", function()
  with_review(one_finding, one_ctx, false, function()
    show.open()
    local first = show._get_buf_id()
    show.open()
    eq(show._get_buf_id(), first)
  end)
end)

test("open: no review shows notification (no buffer created)", function()
  with_review({}, nil, false, function()
    local notified = false
    local orig = vim.notify
    vim.notify = function(msg)
      if msg:find("No review results") then
        notified = true
      end
    end
    show.open()
    vim.notify = orig
    assert(notified, "expected notification")
    eq(show._get_buf_id(), nil)
  end)
end)

test("close: removes buffer", function()
  with_review(one_finding, { cwd = CWD }, false, function()
    show.open()
    local bufnr = show._get_buf_id()
    show.close()
    eq(show._get_buf_id(), nil)
    assert(not vim.api.nvim_buf_is_valid(bufnr), "expected buffer deleted")
  end)
end)

test("open: q keymap is set", function()
  with_review(one_finding, { cwd = CWD }, false, function()
    show.open()
    local keymaps = vim.api.nvim_buf_get_keymap(show._get_buf_id(), "n")
    local found = false
    for _, km in ipairs(keymaps) do
      if km.lhs == "q" then
        found = true
      end
    end
    assert(found, "expected q keymap")
  end)
end)

test("open: buffer content matches render output", function()
  local findings = { f(CWD .. "/src/app.ts", 10, E, "bad code", { "good code" }) }
  local ctx = { cwd = CWD, review_type = "committed", current_branch = "main" }
  with_review(findings, ctx, false, function()
    show.open()
    local buf_lines = vim.api.nvim_buf_get_lines(show._get_buf_id(), 0, -1, false)
    eq(buf_lines[1], "# CodeRabbit Review")
    assert(has(buf_lines, "src/app.ts"), "expected file path")
    assert(has(buf_lines, "bad code"), "expected message")
  end)
end)

test("open: in-progress review shows notice", function()
  with_review(one_finding, { cwd = CWD }, true, function()
    show.open()
    local buf_lines = vim.api.nvim_buf_get_lines(show._get_buf_id(), 0, -1, false)
    assert(has(buf_lines, "Review in progress"), "expected notice")
  end)
end)

test("is_open: false when no buffer, true when visible", function()
  eq(show.is_open(), false)
  with_review(one_finding, { cwd = CWD }, false, function()
    show.open()
    eq(show.is_open(), true)
  end)
end)

-- ──────────────────────────────────────────────────────────
-- Tests: layout modes
-- ──────────────────────────────────────────────────────────

local config = require("coderabbit.config")

local function with_layout(layout, fn)
  local prev = config.get().show.layout
  config.get().show.layout = layout
  local ok, err = pcall(fn)
  config.get().show.layout = prev
  if not ok then
    error(err, 2)
  end
end

test("layout float: opens floating window", function()
  with_layout("float", function()
    with_review(one_finding, one_ctx, false, function()
      show.open()
      local bufnr = show._get_buf_id()
      assert(bufnr and vim.api.nvim_buf_is_valid(bufnr), "expected valid buffer")
      local winid = vim.fn.bufwinid(bufnr)
      assert(winid ~= -1, "expected buffer in a window")
      local win_cfg = vim.api.nvim_win_get_config(winid)
      eq(win_cfg.relative, "editor")
      assert(win_cfg.width > 0, "expected positive width")
      assert(win_cfg.height > 0, "expected positive height")
    end)
  end)
end)

test("layout float: close removes floating window", function()
  with_layout("float", function()
    with_review(one_finding, one_ctx, false, function()
      show.open()
      eq(show.is_open(), true)
      show.close()
      eq(show.is_open(), false)
      eq(show._get_buf_id(), nil)
    end)
  end)
end)

test("layout buffer: opens in current window (no split or float)", function()
  with_layout("buffer", function()
    with_review(one_finding, one_ctx, false, function()
      local win_before = vim.api.nvim_get_current_win()
      local win_count_before = #vim.api.nvim_list_wins()
      show.open()
      local bufnr = show._get_buf_id()
      assert(bufnr and vim.api.nvim_buf_is_valid(bufnr), "expected valid buffer")
      eq(vim.api.nvim_get_current_win(), win_before)
      eq(#vim.api.nvim_list_wins(), win_count_before)
      local win_cfg = vim.api.nvim_win_get_config(vim.fn.bufwinid(bufnr))
      eq(win_cfg.relative, "")
    end)
  end)
end)

test("layout buffer: bufhidden is hide", function()
  with_layout("buffer", function()
    with_review(one_finding, one_ctx, false, function()
      show.open()
      local bufnr = show._get_buf_id()
      eq(vim.api.nvim_get_option_value("bufhidden", { buf = bufnr }), "hide")
    end)
  end)
end)

test("layout float: bufhidden is wipe", function()
  with_layout("float", function()
    with_review(one_finding, one_ctx, false, function()
      show.open()
      local bufnr = show._get_buf_id()
      eq(vim.api.nvim_get_option_value("bufhidden", { buf = bufnr }), "wipe")
    end)
  end)
end)

test("layout float: q keymap closes float", function()
  with_layout("float", function()
    with_review(one_finding, { cwd = CWD }, false, function()
      show.open()
      local keymaps = vim.api.nvim_buf_get_keymap(show._get_buf_id(), "n")
      local found = false
      for _, km in ipairs(keymaps) do
        if km.lhs == "q" then
          found = true
        end
      end
      assert(found, "expected q keymap")
    end)
  end)
end)

test("default layout is float", function()
  eq(config.defaults.show.layout, "float")
end)

h.summary()
