if vim.g.loaded_coderabbit then
  return
end
vim.g.loaded_coderabbit = true

vim.api.nvim_create_user_command("CodeRabbitReview", function(args)
  -- Lazy setup if not called yet
  if not require("coderabbit.config")._current then
    require("coderabbit").setup({})
  end
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
