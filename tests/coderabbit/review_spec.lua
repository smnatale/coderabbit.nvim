local cli = require("coderabbit.cli")
local config = require("coderabbit.config")
local diagnostics = require("coderabbit.diagnostics")
local review = require("coderabbit.review")
local storage = require("coderabbit.storage")
local h = require("tests.helpers")
local test, eq = h.test, h.eq

local test_dir = vim.fn.tempname() .. "/coderabbit_review_test"
storage._set_base_dir(test_dir)

local tmpdir = vim.fn.tempname()
vim.fn.mkdir(tmpdir, "p")

local orig_is_available, orig_review = cli.is_available, cli.review

-- Stub the CLI so `review.run` replays `events` synchronously.
local function stub_cli(events)
  cli.is_available = function()
    return true
  end
  cli.review = function(_, callbacks)
    for _, event in ipairs(events) do
      callbacks.on_line(vim.json.encode(event))
    end
    callbacks.on_exit(0, "")
    return nil
  end
end

local function finding_event(name, sev)
  local filepath = tmpdir .. "/" .. name .. ".ts"
  vim.fn.writefile({ "// mock" }, filepath)
  return {
    type = "finding",
    fileName = filepath,
    severity = sev,
    comment = sev .. " finding",
    codegenInstructions = "",
    suggestions = {},
  }
end

local function coderabbit_diagnostics()
  local total = 0
  for _, d in ipairs(vim.diagnostic.get(nil, { namespace = diagnostics.ns })) do
    if d.source == "coderabbit" then
      total = total + 1
    end
  end
  return total
end

local function with_filter(filter, fn)
  local prev = config.get().diagnostics.severity_filter
  config.get().diagnostics.severity_filter = filter
  local ok, err = pcall(fn)
  config.get().diagnostics.severity_filter = prev
  if not ok then
    error(err, 2)
  end
end

local function cleanup()
  cli.is_available, cli.review = orig_is_available, orig_review
  vim.fn.delete(test_dir, "rf")
  diagnostics.clear()
end

-- ──────────────────────────────────────────────────────────
-- Tests
-- ──────────────────────────────────────────────────────────

test("run: invalid diagnostics filter keeps previous results", function()
  cleanup()
  stub_cli({ finding_event("kept", "major") })
  review.run()
  eq(#review.get_results(), 1)

  with_filter("blocker", function()
    review.run()
    eq(#review.get_results(), 1)
  end)
end)

test("run: new review replaces previous diagnostics", function()
  cleanup()
  stub_cli({ finding_event("old_major", "major") })
  review.run()
  eq(coderabbit_diagnostics(), 1)

  with_filter("critical", function()
    stub_cli({ finding_event("new_critical", "critical") })
    review.run()
    eq(coderabbit_diagnostics(), 1)
  end)
end)

cleanup()
vim.fn.delete(tmpdir, "rf")
h.summary()
