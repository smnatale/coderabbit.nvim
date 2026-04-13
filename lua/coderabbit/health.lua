local M = {}

function M.check()
  vim.health.start("coderabbit.nvim")

  -- Neovim version
  if vim.fn.has("nvim-0.10") == 1 then
    vim.health.ok("Neovim >= 0.10")
  else
    vim.health.error("Neovim >= 0.10 required")
  end

  -- Configuration
  local config = require("coderabbit.config")
  local configured = config._current ~= nil

  if configured then
    vim.health.ok("Plugin configured")
  else
    vim.health.warn("setup() has not been called yet", {
      'Add require("coderabbit").setup({}) to your config',
    })
  end

  -- CLI binary
  local cfg = config.get()
  local binary = cfg.cli.binary

  if vim.fn.executable(binary) == 1 then
    vim.health.ok("CLI found: " .. binary)

    -- CLI version
    local version = vim.fn.system({ binary, "--version" })
    version = vim.trim(version)
    if vim.v.shell_error == 0 and version ~= "" then
      vim.health.ok("CLI version: " .. version)
    else
      vim.health.warn("Could not determine CLI version")
    end

    -- Authentication
    local auth_raw = vim.fn.system({ binary, "auth", "status", "--agent" })
    if vim.v.shell_error == 0 then
      local ok, auth = pcall(vim.json.decode, auth_raw)
      if ok and auth.authenticated then
        local user = auth.user and auth.user.username or "unknown"
        local org = auth.currentOrg and auth.currentOrg.name or "none"
        vim.health.ok("Authenticated as " .. user .. " (org: " .. org .. ")")
      else
        vim.health.warn("Not authenticated", { "Run: " .. binary .. " auth login" })
      end
    else
      vim.health.warn("Could not check auth status", { "Run: " .. binary .. " auth login" })
    end
  else
    vim.health.error("CLI not found: " .. binary, {
      "Install with: curl -fsSL https://cli.coderabbit.ai/install.sh | sh",
    })
  end

end

return M
