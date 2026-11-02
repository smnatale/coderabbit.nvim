local severity = require("coderabbit.severity")
local h = require("tests.helpers")
local test, eq = h.test, h.eq

local function finding(raw, diag_severity)
  return {
    filepath = "/tmp/repo/a.lua",
    diagnostic = {
      lnum = 0,
      col = 0,
      severity = diag_severity or h.I,
      message = raw or "finding",
      user_data = raw and { severity_raw = raw } or nil,
    },
  }
end

test("normalize: accepts CodeRabbit severities", function()
  eq(severity.normalize("critical"), "critical")
  eq(severity.normalize("major"), "major")
  eq(severity.normalize("minor"), "minor")
end)

test("normalize: accepts diagnostic aliases", function()
  eq(severity.normalize("error"), "critical")
  eq(severity.normalize("warning"), "major")
  eq(severity.normalize("info"), "minor")
end)

test("parse_filter: parses comma-separated severities", function()
  local filter, err = severity.parse_filter("critical,major")
  eq(err, nil)
  eq(filter.critical, true)
  eq(filter.major, true)
  eq(filter.minor, nil)
end)

test("parse_filter: all disables filtering", function()
  local filter, err = severity.parse_filter("all")
  eq(err, nil)
  eq(filter, nil)
end)

test("parse_filter: rejects unknown severity alongside all", function()
  local filter, err = severity.parse_filter("all,blocker")
  eq(filter, nil)
  assert(err and err:find("invalid severity", 1, true), "expected invalid severity error")
end)

test("parse_filter: rejects unknown severity", function()
  local filter, err = severity.parse_filter("blocker")
  eq(filter, nil)
  assert(err:find("invalid severity", 1, true), "expected invalid severity error")
end)

test("filter_findings: matches raw CodeRabbit severity", function()
  local filter = assert(severity.parse_filter("critical"))
  local findings = {
    finding("critical", h.E),
    finding("major", h.W),
  }
  local filtered = severity.filter_findings(findings, filter)
  eq(#filtered, 1)
  eq(filtered[1], findings[1])
end)

test("filter_findings: falls back to diagnostic severity", function()
  local filter = assert(severity.parse_filter("critical"))
  local findings = {
    finding(nil, h.E),
    finding(nil, h.W),
  }
  local filtered = severity.filter_findings(findings, filter)
  eq(#filtered, 1)
  eq(filtered[1], findings[1])
end)

h.summary()
