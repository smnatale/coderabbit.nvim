local M = {}

local config = require("coderabbit.config")
local cli = require("coderabbit.cli")
local parser = require("coderabbit.parser")
local diagnostics = require("coderabbit.diagnostics")

local state = {
  job_id = nil,
  findings = {},
  cwd = nil,
}

function M.is_running()
  return state.job_id ~= nil
end

function M.get_results()
  return state.findings
end

function M.run(opts)
  opts = opts or {}

  if M.is_running() then
    vim.notify("CodeRabbit: Review already in progress", vim.log.levels.WARN)
    return
  end

  if not cli.is_available() then
    vim.notify(
      "CodeRabbit: CLI not found. Install with: curl -fsSL https://cli.coderabbit.ai/install.sh | sh",
      vim.log.levels.ERROR
    )
    return
  end

  state.findings = {}
  state.cwd = vim.fn.getcwd()
  local cfg = config.get()
  local finding_count = 0
  local got_error = false

  vim.notify("CodeRabbit: Reviewing...")

  state.job_id = cli.review(opts, {
    on_line = function(line)
      local event = parser.parse_line(line)
      if not event then
        return
      end

      if event.type == "status" then
        vim.notify("CodeRabbit: " .. (event.status or event.phase or "working..."), vim.log.levels.INFO)
      elseif event.type == "finding" then
        finding_count = finding_count + 1
        local diag, filepath = parser.finding_to_diagnostic(event, state.cwd, cfg.diagnostics.severity_map)
        if diag then
          table.insert(state.findings, { diagnostic = diag, filepath = filepath })
          if cfg.diagnostics.enabled then
            diagnostics.set(filepath, { diag })
          end
        end
      elseif event.type == "error" then
        got_error = true
        local msg = event.message or "Unknown error"
        if msg:match("[Aa]uth") then
          msg = msg .. "\nRun: cr auth login"
        end
        vim.notify("CodeRabbit: " .. msg, vim.log.levels.ERROR)
      end
    end,

    on_exit = function(code, stderr)
      state.job_id = nil

      if code == -1 then
        vim.notify("CodeRabbit: Review timed out", vim.log.levels.ERROR)
        return
      end

      -- Don't double-report if we already showed a JSON error event
      if code ~= 0 and not got_error and finding_count == 0 then
        local msg = stderr ~= "" and stderr or "Review failed (exit code " .. code .. ")"
        if msg:match("[Aa]uth") then
          msg = msg .. "\nRun: cr auth login"
        end
        vim.notify("CodeRabbit: " .. msg, vim.log.levels.ERROR)
        return
      end

      if not got_error then
        local summary =
          string.format("CodeRabbit: Review complete. %d finding%s.", finding_count, finding_count == 1 and "" or "s")
        vim.notify(summary, vim.log.levels.INFO)
      end

      if cfg.on_review_complete then
        cfg.on_review_complete(state.findings)
      end
    end,
  })
end

function M.stop()
  if state.job_id then
    cli.cancel(state.job_id)
    state.job_id = nil
    vim.notify("CodeRabbit: Review cancelled", vim.log.levels.INFO)
  else
    vim.notify("CodeRabbit: No review in progress", vim.log.levels.WARN)
  end
end

function M.clear()
  diagnostics.clear()
  state.findings = {}
  vim.notify("CodeRabbit: Cleared", vim.log.levels.INFO)
end

return M
