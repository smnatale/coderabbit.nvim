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

  -- Re-attach the code-action LSP client when entering a buffer whose
  -- diagnostics were set while it was still unloaded.
  vim.api.nvim_create_autocmd("BufEnter", {
    group = vim.api.nvim_create_augroup("coderabbit_actions", { clear = true }),
    callback = function(args)
      local bufnr = args.buf
      if #vim.diagnostic.get(bufnr, { namespace = M.ns }) > 0 then
        if #vim.lsp.get_clients({ name = "coderabbit", bufnr = bufnr }) == 0 then
          require("coderabbit.actions").attach(bufnr)
        end
      end
    end,
  })
end

--- Set diagnostics for a file path.
--- Uses bufadd() to ensure a buffer always exists so diagnostics are
--- immediately visible to vim.diagnostic.get() (and thus Telescope).
function M.set(filepath, diagnostics)
  filepath = vim.fn.fnamemodify(filepath, ":p")
  local bufnr = vim.fn.bufadd(filepath)
  vim.fn.bufload(bufnr)
  -- Append to existing diagnostics for this buffer
  local existing = vim.diagnostic.get(bufnr, { namespace = M.ns })
  local merged = vim.list_extend(existing, diagnostics)
  vim.diagnostic.set(M.ns, bufnr, merged)
  require("coderabbit.actions").attach(bufnr)
end

function M.clear()
  vim.diagnostic.reset(M.ns)
end

return M
