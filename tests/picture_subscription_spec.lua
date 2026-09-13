local json = require("readelivery.json")
local picture_subscription = require("readelivery.picture_subscription")

local pointer_path = "C:/mix/_Delivery/CIN_030_MIX/picture.json"
local manifest_path = "C:/mix/_Delivery/CIN_030_MIX/picture-history/picture-0003.json"
local video_path = "C:/mix/video.mov"
local pointer = {
  schemaVersion = 1,
  pictureId = "picture-1",
  latestPictureRevision = 3,
  manifest = "picture-history/picture-0003.json",
}
local snapshot = {
  schemaVersion = 1,
  pictureId = "picture-1",
  pictureRevision = 3,
  videoFile = video_path,
  videoHash = "sha256:video-hash",
  sampleRate = 48000,
  pictureStartSamples = 96000,
  sourceOffsetSamples = 0,
  durationSamples = 144000,
  playbackRate = 1,
  frameRate = { numerator = 24, denominator = 1, dropFrame = false },
  projectTimecodeOffsetSamples = 0,
}
local files = {
  [pointer_path] = json.encode(pointer),
  [manifest_path] = json.encode(snapshot),
  [video_path] = "video",
}
local fs = {}
function fs.read_file(path) return files[path] end
function fs.hash_file(path) if path == video_path then return "video-hash" end end
function fs.dirname(path) return path:match("^(.*)/[^/]+$") end
function fs.join(...) return table.concat({ ... }, "/"):gsub("/+", "/") end

local values = { project_mode = "source" }
local events = {}
local adapter = {}
function adapter.get_project_value(key) return values[key] end
function adapter.set_project_value(key, value) values[key] = tostring(value) end
function adapter.begin_undo(label) table.insert(events, "begin:" .. label) end
function adapter.end_undo(label) table.insert(events, "end:" .. label) end
function adapter.mark_project_dirty() table.insert(events, "dirty") end
function adapter.sync_picture(value)
  table.insert(events, "sync:" .. value.pictureRevision)
  return { item_ref = "picture-item", created = true }
end

local subscribed, subscribe_error = picture_subscription.subscribe(adapter, fs, pointer_path)
assert(subscribed, subscribe_error)
assert(values.picture_manifest_path == pointer_path, "stable pointer path persisted")
assert(values.picture_id == "picture-1", "Picture identity persisted")
assert(values.synchronized_picture_revision == nil, "subscription does not auto-sync")

local status, status_error = picture_subscription.check(adapter, fs)
assert(status, status_error)
assert(status.latest_revision == 3, "latest revision detected")
assert(status.synchronized_revision == 0, "not yet synchronized")
assert(status.reviewed_revision == 0, "not yet reviewed")
assert(status.available, "external video hash matches")

local synchronized, sync_error = picture_subscription.synchronize(adapter, status)
assert(synchronized, sync_error)
assert(values.synchronized_picture_revision == "3", "synchronized revision persisted")
assert(values.picture_start_samples == "96000", "Picture Start persisted")
assert(values.reviewed_picture_revision == nil, "sync does not imply review")

local reviewed, review_error = picture_subscription.mark_reviewed(adapter, status)
assert(reviewed, review_error)
assert(values.reviewed_picture_revision == "3", "review is explicit")

files[video_path] = "replaced bytes"
function fs.hash_file(path) if path == video_path then return "different-hash" end end
local mismatched = assert(picture_subscription.check(adapter, fs))
assert(not mismatched.available, "same-path replacement detected")
assert(mismatched.video_error:find("hash", 1, true), "hash mismatch explained")

return 4
