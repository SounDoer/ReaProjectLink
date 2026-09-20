local json = require("readelivery.json")
local picture_publish = require("readelivery.picture_publish")

local project_values = {
  project_mode = "mix",
  picture_timeline_entries = json.encode({
    { guid = "marker-guid", entryId = "marker-1", kind = "marker", semanticRole = "FFOP" },
  }),
}
local item = { picture_id = "", picture_item_id = "", path = "C:/show/picture.mov" }
local track = { picture_lane_id = "lane-1", name = "Picture Main", items = { item } }
local events = {}
local project_change_count = 1
local ids = { "picture-1", "picture-item-1", "tx-1" }
local id_index = 0
local adapter = {}
function adapter.project_path() return "C:/show/CIN_030_MIX.rpp" end
function adapter.project_token() return "mix-project-1" end
function adapter.project_change_count() return project_change_count end
function adapter.get_project_value(key) return project_values[key] end
function adapter.set_project_value(key, value) project_values[key] = tostring(value) end
function adapter.all_tracks() return { track } end
function adapter.selected_tracks() return { track } end
function adapter.track_items(value) return value.items end
function adapter.track_name(value) return value.name end
function adapter.get_track_picture_lane_id(value) return value.picture_lane_id end
function adapter.set_track_picture_lane_id(value, id) value.picture_lane_id = id end
function adapter.set_track_picture_set_id(value, id) value.picture_set_id = id end
function adapter.get_item_picture_id(value) return value.picture_id end
function adapter.set_item_picture_id(value, id) value.picture_id = id end
function adapter.get_item_picture_item_id(value) return value.picture_item_id end
function adapter.set_item_picture_item_id(value, id) value.picture_item_id = id end
function adapter.item_display_name() return "Main Picture" end
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
function adapter.timeline_state()
  return {
    sample_rate = 48000,
    project_timecode_offset_samples = 3600000,
    frame_rate = { numerator = 24000, denominator = 1001, drop_frame = false },
  }
end
function adapter.timeline_entries()
  return {
    {
      guid = "marker-guid", kind = "marker", selected = true,
      name = "FFOP", start_samples = 96000, end_samples = 96000, color = 0,
    },
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
assert(review.lanes[1].items[1].videoHash == "sha256:video-hash", "video is hashed on review")
assert(review.reference_start_samples == 96000, "FFOP is the Reference Start")

project_change_count = 2
local stale, stale_error = service.publish(review, adapter, fs, {})
assert(not stale and stale_error:find("stale", 1, true),
  "Master Reference Publish rejects a stale Review")
project_change_count = 1

local result, err = service.publish(review, adapter, fs, {
  published_at = "2026-09-13T14:30:00+08:00",
  published_by = "Alice",
})
assert(result, err)
assert(item.picture_id == "picture-1", "Picture identity attached to Item")
assert(item.picture_item_id == "picture-item-1", "stable Picture Item identity attached")
assert(track.picture_set_id == "picture-1", "Picture identity attached to Track")
assert(project_values.picture_id == "picture-1", "Picture identity attached to project")
assert(project_values.picture_start_samples == "96000", "Mix Picture Start persisted")
assert(project_values.picture_start_sample_rate == "48000", "Mix Picture Start sample rate persisted")
local save_index, publish_index
for index, event in ipairs(events) do
  if event == "save" and not save_index then save_index = index end
  if event == "publish" and not publish_index then publish_index = index end
end
assert(save_index and publish_index and save_index < publish_index, "identity saved before Picture Publish")
assert(captured.snapshot.lanes[1].items[1].videoFile == item.path, "original video is referenced")
assert(captured.snapshot.lanes[1].items[1].videoHash == "sha256:video-hash", "published video hash")
assert(captured.snapshot.timeline.referenceStartSamples == 96000, "Reference Start")

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
local rejected = assert(service.review(adapter, fs))
assert(rejected.blocker_count > 0, "audio Item cannot become Picture")

return 5
