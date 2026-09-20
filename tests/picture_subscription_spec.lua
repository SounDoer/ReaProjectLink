local json = require("readelivery.json")
local picture_subscription = require("readelivery.picture_subscription")

local pointer_path = "C:/mix/_Delivery/CIN_030_MIX/picture.json"
local manifest_path = "C:/mix/_Delivery/CIN_030_MIX/picture-history/picture-0003.json"
local video_path = "C:/mix/video.mov"
local function v2_snapshot(revision, item_start, ffop_start)
  return {
    schemaVersion = 2,
    pictureId = "picture-1",
    pictureRevision = revision,
    alignmentMode = "mirror",
    timeline = {
      sampleRate = 48000,
      projectTimecodeOffsetSamples = 0,
      referenceStartSamples = ffop_start,
      referenceRole = "FFOP",
      frameRate = { numerator = 24, denominator = 1, dropFrame = false },
    },
    lanes = {{
      laneId = "picture-lane-1", displayName = "Picture", order = 0,
      items = {{
        itemId = "picture-item-1", displayName = "Picture",
        videoFile = video_path, videoHash = "sha256:video-hash",
        startSamples = item_start, sourceOffsetSamples = 0,
        durationSamples = 144000, playbackRate = 1,
      }},
    }},
    markers = {{
      entryId = "ffop-1", name = "FFOP", startSamples = ffop_start,
      color = 0, semanticRole = "FFOP",
    }},
    regions = {},
  }
end

local pointer = {
  schemaVersion = 2,
  pictureId = "picture-1",
  latestPictureRevision = 3,
  manifest = "picture-history/picture-0003.json",
}
local snapshot = v2_snapshot(3, 96000, 96000)
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

local values = { project_mode = "source", project_token = "source-project-1" }
local events = {}
local adapter = {}
function adapter.get_project_value(key) return values[key] end
function adapter.set_project_value(key, value) values[key] = tostring(value) end
function adapter.begin_undo(label) table.insert(events, "begin:" .. label) end
function adapter.end_undo(label) table.insert(events, "end:" .. label) end
function adapter.mark_project_dirty() table.insert(events, "dirty") end
function adapter.project_sample_rate() return 96000 end
function adapter.project_token() return values.project_token end
function adapter.sync_picture(value)
  table.insert(events, "sync:" .. value.pictureRevision)
  return { item_ref = "picture-item", created = true }
end
function adapter.shift_entire_project(seconds)
  table.insert(events, "shift:" .. tostring(seconds))
  return { shifted = true }
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

values.project_token = "source-project-2"
local wrong_project, wrong_project_error = picture_subscription.synchronize(adapter, status)
assert(not wrong_project and wrong_project_error:find("different REAPER project", 1, true),
  "Picture status cannot be applied to another project")
values.project_token = "source-project-1"

local synchronized, sync_error = picture_subscription.synchronize(adapter, status)
assert(synchronized, sync_error)
assert(values.synchronized_picture_revision == "3", "synchronized revision persisted")
assert(values.picture_start_samples == "192000", "Picture Start converted to the Source sample rate")
assert(values.picture_start_sample_rate == "96000", "Picture Start sample rate persisted")
assert(values.reviewed_picture_revision == nil, "sync does not imply review")

local reviewed, review_error = picture_subscription.mark_reviewed(adapter, status)
assert(reviewed, review_error)
assert(values.reviewed_picture_revision == "3", "review is explicit")

local revision_four_path =
  "C:/mix/_Delivery/CIN_030_MIX/picture-history/picture-0004.json"
local revision_four = v2_snapshot(4, 144000, 144000)
pointer.latestPictureRevision = 4
pointer.manifest = "picture-history/picture-0004.json"
files[pointer_path] = json.encode(pointer)
files[revision_four_path] = json.encode(revision_four)

snapshot.pictureId = "foreign-picture"
files[manifest_path] = json.encode(snapshot)
local foreign_history, foreign_history_error = picture_subscription.check(adapter, fs)
assert(
  not foreign_history and foreign_history_error:find("Picture history", 1, true),
  "a synchronized history snapshot from another Picture is rejected"
)
snapshot.pictureId = "picture-1"
files[manifest_path] = json.encode(snapshot)

local shifted = assert(picture_subscription.check(adapter, fs))
assert(shifted.can_shift_entire_project, "uniform Master Reference shift is detected")
assert(math.abs(shifted.shift_seconds - 1) < 0.000001, "uniform shift delta is reported")
assert(picture_subscription.synchronize(adapter, shifted, { shift_entire_project = true }))
assert(events[#events - 3] == "shift:1.0", "explicit full-project shift is applied before sync")

local function publish_test_revision(revision, value)
  local path = string.format(
    "C:/mix/_Delivery/CIN_030_MIX/picture-history/picture-%04d.json", revision
  )
  pointer.schemaVersion = 2
  pointer.latestPictureRevision = revision
  pointer.manifest = string.format("picture-history/picture-%04d.json", revision)
  files[pointer_path] = json.encode(pointer)
  files[path] = json.encode(value)
end

publish_test_revision(5, v2_snapshot(5, 144000, 144000))
local stationary = assert(picture_subscription.check(adapter, fs))
assert(not stationary.can_shift_entire_project,
  "an update without a timeline rebase does not offer a full-project shift")
assert(picture_subscription.synchronize(adapter, stationary))

publish_test_revision(6, v2_snapshot(6, 192000, 192000))
local uniform = assert(picture_subscription.check(adapter, fs))
assert(uniform.can_shift_entire_project and math.abs(uniform.shift_seconds - 1) < 0.000001,
  "all stable timeline elements moving together offers a full-project shift")
assert(picture_subscription.synchronize(adapter, uniform))

publish_test_revision(7, v2_snapshot(7, 192000, 240000))
local ffop_only = assert(picture_subscription.check(adapter, fs))
assert(not ffop_only.can_shift_entire_project,
  "moving only FFOP does not offer a full-project shift")

files[video_path] = "replaced bytes"
function fs.hash_file(path) if path == video_path then return "different-hash" end end
local mismatched = assert(picture_subscription.check(adapter, fs))
assert(not mismatched.available, "same-path replacement detected")
assert(mismatched.video_error:find("hash", 1, true), "hash mismatch explained")

return 11
