local json = require("reaprojectlink.json")
local reference_publish = require("reaprojectlink.reference_publish")

local project_values = {
  project_type = "master",
  project_id = "master-1",
  reference_timeline_entries = json.encode({
    { guid = "marker-guid", entryId = "marker-1", kind = "marker", referenceStart = true },
  }),
}
local item = { reference_id = "", reference_item_id = "", path = "C:/show/reference.mov" }
local track = { reference_lane_id = "lane-1", name = "Reference Main", items = { item } }
local events = {}
local project_change_count = 1
local ids = { "reference-1", "reference-item-1", "tx-1" }
local id_index = 0
local adapter = {}
function adapter.project_path() return "C:/show/CIN_030_MIX.rpp" end
function adapter.project_token() return "master-project-1" end
function adapter.project_change_count() return project_change_count end
function adapter.get_project_value(key) return project_values[key] end
function adapter.set_project_value(key, value) project_values[key] = tostring(value) end
function adapter.all_tracks() return { track } end
function adapter.selected_tracks() return { track } end
function adapter.track_items(value) return value.items end
function adapter.track_name(value) return value.name end
function adapter.get_track_reference_lane_id(value) return value.reference_lane_id end
function adapter.set_track_reference_lane_id(value, id) value.reference_lane_id = id end
function adapter.set_track_reference_id(value, id) value.reference_id = id end
function adapter.get_item_reference_id(value) return value.reference_id end
function adapter.set_item_reference_id(value, id) value.reference_id = id end
function adapter.get_item_reference_item_id(value) return value.reference_item_id end
function adapter.set_item_reference_item_id(value, id) value.reference_item_id = id end
function adapter.item_display_name() return "Main Reference" end
function adapter.reference_item_state(value)
  return {
    video_file = value.path,
    sample_rate = 48000,
    reference_start_samples = 96000,
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
  return { reference_revision = input.pointer.latestReferenceRevision }
end

local service = reference_publish.create({ reference_writer = writer })
local review = assert(service.review(adapter, fs))
assert(review.package_root == "C:/show/_ReaProjectLink/CIN_030_MIX", "Reference package root")
assert(review.reference_revision == 1, "first Reference revision")
assert(review.lanes[1].items[1].videoHash == "sha256:video-hash", "video is hashed on review")
assert(review.reference_start_samples == 96000, "assigned Marker is the Reference Start")
assert(review.reference_start_marker_id == "marker-1", "Reference Start Marker identity")

project_change_count = 2
local stale, stale_error = service.publish(review, adapter, fs, {})
assert(not stale and stale_error:find("Out of Date", 1, true),
  "Reference Publish rejects an out-of-date Review")
project_change_count = 1

local result, err = service.publish(review, adapter, fs, {
  published_at = "2026-09-13T14:30:00+08:00",
  published_by = "Alice",
})
assert(result, err)
assert(item.reference_id == "reference-1", "Reference identity attached to Item")
assert(item.reference_item_id == "reference-item-1", "stable Reference Item identity attached")
assert(track.reference_id == "reference-1", "Reference identity attached to Track")
assert(project_values.reference_id == "reference-1", "Reference identity attached to project")
assert(project_values.reference_start_samples == "96000", "Reference Start persisted")
assert(project_values.reference_start_sample_rate == "48000", "Reference Start sample rate persisted")
assert(captured.snapshot.masterProjectId == "master-1", "Master Project identity published")
local save_index, publish_index
for index, event in ipairs(events) do
  if event == "save" and not save_index then save_index = index end
  if event == "publish" and not publish_index then publish_index = index end
end
assert(save_index and publish_index and save_index < publish_index, "identity saved before Reference Publish")
assert(captured.snapshot.lanes[1].items[1].videoFile == item.path, "original video is referenced")
assert(captured.snapshot.lanes[1].items[1].videoHash == "sha256:video-hash", "published video hash")
assert(captured.snapshot.timeline.referenceStartSamples == 96000, "Reference Start")

published_files[fs.join(review.package_root, "reference.json")] = json.encode(captured.pointer)
published_files[fs.join(review.package_root, captured.pointer.manifest)] =
  json.encode(captured.snapshot)

local unchanged = assert(service.review(adapter, fs))
assert(unchanged.reference_revision == 2, "next Reference revision")
assert(unchanged.unchanged, "an identical Reference is detected")
assert(unchanged.unchanged_blocker, "an identical Reference blocks Publish by default")
local refused, refused_error = service.publish(unchanged, adapter, fs, {})
assert(not refused and refused_error == unchanged.unchanged_blocker, "unchanged Publish is refused")

local overridden = assert(service.review(adapter, fs, { publish_anyway = true }))
assert(overridden.unchanged, "Publish Anyway still reports the Reference as unchanged")
assert(not overridden.unchanged_blocker, "Publish Anyway clears the blocker")

local publish_events = 0
for _, event in ipairs(events) do if event == "publish" then publish_events = publish_events + 1 end end
function adapter.save_project() return nil, "simulated save failure" end
local unsaved, unsaved_error = service.publish(overridden, adapter, fs, {})
assert(not unsaved and unsaved_error == "simulated save failure", "save failure blocks Reference Publish")
local publish_events_after = 0
for _, event in ipairs(events) do if event == "publish" then publish_events_after = publish_events_after + 1 end end
assert(publish_events_after == publish_events, "Reference writer is not called after save failure")

item.path = "C:/show/not-reference.wav"
local rejected = assert(service.review(adapter, fs))
assert(rejected.blocker_count > 0, "audio Item cannot become Reference")

-- Kind-specific Marker/Region register and unregister -------------------------

local function kind_fixture()
  local values = { project_type = "master", reference_timeline_entries = "[]" }
  local entries = {
    { guid = "marker-a", kind = "marker", selected = true, name = "M" },
    { guid = "region-a", kind = "region", selected = true, name = "R" },
  }
  local kind_adapter = {}
  local kind_ids = { "id-1", "id-2", "id-3", "id-4" }
  local kind_id_index = 0
  function kind_adapter.get_project_value(key) return values[key] end
  function kind_adapter.set_project_value(key, value) values[key] = tostring(value) end
  function kind_adapter.mark_project_dirty() end
  function kind_adapter.timeline_entries() return entries end
  function kind_adapter.new_id() kind_id_index = kind_id_index + 1; return kind_ids[kind_id_index] end
  return kind_adapter, entries, values
end

do
  local kind_adapter, entries = kind_fixture()
  local marker_result, marker_err = service.register_selected_markers(kind_adapter)
  assert(marker_result, marker_err)
  assert(marker_result.added == 1, "registers only the selected Marker")
  local stored = json.decode(kind_adapter.get_project_value("reference_timeline_entries"))
  assert(#stored == 1 and stored[1].guid == "marker-a" and stored[1].kind == "marker",
    "registering Markers does not touch selected Regions")

  local region_result, region_err = service.register_selected_regions(kind_adapter)
  assert(region_result, region_err)
  assert(region_result.added == 1, "registers only the selected Region")
  stored = json.decode(kind_adapter.get_project_value("reference_timeline_entries"))
  assert(#stored == 2, "Region registration adds alongside the existing Marker")

  local no_marker, no_marker_err = service.register_selected_markers(kind_adapter)
  assert(not no_marker and no_marker_err == "Select at least one unregistered Marker.",
    "register Markers error is Marker-specific")
  local no_region, no_region_err = service.register_selected_regions(kind_adapter)
  assert(not no_region and no_region_err == "Select at least one unregistered Region.",
    "register Regions error is Region-specific")

  entries[1].selected, entries[2].selected = true, false
  local unregister_marker, unregister_marker_err = service.unregister_selected_markers(kind_adapter)
  assert(unregister_marker, unregister_marker_err)
  assert(unregister_marker.removed == 1, "unregisters only the selected Marker")
  stored = json.decode(kind_adapter.get_project_value("reference_timeline_entries"))
  assert(#stored == 1 and stored[1].kind == "region",
    "unregistering Markers does not touch registered Regions")

  entries[1].selected, entries[2].selected = false, true
  local unregister_region, unregister_region_err = service.unregister_selected_regions(kind_adapter)
  assert(unregister_region, unregister_region_err)
  assert(unregister_region.removed == 1, "unregisters only the selected Region")

  local no_unregister_marker, no_unregister_marker_err = service.unregister_selected_markers(kind_adapter)
  assert(not no_unregister_marker and
    no_unregister_marker_err == "Select at least one registered Marker.",
    "unregister Markers error is Marker-specific")
  local no_unregister_region, no_unregister_region_err = service.unregister_selected_regions(kind_adapter)
  assert(not no_unregister_region and
    no_unregister_region_err == "Select at least one registered Region.",
    "unregister Regions error is Region-specific")
end

-- Combined selection register/unregister (single card actions) ----------------

local function selection_fixture()
  local values = {
    project_type = "master",
    reference_timeline_entries = json.encode({
      { guid = "region-a", entryId = "region-1", kind = "region" },
      { guid = "marker-registered", entryId = "marker-x", kind = "marker" },
    }),
  }
  local registered_track = { reference_lane_id = "lane-existing" }
  local unregistered_track = { reference_lane_id = "" }
  local entries = {
    { guid = "marker-a", kind = "marker", selected = true, name = "M" },
    { guid = "region-a", kind = "region", selected = true, name = "R" },
    { guid = "marker-registered", kind = "marker", selected = false, name = "M2" },
  }
  local selected_tracks = { registered_track, unregistered_track }
  local sel_ids = { "id-1", "id-2", "id-3", "id-4" }
  local sel_id_index = 0
  local sel_adapter = {}
  function sel_adapter.get_project_value(key) return values[key] end
  function sel_adapter.set_project_value(key, value) values[key] = tostring(value) end
  function sel_adapter.mark_project_dirty() end
  function sel_adapter.begin_undo() end
  function sel_adapter.end_undo() end
  function sel_adapter.timeline_entries() return entries end
  function sel_adapter.selected_tracks() return selected_tracks end
  function sel_adapter.get_track_reference_lane_id(track) return track.reference_lane_id end
  function sel_adapter.set_track_reference_lane_id(track, id) track.reference_lane_id = id end
  function sel_adapter.new_id() sel_id_index = sel_id_index + 1; return sel_ids[sel_id_index] end
  return sel_adapter, registered_track, unregistered_track, entries
end

do
  local sel_adapter = selection_fixture()
  local counts, counts_err = service.selection_counts(sel_adapter)
  assert(counts, counts_err)
  assert(counts.tracks.selected == 2 and counts.tracks.registered == 1, "track selection counts")
  assert(counts.markers.selected == 1 and counts.markers.registered == 0, "marker selection counts")
  assert(counts.regions.selected == 1 and counts.regions.registered == 1, "region selection counts")
end

do
  local sel_adapter, registered_track, unregistered_track = selection_fixture()
  local result, err = service.register_selected(sel_adapter)
  assert(result, err)
  assert(result.tracks == 1 and result.markers == 1 and result.regions == 0 and result.total == 2,
    "register_selected registers only the unregistered selection")
  assert(unregistered_track.reference_lane_id ~= "", "unregistered Track gains a lane id")
  assert(registered_track.reference_lane_id == "lane-existing", "already-registered Track untouched")
  local stored = json.decode(sel_adapter.get_project_value("reference_timeline_entries"))
  assert(#stored == 3, "already-registered Region is not duplicated; unregistered Marker is added")
end

do
  -- Nothing selected at all.
  local sel_adapter, _, _, entries = selection_fixture()
  function sel_adapter.selected_tracks() return {} end
  entries[1].selected, entries[2].selected = false, false
  local result, err = service.register_selected(sel_adapter)
  assert(not result and err == "Select Tracks, Markers, or Regions in REAPER first.",
    "register_selected requires a selection")
end

do
  -- Something selected, but it is all already registered.
  local sel_adapter, registered_track, _, entries = selection_fixture()
  function sel_adapter.selected_tracks() return { registered_track } end
  entries[1].selected, entries[2].selected, entries[3].selected = false, true, false
  local result, err = service.register_selected(sel_adapter)
  assert(not result and err == "The selected Tracks, Markers, and Regions are already registered.",
    "register_selected refuses an all-registered selection")
end

do
  local sel_adapter, registered_track, unregistered_track = selection_fixture()
  local result, err = service.unregister_selected(sel_adapter)
  assert(result, err)
  assert(result.tracks == 1 and result.markers == 0 and result.regions == 1 and result.total == 2,
    "unregister_selected removes only the selected-and-registered selection")
  assert(registered_track.reference_lane_id == "", "registered+selected Track is unregistered")
  assert(unregistered_track.reference_lane_id == "", "never-registered Track untouched")
  local stored = json.decode(sel_adapter.get_project_value("reference_timeline_entries"))
  assert(#stored == 1 and stored[1].guid == "marker-registered",
    "selected+registered Region is removed; unselected registered Marker is kept")
end

do
  local sel_adapter, _, unregistered_track, entries = selection_fixture()
  function sel_adapter.selected_tracks() return { unregistered_track } end
  entries[1].selected, entries[2].selected, entries[3].selected = false, false, false
  local result, err = service.unregister_selected(sel_adapter)
  assert(not result and err == "Select registered Tracks, Markers, or Regions in REAPER first.",
    "unregister_selected requires a registered selection")
end

-- Removed-content detection at Publish Review (D089) --------------------------

local function removed_fixture()
  local project_path = "C:/show2/CIN_099_MIX.rpp"
  local values = { project_type = "master", reference_timeline_entries = "[]" }
  local reference_item = { reference_id = "", reference_item_id = "", path = "C:/show2/ref.mov" }
  local reference_track = { reference_lane_id = "", name = "Reference Cam", items = { reference_item } }
  local timeline_entries = {
    { guid = "marker-r", kind = "marker", selected = false, name = "Slate", start_samples = 0, end_samples = 0, color = 0 },
    { guid = "region-r", kind = "region", selected = false, name = "Take", start_samples = 100, end_samples = 200, color = 0 },
  }
  local rem_ids, rem_id_index = {}, 0
  for i = 1, 20 do rem_ids[i] = "rem-id-" .. i end
  local rem_adapter = {}
  function rem_adapter.project_path() return project_path end
  function rem_adapter.set_project_path(value) project_path = value end
  function rem_adapter.project_token() return "removed-master" end
  function rem_adapter.project_change_count() return 1 end
  function rem_adapter.get_project_value(key) return values[key] end
  function rem_adapter.set_project_value(key, value) values[key] = tostring(value) end
  function rem_adapter.all_tracks() return { reference_track } end
  function rem_adapter.selected_tracks() return {} end
  function rem_adapter.track_items(value) return value.items end
  function rem_adapter.track_name(value) return value.name end
  function rem_adapter.get_track_reference_lane_id(value) return value.reference_lane_id end
  function rem_adapter.set_track_reference_lane_id(value, id) value.reference_lane_id = id end
  function rem_adapter.set_track_reference_id(value, id) value.reference_id = id end
  function rem_adapter.get_item_reference_id(value) return value.reference_id end
  function rem_adapter.set_item_reference_id(value, id) value.reference_id = id end
  function rem_adapter.get_item_reference_item_id(value) return value.reference_item_id end
  function rem_adapter.set_item_reference_item_id(value, id) value.reference_item_id = id end
  function rem_adapter.item_display_name() return "Ref Cam Item" end
  function rem_adapter.reference_item_state(value)
    return {
      video_file = value.path, source_offset_samples = 0, duration_samples = 48000,
      playback_rate = 1, reference_start_samples = 0,
    }
  end
  function rem_adapter.timeline_state()
    return {
      sample_rate = 48000, project_timecode_offset_samples = 0,
      frame_rate = { numerator = 24, denominator = 1, drop_frame = false },
    }
  end
  function rem_adapter.timeline_entries() return timeline_entries end
  function rem_adapter.new_id() rem_id_index = rem_id_index + 1; return rem_ids[rem_id_index] end
  function rem_adapter.begin_undo() end
  function rem_adapter.end_undo() end
  function rem_adapter.mark_project_dirty() end
  function rem_adapter.save_project() return true end
  return rem_adapter, values, reference_track, timeline_entries
end

do
  local rem_adapter, values, reference_track, timeline_entries = removed_fixture()
  local rem_files = {}
  local rem_fs = {}
  function rem_fs.join(...) return table.concat({ ... }, "/"):gsub("/+", "/") end
  function rem_fs.exists(path) return path == "C:/show2/ref.mov" or rem_files[path] ~= nil end
  function rem_fs.read_file(path) return rem_files[path] end
  function rem_fs.hash_file(path) if path == "C:/show2/ref.mov" then return "ref-hash" end end
  local rem_writer = {}
  function rem_writer.publish(input)
    rem_files[rem_fs.join(input.package_root, "reference.json")] = json.encode(input.pointer)
    rem_files[rem_fs.join(input.package_root, input.pointer.manifest)] = json.encode(input.snapshot)
    return { reference_revision = input.pointer.latestReferenceRevision }
  end
  local rem_service = reference_publish.create({ reference_writer = rem_writer })

  -- Publish once with a Track, a Marker, and a Region registered.
  reference_track.reference_lane_id = "lane-pub"
  values.reference_timeline_entries = json.encode({
    { guid = "marker-r", entryId = "marker-pub", kind = "marker" },
    { guid = "region-r", entryId = "region-pub", kind = "region" },
  })
  local first_review = assert(rem_service.review(rem_adapter, rem_fs))
  assert(first_review.removed.total == 0, "nothing published yet, so nothing is removed")
  local first_result, first_err = rem_service.publish(first_review, rem_adapter, rem_fs, {
    published_at = "2026-09-23T00:00:00+00:00", published_by = "Bob",
  })
  assert(first_result, first_err)

  -- Unregister the Track and the Marker; keep the Region.
  reference_track.reference_lane_id = ""
  values.reference_timeline_entries = json.encode({
    { guid = "region-r", entryId = "region-pub", kind = "region" },
  })
  local blocked = assert(rem_service.review(rem_adapter, rem_fs))
  assert(blocked.removed.tracks == 1 and blocked.removed.markers == 1 and
    blocked.removed.regions == 0 and blocked.removed.total == 2,
    "removed content is counted by kind")
  assert(blocked.removed_blocker ==
    "1 Track and 1 Marker from Reference r1 are no longer registered.",
    "removed-content blocker names the counts and the last published revision")
  assert(blocked.blocker_count == 1, "removed content blocks Publish")

  local allowed = assert(rem_service.review(rem_adapter, rem_fs, { allow_removals = true }))
  assert(allowed.removed.total == 2, "allow_removals still reports what was removed")
  assert(not allowed.removed_blocker, "allow_removals clears the removed-content blocker")
  assert(allowed.blocker_count == 0, "allow_removals unblocks Publish")

  -- Re-registering the exact same Track and Marker identities is not a removal.
  reference_track.reference_lane_id = "lane-pub"
  values.reference_timeline_entries = json.encode({
    { guid = "marker-r", entryId = "marker-pub", kind = "marker" },
    { guid = "region-r", entryId = "region-pub", kind = "region" },
  })
  local restored = assert(rem_service.review(rem_adapter, rem_fs))
  assert(restored.removed.total == 0, "re-registering the same identity is not a removal")

  -- A Save As "new" review starts fresh: nothing counts as removed.
  reference_track.reference_lane_id = ""
  values.reference_timeline_entries = "[]"
  rem_adapter.set_project_path("C:/show2/renamed/CIN_099_MIX_New.rpp")
  local new_review = assert(rem_service.review(rem_adapter, rem_fs, { save_as_decision = "new" }))
  assert(new_review.removed.total == 0, "Save As new reports no removals")
  assert(not new_review.removed_blocker, "Save As new has no removed-content blocker")
end

return 13
