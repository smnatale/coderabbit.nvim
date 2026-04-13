local M = {}

local ns = vim.api.nvim_create_namespace("coderabbit")

--- Apply a suggestion to a buffer and remove the corresponding diagnostic.
--- @param bufnr number Buffer number
--- @param lnum number 0-indexed start line
--- @param end_lnum number|nil 0-indexed end line (nil = single line)
--- @param suggestion string Replacement text (may contain newlines)
--- @param message string Diagnostic message (used to identify which diagnostic to remove)
function M.apply(bufnr, lnum, end_lnum, suggestion, message)
  if not vim.api.nvim_buf_is_loaded(bufnr) then
    vim.fn.bufload(bufnr)
  end

  local end_line = (end_lnum or lnum) + 1
  local new_lines = vim.split(suggestion, "\n", { plain = true })
  vim.api.nvim_buf_set_lines(bufnr, lnum, end_line, false, new_lines)

  -- Remove the applied diagnostic (first match only)
  local existing = vim.diagnostic.get(bufnr, { namespace = ns })
  local remaining = {}
  local removed = false
  for _, d in ipairs(existing) do
    if not removed and d.lnum == lnum and d.message == message then
      removed = true
    else
      table.insert(remaining, d)
    end
  end
  vim.diagnostic.set(ns, bufnr, remaining)
end

--- Build code actions for coderabbit diagnostics overlapping the given range.
--- @param bufnr number Buffer number
--- @param range table LSP-style range { start = { line = N }, ["end"] = { line = N } }
--- @return table[] LSP code actions
function M.get_actions(bufnr, range)
  local start_line = range.start.line
  local end_line = range["end"].line

  local diags = vim.diagnostic.get(bufnr, { namespace = ns })
  local actions = {}

  for _, diag in ipairs(diags) do
    local diag_end = diag.end_lnum or diag.lnum
    -- Check if diagnostic range overlaps the requested range
    if diag.lnum <= end_line and diag_end >= start_line then
      local suggestions = diag.user_data and diag.user_data.suggestions or {}
      for i, suggestion in ipairs(suggestions) do
        local title = #suggestions > 1 and string.format("CodeRabbit: Apply fix (%d/%d)", i, #suggestions)
          or "CodeRabbit: Apply fix"
        table.insert(actions, {
          title = title,
          kind = "quickfix",
          command = {
            title = title,
            command = "coderabbit.apply",
            arguments = {
              {
                bufnr = bufnr,
                lnum = diag.lnum,
                end_lnum = diag.end_lnum,
                suggestion = suggestion,
                message = diag.message,
              },
            },
          },
        })
      end
    end
  end

  return actions
end

--- Attach the code-action virtual LSP client to a buffer.
--- Creates the client on first call; reuses and attaches on subsequent calls.
--- @param bufnr number Buffer number
function M.attach(bufnr)
  vim.lsp.start({
    name = "coderabbit",
    cmd = function(_dispatchers)
      local closing = false
      return {
        request = function(method, params, callback)
          if method == "initialize" then
            callback(nil, {
              capabilities = {
                codeActionProvider = true,
                executeCommandProvider = {
                  commands = { "coderabbit.apply" },
                },
              },
            })
          elseif method == "shutdown" then
            callback(nil, nil)
          elseif method == "textDocument/codeAction" then
            local uri = params.textDocument.uri
            local buf = vim.uri_to_bufnr(uri)
            local result = M.get_actions(buf, params.range)
            callback(nil, result)
          elseif method == "workspace/executeCommand" then
            if params.command == "coderabbit.apply" then
              local arg = params.arguments[1]
              vim.schedule(function()
                M.apply(arg.bufnr, arg.lnum, arg.end_lnum, arg.suggestion, arg.message)
              end)
            end
            callback(nil, nil)
          else
            callback(nil, nil)
          end
        end,
        notify = function(method)
          if method == "exit" then
            closing = true
          end
        end,
        is_closing = function()
          return closing
        end,
        terminate = function()
          closing = true
        end,
      }
    end,
    root_dir = vim.fn.getcwd(),
  }, { bufnr = bufnr })
end

return M
