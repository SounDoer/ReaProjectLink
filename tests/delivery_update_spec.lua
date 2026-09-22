local json = require("reaprojectlink.json")
local delivery_update = require("reaprojectlink.delivery_update")

local root = "C:/source/_ReaProjectLink/Music"
local pointer_path = root .. "/delivery.json"
local pointer = {
  schemaVersion = 1,
  sourceProjectId = "source-1",
  deliveryId = "delivery-1",
  latestDeliveryRevision = 2,
  manifest = "history/delivery-0002.json",
}
local function clip(id, name, position)
  return {
    clipId = id, displayName = name, mediaRevision = 1,
    mediaFile = "../media/" .. id .. "/" .. name .. ".wav",
    mediaHash = "sha256:hash-" .. id,
    startOffsetSamples = position, sourceOffsetSamples = 0, lengthSamples = 48000,
    itemGain = 1, fadeInSamples = 0, fadeOutSamples = 0, take = {},
  }
end
local function snapshot(revision)
  return {
    schemaVersion = 1, sourceProjectId = "source-1", deliveryId = "delivery-1",
    sourceProjectName = "Music", deliveryRevision = revision, sampleRate = 48000,
    reference = { referenceId = "reference-1", reviewedRevision = 7 },
    lanes = {
      { laneId = "lane-1", displayName = "Music A", order = 0, clips = { clip("r" .. revision .. "-a", "A", 0) } },
      { laneId = "lane-2", displayName = "Music B", order = 1, clips = { clip("r" .. revision .. "-b", "B", 48000) } },
    },
  }
end
local latest, previous = snapshot(2), snapshot(1)
local files = {
  [pointer_path] = json.encode(pointer),
  [root .. "/history/delivery-0001.json"] = json.encode(previous),
  [root .. "/history/delivery-0002.json"] = json.encode(latest),
}
for _, snap in ipairs({ previous, latest }) do
  for _, lane in ipairs(snap.lanes) do
    for _, value in ipairs(lane.clips) do
      files[root .. "/media/" .. value.clipId .. "/" .. value.displayName .. ".wav"] = "media-" .. value.clipId
    end
  end
end
local fs = {}
function fs.read_file(path) return files[path] end
function fs.hash_file(path)
  local id = path:match("/media/([^/]+)/")
  return id and "hash-" .. id or nil
end
function fs.join(...) return table.concat({ ... }, "/"):gsub("/+", "/") end

local subscriptions = {{
  pointerPath = pointer_path, sourceProjectId = "source-1", deliveryId = "delivery-1",
  acceptedDeliveryRevision = 1,
  lanes = {
    { laneId = "lane-1", trackGuid = "track-1" },
    { laneId = "lane-2", unmapped = true },
  },
}}
local values = {
  reference_id = "reference-1", reference_revision = "7",
  reference_start_samples = "96000", reference_start_sample_rate = "48000",
  delivery_subscriptions = json.encode(subscriptions),
}
local item_one, item_two = {}, {}
local instance_state = { position_seconds = 0, length_seconds = 1 }
local instances = {
  { item_ref = item_one, track_ref = { guid = "track-9", name = "Local" }, lane_id = "lane-1", state = instance_state },
  { item_ref = item_two, track_ref = { guid = "track-1", name = "Music A" }, lane_id = "lane-1", state = instance_state },
}
local events = {}
local stale = false
local adapter = {}
function adapter.get_project_value(key) return values[key] end
function adapter.set_project_value(key, value) values[key] = value end
function adapter.project_sample_rate() return 48000 end
function adapter.all_tracks() return { { guid = "track-1", name = "Music A" }, { guid = "track-2", name = "Music B" } } end
function adapter.track_guid(track) return track.guid end
function adapter.track_name(track) return track.name end
function adapter.track_by_guid(guid) if guid == "track-1" or guid == "track-2" then return { guid = guid, name = guid } end end
function adapter.delivery_instances() return instances end
function adapter.valid_item() return true end
function adapter.delivery_instance_state(item)
  if stale and item == item_one then return { position_seconds = 1, length_seconds = 1 } end
  return instance_state
end
function adapter.begin_undo() table.insert(events, "begin") end
function adapter.end_undo() table.insert(events, "end") end
function adapter.cancel_undo() table.insert(events, "cancel") end
function adapter.mark_project_dirty() table.insert(events, "dirty") end
function adapter.delete_linked_item(item) table.insert(events, { "delete", item }); return true end
function adapter.detach_instance(item) table.insert(events, { "detach", item }); return true end
function adapter.new_id() return "instance-new" end
function adapter.create_master_track(name) return { guid = "created-" .. name, name = name } end
function adapter.create_delivery_item(track, value, context)
  table.insert(events, { "create", track, value, context })
  return { track = track, clip = value, context = context }
end
function adapter.is_linked_item(item) return item == item_one end

local review, review_error = delivery_update.review(adapter, fs, "source-1")
assert(review, review_error)
assert(review.target_revision == 2 and review.latest_revision == 2, "latest Delivery Revision selected")
assert(review.replacement_count == 2, "all managed Items will be replaced")
assert(review.source_item_count == 2, "complete Source snapshot counted")
assert(#review.additions == 1 and review.additions[1].clip.clipId == "r2-a", "mapped Lane is ready to import")
assert(#review.unmapped_lanes == 1 and review.unmapped_lanes[1].lane_id == "lane-2", "unmapped Lane still needs routing")
assert(review.unmapped_lanes[1].skipped == true, "a Lane the user chose not to import is reported as skipped")

stale = true
local stale_result, stale_error = delivery_update.apply(review, adapter, {
  lane_mappings = { ["lane-2"] = { kind = "unmapped" } },
})
assert(not stale_result and stale_error:find("changed after Update Review", 1, true), "review protects against intervening edits")
stale = false

local result, apply_error = delivery_update.apply(review, adapter, {
  lane_mappings = { ["lane-2"] = { kind = "existing", track_ref = { guid = "track-2" } } },
})
assert(result, apply_error)
assert(result.deleted_items == 2 and result.new_items == 2, "snapshot replaces all managed Items")
assert(events[1] == "begin" and events[#events] == "end", "synchronization is one Undo step")
assert(json.decode(values.delivery_subscriptions)[1].acceptedDeliveryRevision == 2, "handled Delivery Revision advances")

-- The currently handled revision can be synchronized again to restore its
-- Source-owned Items after a detach or accidental deletion.
instances = {}
events = {}
local resync = assert(delivery_update.review(adapter, fs, "source-1", 2))
assert(resync.pending_count == 2, "current revision remains resynchronizable")
local restored = assert(delivery_update.apply(resync, adapter, {
  lane_mappings = {},
}))
assert(restored.new_items == 2, "resynchronization restores the complete snapshot")

instances = {
  { item_ref = item_one, track_ref = { guid = "track-9" }, lane_id = "lane-1", state = instance_state },
  { item_ref = item_two, track_ref = { guid = "track-1" }, lane_id = "lane-1", state = instance_state },
}
local moved = delivery_update.moved_instances(adapter)
assert(#moved == 1 and moved[1].item_ref == item_one, "Item outside its Delivery Track is detected")
events = {}
local detached = assert(delivery_update.detach_many(adapter, moved))
assert(detached.detached == 1 and events[2][1] == "detach", "confirmed moved Item becomes local")

local older = assert(delivery_update.review(adapter, fs, "source-1", 1))
assert(older.target_revision == 1 and older.source_item_count == 2, "historical snapshot can be synchronized")
local unpublished, revision_error = delivery_update.review(adapter, fs, "source-1", 3)
assert(not unpublished and revision_error == "Requested Delivery revision was never published.", "unpublished revision is rejected")

return 7
