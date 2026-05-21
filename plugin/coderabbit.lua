if vim.g.loaded_coderabbit then
  return
end
vim.g.loaded_coderabbit = true

local function ensure_setup()
  if not require("coderabbit.config")._current then
    require("coderabbit").setup({})
  end
end

local severity_names = require("coderabbit.severity").names

local function parse_id_and_severity(command, args)
  local id = nil
  local severity = nil

  if args.fargs[1] then
    id = tonumber(args.fargs[1])
    if id then
      severity = args.fargs[2]
      if args.fargs[3] then
        vim.notify(command .. ": too many arguments", vim.log.levels.ERROR)
        return nil, nil, false
      end
    else
      severity = args.fargs[1]
      if args.fargs[2] then
        vim.notify(command .. ": invalid review ID: " .. args.fargs[1], vim.log.levels.ERROR)
        return nil, nil, false
      end
    end
  end

  if severity then
    local _, err = require("coderabbit.severity").parse_filter(severity)
    if err then
      vim.notify(command .. ": " .. err, vim.log.levels.ERROR)
      return nil, nil, false
    end
  end

  return id, severity, true
end

local function severity_completion(arglead)
  local completions = vim.list_extend(vim.deepcopy(severity_names), { "all" })
  return vim.tbl_filter(function(item)
    return item:find(arglead, 1, true) == 1
  end, completions)
end

local function id_and_severity_completion(arglead, cmdline, cursorpos)
  cursorpos = cursorpos or (#cmdline + 1)
  local before_cursor = cmdline:sub(1, cursorpos - 1)
  local has_trailing_space = before_cursor:match("%s$") ~= nil
  local args = vim.split(before_cursor, "%s+", { trimempty = true })
  local first_arg = args[2]
  local ids = require("coderabbit.storage").ids()

  if not first_arg or (first_arg and #args == 2 and not has_trailing_space) then
    local completions = vim.list_extend(ids, severity_completion(arglead))
    return vim.tbl_filter(function(item)
      return item:find(arglead, 1, true) == 1
    end, completions)
  end

  if tonumber(first_arg) and (#args <= 3 or has_trailing_space) then
    return severity_completion(arglead)
  end

  return {}
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
  local id, severity, ok = parse_id_and_severity("CodeRabbitShow", args)
  if not ok then
    return
  end
  require("coderabbit").show(id, { severity_filter = severity })
end, {
  nargs = "*",
  complete = id_and_severity_completion,
  desc = "Show CodeRabbit review results in a buffer (optional: review ID and severity)",
})

vim.api.nvim_create_user_command("CodeRabbitRestore", function(args)
  ensure_setup()
  local id = nil
  if args.fargs[1] then
    id = tonumber(args.fargs[1])
    if not id then
      vim.notify("CodeRabbitRestore: invalid review ID: " .. args.fargs[1], vim.log.levels.ERROR)
      return
    end
  end
  require("coderabbit").restore(id)
end, {
  nargs = "?",
  complete = function()
    return require("coderabbit.storage").ids()
  end,
  desc = "Restore diagnostics from a previous CodeRabbit review (default: most recent)",
})

vim.api.nvim_create_user_command("CodeRabbitHistory", function()
  ensure_setup()
  require("coderabbit").history()
end, {
  desc = "Browse CodeRabbit review history",
})

vim.api.nvim_create_user_command("CodeRabbitQuickfix", function(args)
  ensure_setup()
  local id, severity, ok = parse_id_and_severity("CodeRabbitQuickfix", args)
  if not ok then
    return
  end
  require("coderabbit").quickfix(id, { severity_filter = severity })
end, {
  nargs = "*",
  complete = id_and_severity_completion,
  desc = "Populate quickfix list with CodeRabbit findings (optional: review ID and severity)",
})
