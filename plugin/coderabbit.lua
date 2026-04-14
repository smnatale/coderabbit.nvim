if vim.g.loaded_coderabbit then
  return
end
vim.g.loaded_coderabbit = true

local function ensure_setup()
  if not require("coderabbit.config")._current then
    require("coderabbit").setup({})
  end
end

vim.api.nvim_create_user_command("CodeRabbitReview", function(args)
  ensure_setup()
  local opts = {}
  if args.fargs[1] then
    opts.type = args.fargs[1]
  end
  require("coderabbit").review(opts)
end, {
  nargs = "?",
  complete = function()
    return { "all", "committed", "uncommitted" }
  end,
  desc = "Run CodeRabbit code review",
})

vim.api.nvim_create_user_command("CodeRabbitStop", function()
  require("coderabbit").stop()
end, {
  desc = "Cancel running CodeRabbit review",
})

vim.api.nvim_create_user_command("CodeRabbitClear", function()
  require("coderabbit").clear()
end, {
  desc = "Clear CodeRabbit diagnostics",
})

vim.api.nvim_create_user_command("CodeRabbitShow", function(args)
  ensure_setup()
  local id = args.fargs[1] and tonumber(args.fargs[1]) or nil
  require("coderabbit").show(id)
end, {
  nargs = "?",
  complete = function()
    return require("coderabbit.storage").ids()
  end,
  desc = "Show CodeRabbit review results in a buffer (optional: review ID)",
})

vim.api.nvim_create_user_command("CodeRabbitHistory", function()
  ensure_setup()
  require("coderabbit").history()
end, {
  desc = "Browse CodeRabbit review history",
})
