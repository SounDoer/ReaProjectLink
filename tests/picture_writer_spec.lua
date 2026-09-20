local json = require("readelivery.json")
local picture_writer = require("readelivery.picture_writer")

local files = {}
local locked = false
local fail_atomic = false
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
  if fail_atomic then
    fail_atomic = false
    return nil, "simulated pointer failure"
  end
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

local snapshot = { schemaVersion = 2, pictureId = "picture-1", pictureRevision = 1 }
local pointer = {
  schemaVersion = 2,
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

local snapshot_two = {
  schemaVersion = 2,
  pictureId = "picture-1",
  pictureRevision = 2,
  publishedAt = "2026-09-20T10:00:00Z",
  publishedBy = "Alice",
}
local pointer_two = {
  schemaVersion = 2,
  pictureId = "picture-1",
  latestPictureRevision = 2,
  manifest = "picture-history/picture-0002.json",
}
local retry_input = {
  package_root = "package",
  expected_revision = 1,
  transaction_id = "tx-2",
  snapshot = snapshot_two,
  pointer = pointer_two,
}
fail_atomic = true
assert(picture_writer.publish(retry_input, fs) == nil, "pointer failure is uncommitted")
local fresh_snapshot = {}
for key, value in pairs(snapshot_two) do fresh_snapshot[key] = value end
fresh_snapshot.publishedAt = "2026-09-20T10:01:00Z"
fresh_snapshot.publishedBy = "Bob"
local fresh_retry = {}
for key, value in pairs(retry_input) do fresh_retry[key] = value end
fresh_retry.transaction_id = "tx-2-fresh"
fresh_retry.snapshot = fresh_snapshot
local retried, retry_error = picture_writer.publish(fresh_retry, fs)
assert(retried, retry_error)
assert(json.decode(files["package/picture.json"]).latestPictureRevision == 2, "Picture retry commits pointer")

local rejected = picture_writer.publish({
  package_root = "old-package",
  expected_revision = 0,
  transaction_id = "tx-old",
  snapshot = { schemaVersion = 1, pictureId = "old", pictureRevision = 1 },
  pointer = {
    schemaVersion = 1,
    pictureId = "old",
    latestPictureRevision = 1,
    manifest = "picture-history/picture-0001.json",
  },
}, fs)
assert(not rejected, "unpublished Picture schema version 1 is rejected")

return 3
