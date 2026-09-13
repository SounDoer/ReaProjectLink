local json = require("readelivery.json")
local source_publish = require("readelivery.source_publish")

local files = { ["C:/show/bounce.wav"] = "audio bytes" }
local fs = {}
function fs.join(...)
  return table.concat({ ... }, "/"):gsub("/+", "/")
end
function fs.exists(path) return files[path] ~= nil end
function fs.read_file(path) return files[path] end
function fs.file_size(path) return files[path] and #files[path] end
function fs.hash_file(path)
  if files[path] == "audio bytes" then
    return "8f677e9b5b600370ee32c86d5239946509a4555e58951289cf21ad4aa1fd8ccf"
  end
end

local project_values = {
  project_mode = "source",
  picture_id = "picture-1",
  reviewed_picture_revision = "7",
  picture_start_samples = "96000",
}
local item = {
  name = "Line A",
  clip_id = "",
  media = { path = "C:/show/bounce.wav", sample_rate = 48000, channel_count = 1 },
  presentation = {
    start_offset_samples = 144000,
    source_offset_samples = 0,
    length_samples = 48000,
    item_gain = 1,
    fade_in_samples = 0,
    fade_out_samples = 0,
    take = {},
  },
}
local track = { name = "DX", lane_id = "lane-1", items = { item } }
local events = {}
local project_path = "C:/show/CIN_030_DX.rpp"
local ids = { "source-1", "set-1", "clip-1", "tx-1" }
local id_index = 0
local adapter = {}
function adapter.project_path() return project_path end
function adapter.get_project_value(key) return project_values[key] end
function adapter.set_project_value(key, value) project_values[key] = tostring(value) end
function adapter.all_tracks() return { track } end
function adapter.get_track_lane_id(value) return value.lane_id end
function adapter.track_name(value) return value.name end
function adapter.track_fx_count() return 0 end
function adapter.track_items(value) return value.items end
function adapter.get_item_clip_id(value) return value.clip_id end
function adapter.set_item_clip_id(value, clip_id) value.clip_id = clip_id end
function adapter.item_display_name(value) return value.name end
function adapter.active_take_media(value) return value.media end
function adapter.item_presentation(value) return value.presentation end
function adapter.project_sample_rate() return 48000 end
function adapter.file_exists(path) return files[path] ~= nil end
function adapter.new_id()
  id_index = id_index + 1
  return ids[id_index]
end
function adapter.begin_undo() table.insert(events, "begin identity") end
function adapter.end_undo() table.insert(events, "end identity") end
function adapter.mark_project_dirty() table.insert(events, "dirty") end
function adapter.save_project() table.insert(events, "save project"); return true end

local captured_publish
local writer = {}
function writer.publish(input)
  table.insert(events, "publish package")
  captured_publish = input
  return { publish_revision = input.pointer.latestPublishRevision }
end

local service = source_publish.create({ package_writer = writer })
local review = assert(service.review(adapter, fs, {
  identity_decisions = { [item] = { kind = "new" } },
  publish_anyway = false,
}))

assert(review.package_root == "C:/show/_Delivery/CIN_030_DX", "managed package root")
assert(review.publish_revision == 1, "first review revision")
assert(review.blocker_count == 0, "publishable review")

local result, publish_error = service.publish(review, adapter, fs, {
  published_at = "2026-09-13T13:00:00+08:00",
  published_by = "Alice",
})
assert(result, publish_error)
assert(project_values.source_project_id == "source-1", "Source identity persisted")
assert(project_values.delivery_set_id == "set-1", "Delivery Set identity persisted")
assert(project_values.source_identity_project_path == project_path, "identity path persisted")
assert(project_values.source_package_root == review.package_root, "stable package root persisted")
assert(item.clip_id == "clip-1", "Clip identity persisted")
assert(events[4] == "save project", "identity is saved before package Publish")
assert(events[5] == "publish package", "package Publish follows project save")
assert(captured_publish.package_root == review.package_root, "writer package root")
assert(captured_publish.expected_revision == 0, "writer reviewed base")
assert(captured_publish.snapshot.picture.reviewedRevision == 7, "reviewed Picture revision")
assert(captured_publish.snapshot.lanes[1].clips[1].startOffsetSamples == 48000, "Picture-relative Clip position")
assert(captured_publish.pointer.manifest == "history/publish-0001.json", "history pointer")

files[review.package_root .. "/delivery.json"] = json.encode(captured_publish.pointer)
files[review.package_root .. "/history/publish-0001.json"] = json.encode(captured_publish.snapshot)
local next_review = assert(service.review(adapter, fs, {}))
assert(next_review.publish_revision == 2, "published baseline is loaded")
assert(next_review.lanes[1].clips[1].status == "Unchanged", "baseline comparison")

project_path = "C:/show/renamed/CIN_030_DX_New.rpp"
local unresolved_save_as = assert(service.review(adapter, fs, {}))
assert(unresolved_save_as.save_as_blocker, "Save As requires an identity choice")
assert(unresolved_save_as.blocker_count == 1, "Save As blocks Publish")

local continued = assert(service.review(adapter, fs, { save_as_decision = "continue" }))
assert(continued.package_root == review.package_root, "continuing keeps the stable package root")
assert(continued.source_project_id == "source-1", "continuing keeps Source identity")

local restarted = assert(service.review(adapter, fs, {
  save_as_decision = "new",
  identity_decisions = { [item] = { kind = "new" } },
}))
assert(restarted.package_root == "C:/show/renamed/_Delivery/CIN_030_DX_New", "new Source uses new package root")
assert(restarted.source_project_id == nil, "new Source receives a new identity on Publish")
assert(restarted.lanes[1].clips[1].status == "Added", "new Source resets Clip identity")

return 5
