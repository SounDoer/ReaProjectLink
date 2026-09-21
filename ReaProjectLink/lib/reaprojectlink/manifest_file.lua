local json = require("reaprojectlink.json")

local M = {}

function M.read(fs, path, label, schema_version)
  local bytes, read_error = fs.read_file(path)
  if not bytes then return nil, read_error or ("Could not read " .. label .. ".") end
  local ok, value = pcall(json.decode, bytes)
  if not ok then return nil, label .. " is invalid JSON: " .. tostring(value) end
  if schema_version and value.schemaVersion ~= schema_version then
    return nil, label .. " uses an unsupported schema version."
  end
  return value
end

-- Raises instead of returning an error; level 3 blames the writer's caller.
function M.decode(fs, path, label)
  local bytes, read_error = fs.read_file(path)
  if not bytes then error(read_error or ("could not read " .. label), 3) end
  local ok, value = pcall(json.decode, bytes)
  if not ok then error(label .. " failed JSON validation: " .. tostring(value), 3) end
  return value
end

function M.retry_equivalent(left, right)
  local function without_publication_metadata(value)
    local copy = {}
    for key, entry in pairs(value) do
      if key ~= "publishedAt" and key ~= "publishedBy" then copy[key] = entry end
    end
    return copy
  end
  return json.encode(without_publication_metadata(left)) ==
    json.encode(without_publication_metadata(right))
end

return M
