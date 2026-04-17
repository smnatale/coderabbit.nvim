local utils = require("coderabbit.utils")
local h = require("tests.helpers")
local test, eq = h.test, h.eq

-- ──────────────────────────────────────────────────────────
-- Tests: json_decode
-- ──────────────────────────────────────────────────────────

for _, case in ipairs({
  { "valid object", '{"a":1}', { a = 1 } },
  { "valid array", "[1,2,3]", { 1, 2, 3 } },
  { "empty object", "{}", true },
  { "nil input", nil, nil },
  { "empty string", "", nil },
  { "invalid JSON", "not json", nil },
  { "JSON string (non-table)", '"hello"', nil },
  { "JSON number (non-table)", "42", nil },
  { "JSON boolean (non-table)", "true", nil },
}) do
  test("json_decode: " .. case[1], function()
    local result = utils.json_decode(case[2])
    if case[3] == nil then
      eq(result, nil)
    elseif case[3] == true then
      -- just check it returned a table (e.g. vim.empty_dict)
      assert(type(result) == "table", "expected table, got " .. type(result))
    else
      eq(vim.inspect(result), vim.inspect(case[3]))
    end
  end)
end

-- ──────────────────────────────────────────────────────────
-- Tests: read_file
-- ──────────────────────────────────────────────────────────

test("read_file: reads existing file", function()
  local path = vim.fn.tempname()
  vim.fn.writefile({ "hello", "world" }, path)
  local content = utils.read_file(path)
  assert(content ~= nil, "expected content")
  assert(content:find("hello"), "expected 'hello' in content")
  assert(content:find("world"), "expected 'world' in content")
  os.remove(path)
end)

test("read_file: returns nil for non-existent file", function()
  eq(utils.read_file("/tmp/does_not_exist_" .. os.time()), nil)
end)

test("read_file: reads empty file", function()
  local path = vim.fn.tempname()
  vim.fn.writefile({}, path)
  local content = utils.read_file(path)
  assert(content ~= nil, "expected non-nil for empty file")
  eq(content, "")
  os.remove(path)
end)

-- ──────────────────────────────────────────────────────────
-- Tests: write_file
-- ──────────────────────────────────────────────────────────

test("write_file: writes and read back matches", function()
  local path = vim.fn.tempname()
  eq(utils.write_file(path, "test content"), true)
  eq(utils.read_file(path), "test content")
  os.remove(path)
end)

test("write_file: overwrites existing content", function()
  local path = vim.fn.tempname()
  utils.write_file(path, "first")
  utils.write_file(path, "second")
  eq(utils.read_file(path), "second")
  os.remove(path)
end)

test("write_file: returns false for invalid path", function()
  eq(utils.write_file("/no/such/directory/file.txt", "data"), false)
end)

-- ──────────────────────────────────────────────────────────
-- Tests: notify
-- ──────────────────────────────────────────────────────────

test("notify: prefixes message with CodeRabbit", function()
  local captured_msg, captured_level
  local orig = vim.notify
  vim.notify = function(msg, level)
    captured_msg = msg
    captured_level = level
  end
  utils.notify("test message")
  vim.notify = orig
  eq(captured_msg, "CodeRabbit: test message")
  eq(captured_level, vim.log.levels.INFO)
end)

test("notify: passes custom level", function()
  local captured_level
  local orig = vim.notify
  vim.notify = function(_, level)
    captured_level = level
  end
  utils.notify("error!", vim.log.levels.ERROR)
  vim.notify = orig
  eq(captured_level, vim.log.levels.ERROR)
end)

-- ──────────────────────────────────────────────────────────
-- Tests: pluralize
-- ──────────────────────────────────────────────────────────

for _, case in ipairs({
  { 0, "finding", "0 findings" },
  { 1, "finding", "1 finding" },
  { 2, "finding", "2 findings" },
  { 100, "item", "100 items" },
  { 1, "error", "1 error" },
}) do
  test("pluralize: " .. case[3], function()
    eq(utils.pluralize(case[1], case[2]), case[3])
  end)
end

h.summary()
