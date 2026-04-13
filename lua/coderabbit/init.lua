local M = {}

function M.setup(opts)
  local config = require("coderabbit.config")
  config.setup(opts)

  local diagnostics = require("coderabbit.diagnostics")
  diagnostics.setup()

  -- Define highlight groups with sensible defaults
  local hl_defs = {
    CodeRabbitCritical = { link = "DiagnosticError" },
    CodeRabbitMajor = { link = "DiagnosticWarn" },
    CodeRabbitMinor = { link = "DiagnosticInfo" },
  }
  for name, val in pairs(hl_defs) do
    vim.api.nvim_set_hl(0, name, vim.tbl_extend("keep", val, { default = true }))
  end
end

function M.review(opts)
  require("coderabbit.review").run(opts)
end

function M.stop()
  require("coderabbit.review").stop()
end

function M.clear()
  require("coderabbit.review").clear()
end

return M
