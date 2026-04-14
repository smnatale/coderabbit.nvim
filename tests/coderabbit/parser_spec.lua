local parser = require("coderabbit.parser")
local h = require("tests.helpers")
local test, eq = h.test, h.eq

-- parse_line: edge cases (table-driven)

for _, case in ipairs({
  { "empty string", "" },
  { "nil", nil },
  { "invalid JSON", "not json" },
  { "non-table JSON", '"just a string"' },
}) do
  test("parse_line: " .. case[1] .. " returns nil", function()
    eq(parser.parse_line(case[2]), nil)
  end)
end

-- parse_line: valid events (table-driven)

for _, case in ipairs({
  {
    "finding",
    '{"type":"finding","severity":"major","fileName":"src/foo.ts","codegenInstructions":"Fix this","suggestions":[]}',
    { type = "finding", severity = "major", fileName = "src/foo.ts" },
  },
  {
    "status",
    '{"type":"status","phase":"analyzing","status":"reviewing"}',
    { type = "status", phase = "analyzing" },
  },
  {
    "complete",
    '{"type":"complete","status":"review_completed","findings":5}',
    { type = "complete", findings = 5 },
  },
  {
    "error",
    '{"type":"error","errorType":"review","message":"No files found","recoverable":false,"details":{}}',
    { type = "error", message = "No files found" },
  },
}) do
  test("parse_line: valid " .. case[1], function()
    local r = parser.parse_line(case[2])
    assert(r)
    for k, v in pairs(case[3]) do
      eq(r[k], v)
    end
  end)
end

-- clean_message (table-driven)

for _, case in ipairs({
  {
    "strips boilerplate prefix",
    "Verify each finding against the current code and only fix it if needed.\n\nIn src/foo.ts at line 42, do the thing.",
    "In src/foo.ts at line 42, do the thing.",
  },
  { "preserves non-prefixed message", "Some other message.", "Some other message." },
  { "nil returns empty string", nil, "" },
}) do
  test("clean_message: " .. case[1], function()
    eq(parser.clean_message(case[2]), case[3])
  end)
end

-- finding_to_diagnostic

local severity_map = {
  critical = vim.diagnostic.severity.ERROR,
  major = vim.diagnostic.severity.WARN,
  minor = vim.diagnostic.severity.INFO,
}

local function make_finding(sev, file, instructions, suggestions)
  return {
    severity = sev,
    fileName = file,
    codegenInstructions = instructions or "Fix.",
    suggestions = suggestions or {},
  }
end

test("finding_to_diagnostic: line range", function()
  local finding = make_finding(
    "critical",
    "src/foo.ts",
    "Verify each finding against the current code and only fix it if needed."
      .. "\n\nIn @src/foo.ts around lines 99 - 103, Something is wrong.",
    { "fixed code" }
  )
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
  local finding = make_finding(
    "major",
    "src/bar.ts",
    "Verify each finding against the current code and only fix it if needed.\n\nIn @src/bar.ts at line 42, Fix the bug."
  )
  local diag, filepath = parser.finding_to_diagnostic(finding, "/tmp/repo", severity_map)
  assert(diag)
  eq(filepath, "/tmp/repo/src/bar.ts")
  eq(diag.lnum, 41)
  eq(diag.end_lnum, nil)
  eq(diag.severity, vim.diagnostic.severity.WARN)
end)

test("finding_to_diagnostic: unknown severity falls back to INFO", function()
  local diag = parser.finding_to_diagnostic(
    make_finding("unknown", "src/foo.ts", "Something at line 1."),
    "/tmp/repo",
    severity_map
  )
  eq(diag.severity, vim.diagnostic.severity.INFO)
end)

test("finding_to_diagnostic: resolves relative paths", function()
  local _, filepath =
    parser.finding_to_diagnostic(make_finding("minor", "lib/utils.ts"), "/home/user/project", severity_map)
  eq(filepath, "/home/user/project/lib/utils.ts")
end)

test("finding_to_diagnostic: preserves absolute paths", function()
  local _, filepath =
    parser.finding_to_diagnostic(make_finding("minor", "/absolute/path/file.ts"), "/home/user/project", severity_map)
  eq(filepath, "/absolute/path/file.ts")
end)

test("finding_to_diagnostic: nil for missing fileName", function()
  local diag = parser.finding_to_diagnostic(
    { severity = "major", codegenInstructions = "Something.", suggestions = {} },
    "/tmp/repo",
    severity_map
  )
  eq(diag, nil)
end)

h.summary()
