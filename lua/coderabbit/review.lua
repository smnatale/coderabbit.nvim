local M = {}

local config = require("coderabbit.config")
local cli = require("coderabbit.cli")
local parser = require("coderabbit.parser")
local diagnostics = require("coderabbit.diagnostics")
local utils = require("coderabbit.utils")

local spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local FRAME_MS = 80

local state = {
  job_id = nil,
  findings = {},
  cwd = nil,
  start_time = nil,
  fidget_handle = nil,
  last_notify_time = nil,
  review_type = nil,
  current_branch = nil,
  base_branch = nil,
  base_commit = nil,
}

local storage = require("coderabbit.storage")

local function spinner()
  local idx = math.floor(vim.uv.hrtime() / (1e6 * FRAME_MS)) % #spinner_frames + 1
  return spinner_frames[idx]
end

local function fidget_start()
  local ok, progress = pcall(require, "fidget.progress")
  if not ok then
    return nil
  end
  return progress.handle.create({
    title = "Reviewing",
    message = "analyzing...",
    lsp_client = { name = "coderabbit" },
  })
end

local function fidget_update(msg)
  if state.fidget_handle then
    state.fidget_handle.message = msg
  end
end

local function fidget_finish(msg)
  if state.fidget_handle then
    state.fidget_handle.message = msg
    state.fidget_handle:finish()
    state.fidget_handle = nil
  end
end

function M.is_running()
  return state.job_id ~= nil
end

function M.get_results()
  return state.findings
end

function M.get_context()
  if not state.cwd and not state.review_type then
    return nil
  end
  return {
    cwd = state.cwd,
    review_type = state.review_type,
    current_branch = state.current_branch,
    base_branch = state.base_branch,
    base_commit = state.base_commit,
    start_time = state.start_time,
  }
end

function M.get_history()
  return storage.list()
end

function M.get_review(id)
  return storage.load(id)
end

--- Return a short status string for statusline integration.
--- Returns nil when no review is running.
function M.status()
  if not state.job_id then
    return nil
  end
  local elapsed = os.time() - state.start_time
  return string.format("%s CodeRabbit (%ds)", spinner(), elapsed)
end

function M.run(opts)
  opts = opts or {}

  if M.is_running() then
    utils.notify("Review already in progress", vim.log.levels.WARN)
    return
  end

  if not cli.is_available() then
    utils.notify(
      "CLI not found. Install with: curl -fsSL https://cli.coderabbit.ai/install.sh | sh",
      vim.log.levels.ERROR
    )
    return
  end

  state.findings = {}
  state.cwd = vim.fn.getcwd()
  local cfg = config.get()
  local finding_count = 0
  local got_error = false

  utils.notify("Reviewing...")

  state.start_time = os.time()
  state.fidget_handle = fidget_start()

  state.job_id = cli.review(opts, {
    on_line = function(line)
      local event = parser.parse_line(line)
      if not event then
        return
      end

      if event.type == "review_context" then
        if event.workingDirectory then
          state.cwd = event.workingDirectory
        end
        state.review_type = event.reviewType
        state.current_branch = event.currentBranch
        state.base_branch = event.baseBranch
        state.base_commit = event.baseCommit
      elseif event.type == "status" then
        local msg = event.status or event.phase or "working..."
        if state.fidget_handle then
          fidget_update(msg)
        else
          local now = os.time()
          if not state.last_notify_time or (now - state.last_notify_time) >= 20 then
            state.last_notify_time = now
            utils.notify(msg)
          end
        end
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
        if event.errorType then
          msg = "[" .. event.errorType .. "] " .. msg
        end
        if event.metadata and event.metadata.waitTime then
          msg = msg .. " (retry in " .. event.metadata.waitTime .. ")"
        end
        if event.details and type(event.details) == "table" and next(event.details) then
          msg = msg .. "\n" .. vim.inspect(event.details)
        end
        if msg:match("[Aa]uth") then
          msg = msg .. "\nRun: cr auth login"
        end
        utils.notify(msg, vim.log.levels.ERROR)
      end
    end,

    on_exit = function(code, stderr)
      state.job_id = nil
      state.start_time = nil
      state.last_notify_time = nil

      if code == -1 then
        fidget_finish("timed out")
        utils.notify("Review timed out", vim.log.levels.ERROR)
        return
      end

      -- Don't double-report if we already showed a JSON error event
      if code ~= 0 and not got_error and finding_count == 0 then
        local msg = stderr ~= "" and stderr or "Review failed (exit code " .. code .. ")"
        if msg:match("[Aa]uth") then
          msg = msg .. "\nRun: cr auth login"
        end
        fidget_finish("failed")
        utils.notify(msg, vim.log.levels.ERROR)
        return
      end

      if not got_error then
        local fc = utils.pluralize(finding_count, "finding")
        utils.notify("Review complete. " .. fc .. ". Run :CodeRabbitShow to view.")
        fidget_finish("done — " .. fc)
      else
        fidget_finish("done (with errors)")
      end

      storage.save(state.findings, M.get_context())

      if cfg.on_review_complete then
        cfg.on_review_complete(state.findings)
      end
    end,
  })
end

function M.stop()
  if state.job_id then
    fidget_finish("cancelled")
    cli.cancel(state.job_id)
    state.job_id = nil
    utils.notify("Review cancelled")
  else
    utils.notify("No review in progress", vim.log.levels.WARN)
  end
end

function M.restore(id)
  local entries = storage.list()
  if #entries == 0 then
    utils.notify("No saved reviews found", vim.log.levels.WARN)
    return
  end

  if not id then
    id = entries[#entries].id
  end

  local review = storage.load(id)
  if not review then
    utils.notify("Review #" .. id .. " not found", vim.log.levels.WARN)
    return
  end

  diagnostics.clear()
  local findings = type(review.findings) == "table" and review.findings or {}
  vim.schedule(function()
    for _, finding in ipairs(findings) do
      diagnostics.set(finding.filepath, { finding.diagnostic })
    end

    utils.notify(string.format("Restored %d findings from review #%d", #findings, id))
  end)
end

function M.clear()
  diagnostics.clear()
  state.findings = {}
  state.cwd = nil
  state.start_time = nil
  state.review_type = nil
  state.current_branch = nil
  state.base_branch = nil
  state.base_commit = nil
  utils.notify("Cleared")
end

return M
