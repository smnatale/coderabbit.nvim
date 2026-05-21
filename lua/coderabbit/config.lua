local M = {}

M.defaults = {
  cli = {
    binary = "cr",
    timeout = 0,
    extra_args = {},
  },
  review = {
    type = "all",
    base = nil,
    base_commit = nil,
  },
  diagnostics = {
    enabled = true,
    severity_filter = nil,
    severity_map = {
      critical = vim.diagnostic.severity.ERROR,
      major = vim.diagnostic.severity.WARN,
      minor = vim.diagnostic.severity.INFO,
    },
    virtual_text = true,
    signs = true,
    underline = true,
  },
  show = {
    layout = "float",
    severity_filter = nil,
    float = {
      width = 0.6,
      height = 0.7,
      border = "rounded",
    },
  },
  quickfix = {
    auto = false,
    severity_filter = nil,
  },
  history = {
    max_entries = 50,
  },
  on_review_complete = nil,
}

M._current = nil

function M.setup(user_opts)
  M._current = vim.tbl_deep_extend("force", {}, M.defaults, user_opts or {})
  return M._current
end

function M.get()
  if not M._current then
    M._current = vim.tbl_deep_extend("force", {}, M.defaults)
  end
  return M._current
end

return M
