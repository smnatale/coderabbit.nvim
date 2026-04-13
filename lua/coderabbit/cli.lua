local M = {}

local config = require("coderabbit.config")

function M.is_available()
  local cfg = config.get()
  return vim.fn.executable(cfg.cli.binary) == 1
end

--- Build the command table for `cr review --agent`.
local function build_cmd(opts)
  local cfg = config.get()
  local cmd = { cfg.cli.binary, "review", "--agent", "--no-color" }

  local review_type = opts.type or cfg.review.type
  if review_type then
    table.insert(cmd, "--type")
    table.insert(cmd, review_type)
  end

  local base = opts.base or cfg.review.base
  if base then
    table.insert(cmd, "--base")
    table.insert(cmd, base)
  end

  local base_commit = opts.base_commit or cfg.review.base_commit
  if base_commit then
    table.insert(cmd, "--base-commit")
    table.insert(cmd, base_commit)
  end

  for _, arg in ipairs(cfg.cli.extra_args) do
    table.insert(cmd, arg)
  end

  return cmd
end

--- Run a review asynchronously.
--- @param opts table Review options (type, base, base_commit)
--- @param callbacks table { on_line, on_exit }
---   on_line(line: string) — called for each stdout line
---   on_exit(code: number, stderr: string) — called on process exit
--- @return number job_id
function M.review(opts, callbacks)
  local cmd = build_cmd(opts)
  local stderr_chunks = {}
  local cfg = config.get()
  local timer = nil

  local job_id = vim.fn.jobstart(cmd, {
    cwd = vim.fn.getcwd(),
    stdout_buffered = false,
    on_stdout = function(_, data, _)
      if not data then
        return
      end
      for _, line in ipairs(data) do
        if line ~= "" then
          vim.schedule(function()
            if callbacks.on_line then
              callbacks.on_line(line)
            end
          end)
        end
      end
    end,
    on_stderr = function(_, data, _)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            table.insert(stderr_chunks, line)
          end
        end
      end
    end,
    on_exit = function(_, code, _)
      if timer then
        vim.fn.timer_stop(timer)
      end
      local stderr = table.concat(stderr_chunks, "\n")
      vim.schedule(function()
        if callbacks.on_exit then
          callbacks.on_exit(code, stderr)
        end
      end)
    end,
  })

  if job_id > 0 and cfg.cli.timeout > 0 then
    timer = vim.fn.timer_start(cfg.cli.timeout, function()
      vim.fn.jobstop(job_id)
      vim.schedule(function()
        if callbacks.on_exit then
          callbacks.on_exit(-1, "Review timed out")
        end
      end)
    end)
  end

  return job_id
end

function M.cancel(job_id)
  if job_id and job_id > 0 then
    pcall(vim.fn.jobstop, job_id)
  end
end

return M
