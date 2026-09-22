local json = require("reaprojectlink.json")
local delivery_publish = require("reaprojectlink.delivery_publish")

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
  project_type = "source",
  project_id = "source-1",
  reference_id = "reference-1",
  synchronized_reference_revision = "7",
  reference_start_samples = "48000",
  reference_start_sample_rate = "48000",
}
local item = {
  name = "Line A",
  clip_id = "",
  media = { path = "C:/show/bounce.wav", sample_rate = 48000, channel_count = 1 },
  presentation = {
    start_offset_samples = 288000,
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
local ids = { "delivery-1", "clip-1", "tx-1", "clip-2", "tx-2", "clip-3" }
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
function adapter.project_sample_rate() return 96000 end
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
  return { delivery_revision = input.pointer.latestDeliveryRevision }
end

local service = delivery_publish.create({ delivery_writer = writer })
local review = assert(service.review(adapter, fs, { publish_anyway = false }))

assert(review.package_root == "C:/show/_ReaProjectLink/CIN_030_DX", "managed package root")
assert(review.delivery_revision == 1, "first review revision")
assert(review.blocker_count == 0, "publishable review")

local result, publish_error = service.publish(review, adapter, fs, {
  published_at = "2026-09-13T13:00:00+08:00",
  published_by = "Alice",
})
assert(result, publish_error)
assert(project_values.project_id == "source-1", "Project identity persisted")
assert(project_values.delivery_id == "delivery-1", "Delivery identity persisted")
assert(project_values.project_identity_path == project_path, "identity path persisted")
assert(project_values.package_root == review.package_root, "stable package root persisted")
assert(item.clip_id == "clip-1", "Clip identity persisted")
assert(events[4] == "save project", "identity is saved before package Publish")
assert(events[5] == "publish package", "package Publish follows project save")
assert(captured_publish.package_root == review.package_root, "writer package root")
assert(captured_publish.expected_revision == 0, "writer reviewed base")
assert(captured_publish.snapshot.reference.reviewedRevision == 7, "reviewed Reference revision")
assert(project_values.reviewed_reference_revision == "7", "declared Reference revision persisted")
assert(captured_publish.snapshot.lanes[1].clips[1].startOffsetSamples == 192000, "Reference-relative Clip position across sample rates")
assert(captured_publish.pointer.manifest == "history/delivery-0001.json", "history pointer")

files[review.package_root .. "/delivery.json"] = json.encode(captured_publish.pointer)
files[review.package_root .. "/history/delivery-0001.json"] = json.encode(captured_publish.snapshot)
local next_review = assert(service.review(adapter, fs, {}))
assert(next_review.delivery_revision == 2, "published baseline is loaded")
assert(next_review.lanes[1].clips[1].status == "Included", "next snapshot needs no lineage decision")
project_values.synchronized_reference_revision = "8"
local declared_default = assert(service.review(adapter, fs, {}))
assert(declared_default.reviewed_reference_revision == 8,
  "declaration defaults to the Synchronized Reference Revision")
assert(declared_default.last_declared_reference_revision == 7, "previous declaration is offered")
local declared_older = assert(service.review(adapter, fs, { declared_reference_revision = 7 }))
assert(declared_older.reviewed_reference_revision == 7, "the previous revision may be declared")
local older_result, older_error = service.publish(declared_older, adapter, fs, {
  published_at = "2026-09-13T13:05:00+08:00",
  published_by = "Alice",
})
assert(older_result, older_error)
assert(captured_publish.snapshot.reference.reviewedRevision == 7,
  "the older declared revision is what publishes, not the Synchronized one")
assert(project_values.reviewed_reference_revision == "7",
  "the older declared revision persists even while Synchronized is ahead")
files[review.package_root .. "/delivery.json"] = json.encode(captured_publish.pointer)
files[review.package_root .. "/history/delivery-0002.json"] = json.encode(captured_publish.snapshot)
project_values.synchronized_reference_revision = nil
local unsynchronized = assert(service.review(adapter, fs, {}))
assert(unsynchronized.reference_blocker, "publishing requires a Synchronized Reference Revision")
assert(unsynchronized.blocker_count > 0, "an unsynchronized Reference blocks Publish")
project_values.synchronized_reference_revision = "8"

project_path = "C:/show/renamed/CIN_030_DX_New.rpp"
local unresolved_save_as = assert(service.review(adapter, fs, {}))
assert(unresolved_save_as.save_as_blocker, "Save As requires an identity choice")
assert(unresolved_save_as.blocker_count == 1, "Save As blocks Publish")

local continued = assert(service.review(adapter, fs, { save_as_decision = "continue" }))
assert(continued.package_root == review.package_root, "continuing keeps the stable package root")
assert(continued.source_project_id == "source-1", "continuing keeps Source identity")

local restarted = assert(service.review(adapter, fs, {
  save_as_decision = "new",
}))
assert(restarted.package_root == "C:/show/renamed/_ReaProjectLink/CIN_030_DX_New", "new Source uses new package root")
assert(restarted.source_project_id == nil, "new Source receives a new identity on Publish")
assert(restarted.lanes[1].clips[1].status == "Included", "new Source includes its current Items")

local package_events = 0
for _, event in ipairs(events) do if event == "publish package" then package_events = package_events + 1 end end
function adapter.save_project() return nil, "simulated save failure" end
local unsaved, unsaved_error = service.publish(continued, adapter, fs, {
  published_at = "2026-09-13T13:10:00+08:00",
  published_by = "Alice",
})
assert(not unsaved and unsaved_error == "simulated save failure", "save failure blocks audio Publish")
local package_events_after = 0
for _, event in ipairs(events) do if event == "publish package" then package_events_after = package_events_after + 1 end end
assert(package_events_after == package_events, "package writer is not called after save failure")

return 7
