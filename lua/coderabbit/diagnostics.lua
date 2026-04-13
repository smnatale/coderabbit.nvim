local M = {}

local config = require("coderabbit.config")

M.ns = vim.api.nvim_create_namespace("coderabbit")

-- Pending diagnostics for files not yet opened
local pending = {}

function M.setup()
  local cfg = config.get()
  vim.diagnostic.config({
    virtual_text = cfg.diagnostics.virtual_text and {
      prefix = "●",
      source = "if_many",
    } or false,
    signs = cfg.diagnostics.signs,
    underline = cfg.diagnostics.underline,
    severity_sort = true,
  }, M.ns)
end

--- Set diagnostics for a file path.
--- If the buffer is loaded, sets immediately. Otherwise stores as pending.
function M.set(filepath, diagnostics)
  local bufnr = vim.fn.bufnr(filepath)
  if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
    -- Append to existing diagnostics for this buffer
    local existing = vim.diagnostic.get(bufnr, { namespace = M.ns })
    local merged = vim.list_extend(existing, diagnostics)
    vim.diagnostic.set(M.ns, bufnr, merged)
  else
    -- Store pending, will apply when buffer is opened
    if not pending[filepath] then
      pending[filepath] = {}
    end
    vim.list_extend(pending[filepath], diagnostics)
    M._ensure_autocmd()
  end
end

local autocmd_created = false

function M._ensure_autocmd()
  if autocmd_created then
    return
  end
  autocmd_created = true

  local group = vim.api.nvim_create_augroup("CodeRabbitPending", { clear = true })
  vim.api.nvim_create_autocmd("BufReadPost", {
    group = group,
    callback = function(args)
      local bufpath = vim.api.nvim_buf_get_name(args.buf)
      if pending[bufpath] then
        vim.diagnostic.set(M.ns, args.buf, pending[bufpath])
        pending[bufpath] = nil
      end
    end,
  })
end

function M.clear()
  vim.diagnostic.reset(M.ns)
  pending = {}
end

return M
