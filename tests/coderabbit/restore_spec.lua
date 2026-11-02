local diagnostics = require("coderabbit.diagnostics")
local review = require("coderabbit.review")
local storage = require("coderabbit.storage")
local h = require("tests.helpers")
local test, eq = h.test, h.eq

local test_dir = vim.fn.tempname() .. "/coderabbit_restore_test"
storage._set_base_dir(test_dir)

local function flush()
  vim.wait(10, function()
    return false
  end)
end

local finding_tmpdirs = {}

local function cleanup()
  for _, dir in ipairs(finding_tmpdirs) do
    vim.fn.delete(dir, "rf")
  end
  finding_tmpdirs = {}
  vim.fn.delete(test_dir, "rf")
  diagnostics.clear()
end

local function make_findings(n)
  local tmpdir = vim.fn.tempname()
  vim.fn.mkdir(tmpdir, "p")
  table.insert(finding_tmpdirs, tmpdir)
  local findings = {}
  for i = 1, n do
    local filepath = tmpdir .. "/file" .. i .. ".ts"
    vim.fn.writefile({ "// mock" }, filepath)
    table.insert(findings, h.finding(filepath, i * 10, h.W, "finding " .. i))
  end
  return findings
end

-- ──────────────────────────────────────────────────────────
-- Tests
-- ──────────────────────────────────────────────────────────

test("restore: warns when no saved reviews exist", function()
  cleanup()
  -- Should not error, just warn
  review.restore(nil)
end)

test("restore: warns when review ID not found", function()
  cleanup()
  storage.save(make_findings(1), h.context())
  review.restore(999)
end)

test("restore: restores diagnostics from a specific review", function()
  cleanup()
  local findings = make_findings(2)
  storage.save(findings, h.context())

  review.restore(1)
  flush()

  for _, finding in ipairs(findings) do
    local bufnr = vim.fn.bufnr(finding.filepath)
    local got = vim.diagnostic.get(bufnr, { namespace = diagnostics.ns })
    eq(#got, 1)
    eq(got[1].message, finding.diagnostic.message)
  end
end)

test("restore: defaults to most recent review when no ID given", function()
  cleanup()
  local old_findings = make_findings(1)
  storage.save(old_findings, h.context("old-branch"))
  local new_findings = make_findings(2)
  storage.save(new_findings, h.context("new-branch"))

  review.restore(nil)
  flush()

  -- Should have diagnostics from the second review (2 findings)
  local total = 0
  for _, d in ipairs(vim.diagnostic.get()) do
    if d.source == "coderabbit" then
      total = total + 1
    end
  end
  eq(total, 2)
end)

test("restore: clears previous diagnostics before applying", function()
  cleanup()
  local first = make_findings(3)
  storage.save(first, h.context())
  local second = make_findings(1)
  storage.save(second, h.context())

  review.restore(1) -- 3 findings
  flush()
  review.restore(2) -- 1 finding — should replace, not accumulate
  flush()

  local total = 0
  for _, d in ipairs(vim.diagnostic.get()) do
    if d.source == "coderabbit" then
      total = total + 1
    end
  end
  eq(total, 1)
end)

local function coderabbit_diags()
  local out = {}
  for _, d in ipairs(vim.diagnostic.get()) do
    if d.source == "coderabbit" then
      table.insert(out, d)
    end
  end
  return out
end

test("restore: skips resolved and dismissed findings", function()
  cleanup()
  local findings = make_findings(3)
  findings[1].status = "resolved"
  findings[3].status = "dismissed"
  storage.save(findings, h.context())

  review.restore(1)
  flush()

  local got = coderabbit_diags()
  eq(#got, 1)
  eq(got[1].message, "finding 2")
end)

test("restore: dismissing a restored finding persists across restores", function()
  cleanup()
  local filename = storage.save(make_findings(2), h.context())

  review.restore(1)
  flush()

  local target
  for _, d in ipairs(coderabbit_diags()) do
    if d.message == "finding 1" then
      target = d
    end
  end
  assert(target, "expected finding 1 diagnostic")
  eq(target.user_data.ref.file, filename)
  eq(target.user_data.ref.index, 1)

  eq(require("coderabbit.actions").mark(target.bufnr, target, "dismissed"), true)
  eq(#coderabbit_diags(), 1)

  review.restore(1)
  flush()

  local got = coderabbit_diags()
  eq(#got, 1)
  eq(got[1].message, "finding 2")
  eq(storage.load(1).findings[1].status, "dismissed")
end)

test("set_status: rejects unknown statuses and stale refs", function()
  cleanup()
  eq(review.set_status({ file = "missing.json", index = 1 }, "resolved"), false)
  eq(review.set_status({ run = -1, index = 1 }, "resolved"), false)
  eq(review.set_status({ file = "missing.json", index = 1 }, "bogus"), false)
  eq(review.set_status(nil, "resolved"), false)
end)

cleanup()
h.summary()
