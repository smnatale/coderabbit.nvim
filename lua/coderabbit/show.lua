local M = {}

local buf_id = nil

local severity_labels = vim.diagnostic.severity

local function relative_path(filepath, cwd)
  if not cwd or not filepath then
    return filepath or ""
  end
  local prefix = cwd
  if prefix:sub(-1) ~= "/" then
    prefix = prefix .. "/"
  end
  if filepath:sub(1, #prefix) == prefix then
    return filepath:sub(#prefix + 1)
  end
  return filepath
end

local function lang_from_path(filepath)
  return filepath:match("%.([^%.]+)$") or ""
end

local function line_label(diag)
  if diag.end_lnum and diag.end_lnum ~= diag.lnum then
    return string.format("Lines %d-%d", diag.lnum + 1, diag.end_lnum + 1)
  end
  if diag.lnum > 0 then
    return string.format("Line %d", diag.lnum + 1)
  end
  return nil
end

--- Render findings and context into an array of markdown lines.
--- @param findings table[] Array of { diagnostic, filepath }
--- @param context table|nil Review context metadata
--- @param opts table|nil { cwd = string }
--- @return string[]
function M.render(findings, context, opts)
  opts = opts or {}
  local lines = {}

  table.insert(lines, "# CodeRabbit Review")
  table.insert(lines, "")

  if context then
    local parts = {}
    if context.review_type then
      table.insert(parts, "**Type:** " .. context.review_type)
    end
    if context.current_branch then
      table.insert(parts, "**Branch:** " .. context.current_branch)
    end
    if context.base_branch then
      table.insert(parts, "**Base:** " .. context.base_branch)
    end
    if context.base_commit then
      table.insert(parts, "**Commit:** " .. context.base_commit)
    end
    if #parts > 0 then
      table.insert(lines, table.concat(parts, " | "))
    end
    table.insert(lines, string.format("**Findings:** %d", #findings))
    table.insert(lines, "")
  end

  table.insert(lines, "---")
  table.insert(lines, "")

  if #findings == 0 then
    table.insert(lines, "*No findings -- your code looks good!*")
    return lines
  end

  -- Group findings by filepath
  local by_file = {}
  local file_order = {}
  for _, f in ipairs(findings) do
    local rel = relative_path(f.filepath, opts.cwd)
    if not by_file[rel] then
      by_file[rel] = {}
      table.insert(file_order, rel)
    end
    table.insert(by_file[rel], f.diagnostic)
  end
  table.sort(file_order)

  for i, filepath in ipairs(file_order) do
    if i > 1 then
      table.insert(lines, "---")
      table.insert(lines, "")
    end

    table.insert(lines, "## " .. filepath)
    table.insert(lines, "")

    local lang = lang_from_path(filepath)

    for _, diag in ipairs(by_file[filepath]) do
      local sev = severity_labels[diag.severity] or "INFO"
      local loc = line_label(diag)
      if loc then
        table.insert(lines, string.format("### [%s] %s", sev, loc))
      else
        table.insert(lines, string.format("### [%s]", sev))
      end
      table.insert(lines, "")
      table.insert(lines, diag.message)
      table.insert(lines, "")

      local suggestions = diag.user_data and diag.user_data.suggestions or {}
      if #suggestions > 0 then
        table.insert(lines, "**Suggested fix:**")
        table.insert(lines, "")
        for _, suggestion in ipairs(suggestions) do
          table.insert(lines, "```" .. lang)
          for sline in (suggestion .. "\n"):gmatch("([^\n]*)\n") do
            table.insert(lines, sline)
          end
          table.insert(lines, "```")
          table.insert(lines, "")
        end
      end
    end
  end

  return lines
end

function M.open(id)
  local review = require("coderabbit.review")
  local findings, context, running

  if id then
    local entry = review.get_review(id)
    if not entry then
      vim.notify("CodeRabbit: Review #" .. id .. " not found", vim.log.levels.WARN)
      return
    end
    findings = entry.findings
    context = entry.context
    running = false
  else
    findings = review.get_results()
    context = review.get_context()
    running = review.is_running()
  end

  if #findings == 0 and not running and not context then
    vim.notify("CodeRabbit: No review results. Run :CodeRabbitReview first", vim.log.levels.WARN)
    return
  end

  local content = M.render(findings, context, { cwd = context and context.cwd or vim.fn.getcwd() })
  if running then
    table.insert(content, 1, "")
    table.insert(
      content,
      1,
      string.format(
        "> **Review in progress...** Showing %d finding%s so far. Run `:CodeRabbitShow` again to refresh.",
        #findings,
        #findings == 1 and "" or "s"
      )
    )
  end

  -- Reuse existing buffer if visible
  if buf_id and vim.api.nvim_buf_is_valid(buf_id) then
    local winid = vim.fn.bufwinid(buf_id)
    if winid ~= -1 then
      vim.api.nvim_set_current_win(winid)
    else
      vim.cmd("vsplit")
      vim.api.nvim_win_set_buf(0, buf_id)
    end
    vim.api.nvim_set_option_value("modifiable", true, { buf = buf_id })
    vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, content)
    vim.api.nvim_set_option_value("modifiable", false, { buf = buf_id })
    return
  end

  buf_id = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf_id, "coderabbit://review")
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf_id })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf_id })
  vim.api.nvim_set_option_value("swapfile", false, { buf = buf_id })
  vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf_id })

  vim.api.nvim_buf_set_lines(buf_id, 0, -1, false, content)
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf_id })

  vim.cmd("vsplit")
  vim.api.nvim_win_set_buf(0, buf_id)

  vim.api.nvim_set_option_value("number", false, { win = 0 })
  vim.api.nvim_set_option_value("relativenumber", false, { win = 0 })
  vim.api.nvim_set_option_value("signcolumn", "no", { win = 0 })
  vim.api.nvim_set_option_value("wrap", true, { win = 0 })
  vim.api.nvim_set_option_value("linebreak", true, { win = 0 })
  vim.api.nvim_set_option_value("spell", false, { win = 0 })
  vim.api.nvim_set_option_value("conceallevel", 2, { win = 0 })

  vim.keymap.set("n", "q", function()
    M.close()
  end, { buffer = buf_id, nowait = true, silent = true })

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf_id,
    once = true,
    callback = function()
      buf_id = nil
    end,
  })
end

function M.close()
  local id = buf_id
  buf_id = nil
  if not id or not vim.api.nvim_buf_is_valid(id) then
    return
  end
  local winid = vim.fn.bufwinid(id)
  if winid ~= -1 then
    vim.api.nvim_win_close(winid, true)
  end
  if vim.api.nvim_buf_is_valid(id) then
    vim.api.nvim_buf_delete(id, { force = true })
  end
end

function M.is_open()
  return buf_id ~= nil and vim.api.nvim_buf_is_valid(buf_id) and vim.fn.bufwinid(buf_id) ~= -1
end

--- Exposed for testing.
M._get_buf_id = function()
  return buf_id
end

M._reset = function()
  if buf_id and vim.api.nvim_buf_is_valid(buf_id) then
    vim.api.nvim_buf_delete(buf_id, { force = true })
  end
  buf_id = nil
end

return M
