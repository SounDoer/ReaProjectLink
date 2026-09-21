local M = {}

function M.project_parts(path)
  local directory, filename = path:match("^(.*)[/\\]([^/\\]+)$")
  if not directory then return nil, nil end
  return directory, filename:gsub("%.[Rr][Pp][Pp]$", "")
end

function M.same(left, right)
  if not left or not right then return false end
  return left:gsub("\\", "/"):lower() == right:gsub("\\", "/"):lower()
end

return M
