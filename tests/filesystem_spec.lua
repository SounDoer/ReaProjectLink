local filesystem = require("readelivery.filesystem")
local json = require("readelivery.json")
local package_writer = require("readelivery.package_writer")
local sha256 = require("readelivery.sha256")

local source = debug.getinfo(1, "S").source:sub(2)
local tests_dir = assert(source:match("^(.*)[/\\]"))
local root = tests_dir .. "/.filesystem-fixture"
local fs = filesystem.create(reaper)

fs.remove_tree(root)
assert(fs.make_directory(root))

local first_lock = assert(fs.acquire_lock(root, {
  user = "tester",
  machine = "test-machine",
  started_at = "2026-09-13T12:00:00+08:00",
}))
local second_lock = fs.acquire_lock(root, {})
assert(second_lock == nil, "a second publisher must not acquire the lock")
assert(fs.release_lock(root, first_lock))
local third_lock = assert(fs.acquire_lock(root, {}))
assert(fs.release_lock(root, third_lock))

local stale_token = assert(fs.acquire_lock(root, {
  user = "stale-user",
  machine = "stale-machine",
  started_at = "2026-09-13T12:30:00+08:00",
}))
local lock_info = assert(fs.read_lock(root))
assert(lock_info.token == stale_token and lock_info.user == "stale-user", "lock metadata")
local wrong_removal = fs.remove_lock(root, "wrong-token")
assert(wrong_removal == nil, "lock removal requires the observed token")
assert(fs.remove_lock(root, stale_token), "explicit stale-lock removal")

local source_path = fs.join(root, "source.wav")
local copied_path = fs.join(root, "nested", "copy.wav")
assert(fs.write_file(source_path, "wave bytes"))
assert(fs.make_directory(fs.join(root, "nested")))
assert(fs.copy_file(source_path, copied_path))
assert(fs.read_file(copied_path) == "wave bytes", "copied bytes")
assert(fs.file_size(copied_path) == 10, "copied size")
assert(fs.hash_file(copied_path) == sha256.digest("wave bytes"), "copied hash")

local stable_path = fs.join(root, "delivery.json")
local temporary_path = fs.join(root, "delivery.tmp")
assert(fs.write_file(stable_path, "old"))
assert(fs.write_file(temporary_path, "new"))
assert(fs.atomic_replace(temporary_path, stable_path))
assert(fs.read_file(stable_path) == "new", "atomic replacement")
assert(not fs.exists(temporary_path), "temporary file is consumed")

local package_root = fs.join(root, "package")
local publish_result, publish_error = package_writer.publish({
  package_root = package_root,
  expected_revision = 0,
  transaction_id = "integration",
  snapshot = {
    schemaVersion = 1,
    sourceProjectId = "source-1",
    publishRevision = 1,
    lanes = json.array(),
  },
  pointer = {
    schemaVersion = 1,
    sourceProjectId = "source-1",
    latestPublishRevision = 1,
    manifest = "history/publish-0001.json",
  },
  media = {
    {
      source_path = source_path,
      destination = "media/clip-1/clip_r0001.wav",
      size = 10,
      hash = sha256.digest("wave bytes"),
    },
  },
}, fs)
assert(publish_result, publish_error)
local published_pointer = assert(fs.read_file(fs.join(package_root, "delivery.json")))
assert(json.decode(published_pointer).latestPublishRevision == 1, "real Publish pointer")
assert(
  fs.read_file(fs.join(package_root, "media", "clip-1", "clip_r0001.wav")) == "wave bytes",
  "real Publish media"
)

assert(fs.remove_tree(root))
assert(not fs.exists(root), "fixture directory is removed")

return 1
