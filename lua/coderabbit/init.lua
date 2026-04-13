local M = {}

function M.setup(opts)
  local config = require("coderabbit.config")
  config.setup(opts)

  local diagnostics = require("coderabbit.diagnostics")
  diagnostics.setup()
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
