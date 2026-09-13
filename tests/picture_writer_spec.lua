local json = require("readelivery.json")
local picture_writer = require("readelivery.picture_writer")

local files = {}
local locked = false
local fs = {}
function fs.join(...) return table.concat({ ... }, "/"):gsub("/+", "/") end
function fs.exists(path) return files[path] ~= nil end
function fs.read_file(path) return files[path] end
function fs.write_file(path, bytes) files[path] = bytes; return true end
function fs.make_directory() return true end
function fs.move_file(source, destination)
  if files[destination] then return nil, "destination exists" end
  files[destination], files[source] = files[source], nil
  return true
end
function fs.atomic_replace(source, destination)
  files[destination], files[source] = files[source], nil
  return true
end
function fs.remove_tree(prefix)
  for path in pairs(files) do
    if path:sub(1, #prefix) == prefix then files[path] = nil end
  end
  return true
end
function fs.acquire_lock()
  if locked then return nil, "locked" end
  locked = true
  return "token"
end
function fs.release_lock() locked = false; return true end

local snapshot = { schemaVersion = 1, pictureId = "picture-1", pictureRevision = 1 }
local pointer = {
  schemaVersion = 1,
  pictureId = "picture-1",
  latestPictureRevision = 1,
  manifest = "picture-history/picture-0001.json",
}
local result, err = picture_writer.publish({
  package_root = "package",
  expected_revision = 0,
  transaction_id = "tx-1",
  snapshot = snapshot,
  pointer = pointer,
}, fs)

assert(result, err)
assert(not locked, "lock released")
assert(json.decode(files["package/picture.json"]).latestPictureRevision == 1, "pointer visible")
assert(json.decode(files["package/picture-history/picture-0001.json"]).pictureRevision == 1, "history visible")

return 1
