local parser = require("coderabbit.parser")

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

-- parse_line

test("parse_line: valid finding", function()
  local r = parser.parse_line(
    '{"type":"finding","severity":"major","fileName":"src/foo.ts","codegenInstructions":"Fix this","suggestions":[]}'
  )
  assert(r)
  eq(r.type, "finding")
  eq(r.severity, "major")
  eq(r.fileName, "src/foo.ts")
end)

test("parse_line: status event", function()
  local r = parser.parse_line('{"type":"status","phase":"analyzing","status":"reviewing"}')
  assert(r)
  eq(r.type, "status")
  eq(r.phase, "analyzing")
end)

test("parse_line: complete event", function()
  local r = parser.parse_line('{"type":"complete","status":"review_completed","findings":5}')
  assert(r)
  eq(r.type, "complete")
  eq(r.findings, 5)
end)

test("parse_line: error event", function()
  local r = parser.parse_line(
    '{"type":"error","errorType":"review","message":"No files found","recoverable":false,"details":{}}'
  )
  assert(r)
  eq(r.type, "error")
  eq(r.message, "No files found")
end)

test("parse_line: empty string returns nil", function()
  eq(parser.parse_line(""), nil)
end)

test("parse_line: nil returns nil", function()
  eq(parser.parse_line(nil), nil)
end)

test("parse_line: invalid JSON returns nil", function()
  eq(parser.parse_line("not json"), nil)
end)

test("parse_line: non-table JSON returns nil", function()
  eq(parser.parse_line('"just a string"'), nil)
end)

-- clean_message

test("clean_message: strips boilerplate prefix", function()
  local raw =
    "Verify each finding against the current code and only fix it if needed.\n\nIn src/foo.ts at line 42, do the thing."
  eq(parser.clean_message(raw), "In src/foo.ts at line 42, do the thing.")
end)

test("clean_message: preserves non-prefixed message", function()
  eq(parser.clean_message("Some other message."), "Some other message.")
end)

test("clean_message: nil returns empty string", function()
  eq(parser.clean_message(nil), "")
end)

-- finding_to_diagnostic

local severity_map = {
  critical = vim.diagnostic.severity.ERROR,
  major = vim.diagnostic.severity.WARN,
  minor = vim.diagnostic.severity.INFO,
}

test("finding_to_diagnostic: line range", function()
  local finding = {
    severity = "critical",
    fileName = "src/foo.ts",
    codegenInstructions = "Verify each finding against the current code and only fix it if needed."
      .. "\n\nIn @src/foo.ts around lines 99 - 103, Something is wrong.",
    suggestions = { "fixed code" },
  }
  local diag, filepath = parser.finding_to_diagnostic(finding, "/tmp/repo", severity_map)
  assert(diag)
  eq(filepath, "/tmp/repo/src/foo.ts")
  eq(diag.lnum, 98)
  eq(diag.end_lnum, 102)
  eq(diag.severity, vim.diagnostic.severity.ERROR)
  eq(diag.source, "coderabbit")
  assert(diag.user_data.suggestions)
end)

test("finding_to_diagnostic: single line", function()
  local finding = {
    severity = "major",
    fileName = "src/bar.ts",
    codegenInstructions = "Verify each finding against the current code and only fix it if needed.\n\nIn @src/bar.ts at line 42, Fix the bug.",
    suggestions = {},
  }
  local diag, filepath = parser.finding_to_diagnostic(finding, "/tmp/repo", severity_map)
  assert(diag)
  eq(filepath, "/tmp/repo/src/bar.ts")
  eq(diag.lnum, 41)
  eq(diag.end_lnum, nil)
  eq(diag.severity, vim.diagnostic.severity.WARN)
end)

test("finding_to_diagnostic: unknown severity falls back to INFO", function()
  local finding = {
    severity = "unknown",
    fileName = "src/foo.ts",
    codegenInstructions = "Something at line 1.",
    suggestions = {},
  }
  local diag, _ = parser.finding_to_diagnostic(finding, "/tmp/repo", severity_map)
  eq(diag.severity, vim.diagnostic.severity.INFO)
end)

test("finding_to_diagnostic: resolves relative paths", function()
  local finding = { severity = "minor", fileName = "lib/utils.ts", codegenInstructions = "Fix.", suggestions = {} }
  local _, filepath = parser.finding_to_diagnostic(finding, "/home/user/project", severity_map)
  eq(filepath, "/home/user/project/lib/utils.ts")
end)

test("finding_to_diagnostic: preserves absolute paths", function()
  local finding =
    { severity = "minor", fileName = "/absolute/path/file.ts", codegenInstructions = "Fix.", suggestions = {} }
  local _, filepath = parser.finding_to_diagnostic(finding, "/home/user/project", severity_map)
  eq(filepath, "/absolute/path/file.ts")
end)

test("finding_to_diagnostic: nil for missing fileName", function()
  local finding = { severity = "major", codegenInstructions = "Something.", suggestions = {} }
  local diag, _ = parser.finding_to_diagnostic(finding, "/tmp/repo", severity_map)
  eq(diag, nil)
end)

-- summary
print(string.format("\n%d passed, %d failed", pass, fail))
if fail > 0 then
  vim.cmd("cq1")
end
