local json = require("readelivery.json")
local package_writer = require("readelivery.package_writer")
local sha256 = require("readelivery.sha256")

local function memory_filesystem(initial, options)
  local files = initial or {}
  options = options or {}
  local locked = false
  local fs = {}

  function fs.join(...)
    return table.concat({ ... }, "/"):gsub("/+", "/")
  end

  function fs.acquire_lock()
    if locked then return nil, "locked" end
    locked = true
    return "lock-token"
  end

  function fs.release_lock()
    locked = false
  end

  function fs.make_directory() return true end
  function fs.remove_tree(prefix)
    for path in pairs(files) do
      if path:sub(1, #prefix) == prefix then files[path] = nil end
    end
    return true
  end
  function fs.exists(path) return files[path] ~= nil end
  function fs.read_file(path) return files[path] end
  function fs.write_file(path, bytes)
    if options.corrupt_snapshot and path:match("publish%-%d+%.json$") then
      files[path] = "{broken"
    else
      files[path] = bytes
    end
    return true
  end
  function fs.copy_file(source, destination)
    if not files[source] then return nil, "missing source" end
    files[destination] = files[source]
    return true
  end
  function fs.file_size(path) return files[path] and #files[path] or nil end
  function fs.hash_file(path) return files[path] and sha256.digest(files[path]) or nil end
  function fs.move_file(source, destination)
    if not files[source] then return nil, "missing staged file" end
    files[destination] = files[source]
    files[source] = nil
    return true
  end
  function fs.atomic_replace(source, destination)
    return fs.move_file(source, destination)
  end
  function fs.is_locked() return locked end
  function fs.files() return files end
  return fs
end

local wav = "wave bytes"
local digest = sha256.digest(wav)
local fs = memory_filesystem({ ["source.wav"] = wav })
local snapshot = {
  schemaVersion = 1,
  sourceProjectId = "source-1",
  publishRevision = 1,
  lanes = json.array(),
}
local pointer = {
  schemaVersion = 1,
  sourceProjectId = "source-1",
  latestPublishRevision = 1,
  manifest = "history/publish-0001.json",
}

local result, err = package_writer.publish({
  package_root = "package",
  expected_revision = 0,
  transaction_id = "tx-1",
  snapshot = snapshot,
  pointer = pointer,
  media = {
    {
      source_path = "source.wav",
      destination = "media/clip-1/clip_r0001.wav",
      size = #wav,
      hash = digest,
    },
  },
}, fs)

assert(result, err)
assert(not fs.is_locked(), "Publish lock must be released")
assert(
  fs.read_file("package/media/clip-1/clip_r0001.wav") == wav,
  "managed WAV must be visible"
)
assert(
  json.decode(fs.read_file("package/history/publish-0001.json")).publishRevision == 1,
  "immutable snapshot must be visible"
)
assert(
  json.decode(fs.read_file("package/delivery.json")).latestPublishRevision == 1,
  "stable pointer must expose the revision"
)

local broken_fs = memory_filesystem({ ["source.wav"] = wav }, {
  corrupt_snapshot = true,
})
local failed = package_writer.publish({
  package_root = "broken-package",
  expected_revision = 0,
  transaction_id = "tx-broken",
  snapshot = snapshot,
  pointer = pointer,
  media = {},
}, broken_fs)

assert(failed == nil, "corrupt staged snapshot must fail Publish")
assert(not broken_fs.is_locked(), "failed Publish must release its lock")
assert(
  broken_fs.read_file("broken-package/delivery.json") == nil,
  "failed Publish must not expose a stable pointer"
)

return 2
