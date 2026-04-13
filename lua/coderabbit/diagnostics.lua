local M = {}

local config = require("coderabbit.config")

M.ns = vim.api.nvim_create_namespace("coderabbit")

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
--- Uses bufadd() to ensure a buffer always exists so diagnostics are
--- immediately visible to vim.diagnostic.get() (and thus Telescope).
function M.set(filepath, diagnostics)
  filepath = vim.fn.fnamemodify(filepath, ":p")
  local bufnr = vim.fn.bufadd(filepath)
  -- Append to existing diagnostics for this buffer
  local existing = vim.diagnostic.get(bufnr, { namespace = M.ns })
  local merged = vim.list_extend(existing, diagnostics)
  vim.diagnostic.set(M.ns, bufnr, merged)
end

function M.clear()
  vim.diagnostic.reset(M.ns)
end

return M
