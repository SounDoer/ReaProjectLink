local json = require("reaprojectlink.json")
local reference_writer = require("reaprojectlink.reference_writer")

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

local snapshot = {
  schemaVersion = 2,
  masterProjectId = "master-1",
  referenceId = "reference-1",
  referenceRevision = 1,
}
local pointer = {
  schemaVersion = 2,
  masterProjectId = "master-1",
  referenceId = "reference-1",
  latestReferenceRevision = 1,
  manifest = "history/reference-0001.json",
}
local result, err = reference_writer.publish({
  package_root = "package",
  expected_revision = 0,
  transaction_id = "tx-1",
  snapshot = snapshot,
  pointer = pointer,
}, fs)

assert(result, err)
assert(not locked, "lock released")
assert(json.decode(files["package/reference.json"]).latestReferenceRevision == 1, "pointer visible")
assert(json.decode(files["package/history/reference-0001.json"]).referenceRevision == 1, "history visible")

local snapshot_two = {
  schemaVersion = 2,
  masterProjectId = "master-1",
  referenceId = "reference-1",
  referenceRevision = 2,
  publishedAt = "2026-09-20T10:00:00Z",
  publishedBy = "Alice",
}
local pointer_two = {
  schemaVersion = 2,
  masterProjectId = "master-1",
  referenceId = "reference-1",
  latestReferenceRevision = 2,
  manifest = "history/reference-0002.json",
}
local retry_input = {
  package_root = "package",
  expected_revision = 1,
  transaction_id = "tx-2",
  snapshot = snapshot_two,
  pointer = pointer_two,
}
fail_atomic = true
assert(reference_writer.publish(retry_input, fs) == nil, "pointer failure is uncommitted")
local fresh_snapshot = {}
for key, value in pairs(snapshot_two) do fresh_snapshot[key] = value end
fresh_snapshot.publishedAt = "2026-09-20T10:01:00Z"
fresh_snapshot.publishedBy = "Bob"
local fresh_retry = {}
for key, value in pairs(retry_input) do fresh_retry[key] = value end
fresh_retry.transaction_id = "tx-2-fresh"
fresh_retry.snapshot = fresh_snapshot
local retried, retry_error = reference_writer.publish(fresh_retry, fs)
assert(retried, retry_error)
assert(json.decode(files["package/reference.json"]).latestReferenceRevision == 2, "Reference retry commits pointer")

local rejected = reference_writer.publish({
  package_root = "old-package",
  expected_revision = 0,
  transaction_id = "tx-old",
  snapshot = { schemaVersion = 1, referenceId = "old", referenceRevision = 1 },
  pointer = {
    schemaVersion = 1,
    referenceId = "old",
    latestReferenceRevision = 1,
    manifest = "history/reference-0001.json",
  },
}, fs)
assert(not rejected, "unpublished Reference schema version 1 is rejected")

return 3
