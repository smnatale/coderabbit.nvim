local diagnostics = require("coderabbit.diagnostics")
local parser = require("coderabbit.parser")
local h = require("tests.helpers")
local test, eq = h.test, h.eq

local severity_map = {
  critical = vim.diagnostic.severity.ERROR,
  major = vim.diagnostic.severity.WARN,
  minor = vim.diagnostic.severity.INFO,
}

local function reset()
  diagnostics.clear()
end

local function make_diag(lnum, sev, msg)
  return { lnum = lnum, col = 0, severity = sev, message = msg, source = "coderabbit" }
end

local function make_temp_buf(relpath)
  local tmpdir = vim.fn.tempname()
  vim.fn.mkdir(tmpdir, "p")
  local filepath = tmpdir .. "/" .. relpath
  vim.fn.mkdir(vim.fn.fnamemodify(filepath, ":h"), "p")
  vim.fn.writefile({ "line1", "line2", "line3" }, filepath)
  vim.cmd("edit " .. vim.fn.fnameescape(filepath))
  return vim.fn.bufnr(filepath), filepath, tmpdir
end

local function simulate_finding(json_line, cwd)
  local event = parser.parse_line(json_line)
  if not event or event.type ~= "finding" then
    return nil
  end
  local diag, filepath = parser.finding_to_diagnostic(event, cwd, severity_map)
  if diag then
    diagnostics.set(filepath, { diag })
  end
  return diag, filepath
end

-- ──────────────────────────────────────────────────────────
-- Tests: diagnostics.set on loaded buffer
-- ──────────────────────────────────────────────────────────

test("set: diagnostics appear on loaded buffer", function()
  reset()
  local bufnr, filepath = make_temp_buf("src/foo.ts")
  diagnostics.set(filepath, { make_diag(10, vim.diagnostic.severity.WARN, "Test finding") })
  local got = vim.diagnostic.get(bufnr, { namespace = diagnostics.ns })
  eq(#got, 1)
  eq(got[1].message, "Test finding")
  eq(got[1].severity, vim.diagnostic.severity.WARN)
end)

test("set: multiple diagnostics accumulate on same buffer", function()
  reset()
  local bufnr, filepath = make_temp_buf("src/bar.ts")
  diagnostics.set(filepath, { make_diag(5, vim.diagnostic.severity.ERROR, "First") })
  diagnostics.set(filepath, { make_diag(10, vim.diagnostic.severity.INFO, "Second") })
  eq(#vim.diagnostic.get(bufnr, { namespace = diagnostics.ns }), 2)
end)

test("set: diagnostics appear in global vim.diagnostic.get()", function()
  reset()
  local _, filepath = make_temp_buf("src/global.ts")
  diagnostics.set(filepath, { make_diag(0, vim.diagnostic.severity.INFO, "Global check") })
  local found = false
  for _, d in ipairs(vim.diagnostic.get()) do
    if d.message == "Global check" and d.source == "coderabbit" then
      found = true
      break
    end
  end
  assert(found, "diagnostic not found in global vim.diagnostic.get()")
end)

test("clear: removes all diagnostics", function()
  reset()
  local bufnr, filepath = make_temp_buf("src/clear.ts")
  diagnostics.set(filepath, { make_diag(0, vim.diagnostic.severity.INFO, "Will be cleared") })
  eq(#vim.diagnostic.get(bufnr, { namespace = diagnostics.ns }), 1)
  diagnostics.clear()
  eq(#vim.diagnostic.get(bufnr, { namespace = diagnostics.ns }), 0)
end)

-- ──────────────────────────────────────────────────────────
-- Tests: end-to-end with mock CLI NDJSON
-- ──────────────────────────────────────────────────────────

test("e2e: mock CLI finding sets diagnostic on loaded buffer", function()
  reset()
  local tmpdir = vim.fn.tempname()
  vim.fn.mkdir(tmpdir .. "/apps/server/src/controllers", "p")
  local filepath = tmpdir .. "/apps/server/src/controllers/stripeController.ts"
  vim.fn.writefile({ "// mock file" }, filepath)
  vim.cmd("edit " .. vim.fn.fnameescape(filepath))

  local json_line = vim.json.encode({
    type = "finding",
    severity = "critical",
    fileName = "apps/server/src/controllers/stripeController.ts",
    codegenInstructions = "Verify each finding against the current code and only fix it if needed.\n\n"
      .. "In @apps/server/src/controllers/stripeController.ts around lines 99 - 103, "
      .. "EventBooking.findOneAndUpdate may return null; add a null check.",
    suggestions = { "fixed code" },
  })

  simulate_finding(json_line, tmpdir)

  local bufnr = vim.fn.bufnr(filepath)
  local got = vim.diagnostic.get(bufnr, { namespace = diagnostics.ns })
  eq(#got, 1)
  eq(got[1].lnum, 98)
  eq(got[1].end_lnum, 102)
  eq(got[1].severity, vim.diagnostic.severity.ERROR)
end)

test("e2e: multiple findings from fixture file all become diagnostics", function()
  reset()
  local tmpdir = vim.fn.tempname()
  vim.fn.mkdir(tmpdir .. "/apps/server/src/controllers", "p")

  local stripe_path = tmpdir .. "/apps/server/src/controllers/stripeController.ts"
  local class_path = tmpdir .. "/apps/server/src/controllers/classController.ts"
  vim.fn.writefile({ "// mock" }, stripe_path)
  vim.fn.writefile({ "// mock" }, class_path)
  vim.cmd("edit " .. vim.fn.fnameescape(stripe_path))
  vim.cmd("edit " .. vim.fn.fnameescape(class_path))

  local fixture = vim.fn.readfile("tests/fixtures/agent_output.jsonl")
  local finding_count = 0
  for _, line in ipairs(fixture) do
    local event = parser.parse_line(line)
    if event and event.type == "finding" then
      local diag, fpath = parser.finding_to_diagnostic(event, tmpdir, severity_map)
      if diag then
        diagnostics.set(fpath, { diag })
        finding_count = finding_count + 1
      end
    end
  end

  eq(finding_count, 3)

  local all = vim.diagnostic.get()
  local cr_diags = {}
  for _, d in ipairs(all) do
    if d.source == "coderabbit" then
      table.insert(cr_diags, d)
    end
  end
  eq(#cr_diags, 3)
  eq(#vim.diagnostic.get(vim.fn.bufnr(stripe_path), { namespace = diagnostics.ns }), 2)
  eq(#vim.diagnostic.get(vim.fn.bufnr(class_path), { namespace = diagnostics.ns }), 1)
end)

-- ──────────────────────────────────────────────────────────
-- Tests: file NOT open as a buffer
-- ──────────────────────────────────────────────────────────

test("set: diagnostics for unopened file are still retrievable", function()
  reset()
  local tmpdir = vim.fn.tempname()
  vim.fn.mkdir(tmpdir, "p")
  local filepath = tmpdir .. "/not_open.ts"
  vim.fn.writefile({ "// not open" }, filepath)

  diagnostics.set(filepath, { make_diag(5, vim.diagnostic.severity.WARN, "Unopened file finding") })

  local found = false
  for _, d in ipairs(vim.diagnostic.get()) do
    if d.message == "Unopened file finding" then
      found = true
      break
    end
  end
  assert(found, "diagnostic for unopened file not found in vim.diagnostic.get() — this is the Telescope bug!")
end)

h.summary()
