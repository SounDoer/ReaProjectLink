local json = require("readelivery.json")
local picture_publish = require("readelivery.picture_publish")

local project_values = { project_mode = "mix" }
local item = { picture_id = "", path = "C:/show/picture.mov" }
local events = {}
local ids = { "picture-1", "tx-1" }
local id_index = 0
local adapter = {}
function adapter.project_path() return "C:/show/CIN_030_MIX.rpp" end
function adapter.get_project_value(key) return project_values[key] end
function adapter.set_project_value(key, value) project_values[key] = tostring(value) end
function adapter.selected_items() return { item } end
function adapter.get_item_picture_id(value) return value.picture_id end
function adapter.set_item_picture_id(value, id) value.picture_id = id end
function adapter.picture_item_state(value)
  return {
    video_file = value.path,
    sample_rate = 48000,
    picture_start_samples = 96000,
    source_offset_samples = 0,
    duration_samples = 144000,
    playback_rate = 1,
    frame_rate = { numerator = 24000, denominator = 1001, drop_frame = false },
    project_timecode_offset_samples = 3600000,
  }
end
function adapter.new_id() id_index = id_index + 1; return ids[id_index] end
function adapter.begin_undo() table.insert(events, "begin") end
function adapter.end_undo() table.insert(events, "end") end
function adapter.mark_project_dirty() table.insert(events, "dirty") end
function adapter.save_project() table.insert(events, "save"); return true end

local published_files = {}
local fs = {}
function fs.join(...) return table.concat({ ... }, "/"):gsub("/+", "/") end
function fs.exists(path) return path == item.path or published_files[path] ~= nil end
function fs.read_file(path) return published_files[path] end
function fs.hash_file(path) if path == item.path then return "video-hash" end end

local captured
local writer = {}
function writer.publish(input)
  table.insert(events, "publish")
  captured = input
  return { picture_revision = input.pointer.latestPictureRevision }
end

local service = picture_publish.create({ picture_writer = writer })
local review = assert(service.review(adapter, fs))
assert(review.package_root == "C:/show/_Delivery/CIN_030_MIX", "Picture package root")
assert(review.picture_revision == 1, "first Picture revision")
assert(review.video_hash == "video-hash", "video is hashed on review")

local result, err = service.publish(review, adapter, fs, {
  published_at = "2026-09-13T14:30:00+08:00",
  published_by = "Alice",
})
assert(result, err)
assert(item.picture_id == "picture-1", "Picture identity attached to Item")
assert(project_values.picture_id == "picture-1", "Picture identity attached to project")
assert(project_values.picture_start_samples == "96000", "Mix Picture Start persisted")
assert(project_values.picture_start_sample_rate == "48000", "Mix Picture Start sample rate persisted")
assert(events[4] == "save", "identity saved before Picture Publish")
assert(events[5] == "publish", "Picture package follows project save")
assert(captured.snapshot.videoFile == item.path, "original video is referenced")
assert(captured.snapshot.videoHash == "sha256:video-hash", "published video hash")
assert(captured.snapshot.pictureStartSamples == 96000, "Picture Start")

published_files[fs.join(review.package_root, "picture.json")] = json.encode(captured.pointer)
published_files[fs.join(review.package_root, captured.pointer.manifest)] =
  json.encode(captured.snapshot)

local unchanged = assert(service.review(adapter, fs))
assert(unchanged.picture_revision == 2, "next Picture revision")
assert(unchanged.unchanged, "an identical Picture is detected")
assert(unchanged.unchanged_blocker, "an identical Picture blocks Publish by default")
local refused, refused_error = service.publish(unchanged, adapter, fs, {})
assert(not refused and refused_error == unchanged.unchanged_blocker, "unchanged Publish is refused")

local overridden = assert(service.review(adapter, fs, { publish_anyway = true }))
assert(overridden.unchanged, "Publish Anyway still reports the Picture as unchanged")
assert(not overridden.unchanged_blocker, "Publish Anyway clears the blocker")

local publish_events = 0
for _, event in ipairs(events) do if event == "publish" then publish_events = publish_events + 1 end end
function adapter.save_project() return nil, "simulated save failure" end
local unsaved, unsaved_error = service.publish(overridden, adapter, fs, {})
assert(not unsaved and unsaved_error == "simulated save failure", "save failure blocks Picture Publish")
local publish_events_after = 0
for _, event in ipairs(events) do if event == "publish" then publish_events_after = publish_events_after + 1 end end
assert(publish_events_after == publish_events, "Picture writer is not called after save failure")

item.path = "C:/show/not-picture.wav"
local rejected, rejected_error = service.review(adapter, fs)
assert(not rejected and rejected_error:find("video", 1, true), "audio Item cannot become Picture")

return 4
