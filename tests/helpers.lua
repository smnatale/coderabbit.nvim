local M = {}

local pass, fail = 0, 0

function M.test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    pass = pass + 1
    print("  PASS  " .. name)
  else
    fail = fail + 1
    print("  FAIL  " .. name .. "\n        " .. err)
  end
end

function M.eq(a, b)
  if a ~= b then
    error(string.format("expected %s, got %s", vim.inspect(b), vim.inspect(a)), 2)
  end
end

function M.summary()
  print(string.format("\n%d passed, %d failed", pass, fail))
  if fail > 0 then
    vim.cmd("cq1")
  end
end

return M
