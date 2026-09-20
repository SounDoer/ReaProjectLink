local adapter = require("reaprojectlink.reaper_adapter")
local json = require("reaprojectlink.json")

reaper.GetSetProjectInfo(0, "PROJECT_SRATE", 48000, true)
reaper.InsertTrackAtIndex(0, false)
local track = assert(reaper.GetTrack(0, 0))
local item = assert(reaper.AddMediaItemToTrack(track))
local take = assert(reaper.AddTakeToMediaItem(item))

reaper.SetMediaItemInfo_Value(item, "D_POSITION", 2)
reaper.SetMediaItemInfo_Value(item, "D_LENGTH", 1)
reaper.SetMediaItemInfo_Value(item, "D_VOL", 0.5)
reaper.SetMediaItemInfo_Value(item, "D_FADEINLEN", 0.005)
reaper.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", 0.01)
reaper.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", 0.05)
reaper.SetMediaItemTakeInfo_Value(take, "D_VOL", -0.8)
reaper.SetMediaItemTakeInfo_Value(take, "D_PAN", -0.25)
reaper.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", 1.1)
reaper.SetMediaItemTakeInfo_Value(take, "D_PITCH", 2)
reaper.SetMediaItemTakeInfo_Value(take, "I_CHANMODE", 1)

adapter.set_track_lane_id(track, "lane-1")
adapter.set_item_clip_id(item, "clip-1")
adapter.set_item_reference_id(item, "reference-1")
reaper.SetMediaItemSelected(item, true)
local state = adapter.item_presentation(item)

assert(adapter.get_track_lane_id(track) == "lane-1", "Track identity round trip")
assert(adapter.get_item_clip_id(item) == "clip-1", "Item identity round trip")
assert(adapter.get_item_reference_id(item) == "reference-1", "Reference identity round trip")
assert(adapter.selected_items()[1] == item, "selected Item enumeration")
assert(not adapter.is_linked_item(item), "ordinary Item is not a Linked Item")
local ordinary_detach, ordinary_detach_error = adapter.detach_instance(item)
assert(not ordinary_detach and ordinary_detach_error == "Selected Item is not a Linked Item.",
  "ordinary Item identity is protected from Detach")
assert(adapter.get_item_clip_id(item) == "clip-1", "rejected Detach preserves Item identity")
local ordinary_delete, ordinary_delete_error = adapter.delete_linked_item(item)
assert(not ordinary_delete and ordinary_delete_error == "Selected Item is not a Linked Item.",
  "ordinary Item is protected from Delete")
assert(state.start_offset_samples == 96000, "timeline position conversion")
assert(state.source_offset_samples == 2400, "source offset conversion")
assert(state.length_samples == 48000, "length conversion")
assert(state.fade_in_samples == 240, "fade-in conversion")
assert(state.fade_out_samples == 480, "fade-out conversion")
assert(math.abs(state.take.playback_rate - 1.1) < 0.000001, "take rate")
assert(math.abs(state.take.volume - 0.8) < 0.000001, "absolute take volume")
assert(state.take.polarity_inverted, "take polarity")

local source = debug.getinfo(1, "S").source:sub(2)
local tests_dir = assert(source:match("^(.*)[/\\]"))
local wav_path = tests_dir .. "/.adapter-fixture.wav"
local sample_bytes = string.rep("\0", 96)
local wav = string.pack(
  "<c4I4c4c4I4I2I2I4I4I2I2c4I4",
  "RIFF", 36 + #sample_bytes, "WAVE", "fmt ", 16, 1, 1,
  48000, 96000, 2, 16, "data", #sample_bytes
) .. sample_bytes
local fixture = assert(io.open(wav_path, "wb"))
fixture:write(wav)
fixture:close()

local imported = assert(adapter.create_delivery_item(track, {
  clipId = "imported-clip",
  displayName = "Imported Line",
  mediaPath = wav_path,
  media_path = wav_path,
  mediaRevision = 4,
  sourceOffsetSamples = 240,
  lengthSamples = 480,
  itemGain = 0.5,
  fadeInSamples = 48,
  fadeOutSamples = 96,
  take = {
    volume = 0.8,
    pan = 0.2,
    playbackRate = 1,
    pitch = 1,
    channelMode = 0,
    polarityInverted = true,
  },
}, {
  source_sample_rate = 48000,
  position_seconds = 3,
  source_project_id = "source-1",
  delivery_revision = 8,
  reference_revision = 7,
  instance_id = "instance-1",
}))
local imported_state = adapter.item_presentation(imported)
assert(imported_state.start_offset_samples == 144000, "imported position")
assert(imported_state.length_samples == 480, "imported length")
assert(imported_state.source_offset_samples == 240, "imported source offset")
assert(imported_state.take.polarity_inverted, "imported polarity")
assert(adapter.get_item_clip_id(imported) == "imported-clip", "imported Clip binding")
assert(adapter.is_linked_item(imported), "imported Item is linked")

local instances = adapter.delivery_instances("source-1")
assert(#instances == 1 and instances[1].instance_id == "instance-1", "linked Instance scan")
assert(not instances[1].retired, "new Linked Item is not retired")
adapter.set_instance_retired(imported, true)
assert(adapter.delivery_instances("source-1")[1].retired, "retirement decision persists")
adapter.set_instance_retired(imported, false)
assert(adapter.add_delivery_take(imported, {
  displayName = "Imported Line",
  mediaRevision = 5,
  sourceOffsetSamples = 0,
  take = { volume = 1, pan = 0, playbackRate = 1, pitch = 0, channelMode = 0, polarityInverted = false },
}, wav_path, { source_sample_rate = 48000 }))
assert(reaper.CountTakes(imported) == 2, "update adds a Take")
assert(adapter.apply_delivery_fields(imported, {
  position_seconds = { choice = "use_delivery", delivery = 2 },
  length_seconds = { choice = "use_delivery", delivery = 0.02 },
  source_offset_seconds = { choice = "keep_local", local_state = 0.005 },
  take_volume = { choice = "keep_local", local_state = 0.8 },
  take_polarity_inverted = { choice = "keep_local", local_state = true },
  take_pan = { choice = "keep_local", local_state = 0.2 },
  take_pitch = { choice = "keep_local", local_state = 1 },
}, { reference_start_samples = 96000, project_sample_rate = 48000 }))
assert(math.abs(reaper.GetMediaItemInfo_Value(imported, "D_POSITION") - 4) < 0.000001, "update position")
local updated_take = reaper.GetActiveTake(imported)
assert(math.abs(reaper.GetMediaItemTakeInfo_Value(updated_take, "D_STARTOFFS") - 0.005) < 0.000001, "new Take preserves local source offset")
assert(math.abs(reaper.GetMediaItemTakeInfo_Value(updated_take, "D_VOL") + 0.8) < 0.000001, "new Take preserves local volume and polarity")
assert(math.abs(reaper.GetMediaItemTakeInfo_Value(updated_take, "D_PAN") - 0.2) < 0.000001, "new Take preserves local pan")
assert(math.abs(reaper.GetMediaItemTakeInfo_Value(updated_take, "D_PITCH") - 1) < 0.000001, "new Take preserves local pitch")
adapter.set_instance_revisions(imported, 5, 9)
instances = adapter.delivery_instances("source-1")
assert(instances[1].accepted_media_revision == 5, "accepted media revision")
assert(instances[1].handled_delivery_revision == 9, "handled Publish revision")
assert(adapter.detach_instance(imported), "detach Instance")
assert(not adapter.is_linked_item(imported), "detached Item is no longer linked")
assert(#adapter.delivery_instances("source-1") == 0, "detached Item is ordinary")

local deletable = assert(adapter.create_delivery_item(track, {
  clipId = "delete-clip",
  displayName = "Delete Line",
  media_path = wav_path,
  mediaRevision = 1,
  sourceOffsetSamples = 0,
  lengthSamples = 480,
  itemGain = 1,
  take = {},
}, {
  source_sample_rate = 48000,
  position_seconds = 5,
  source_project_id = "source-1",
  delivery_revision = 1,
  reference_revision = 7,
  instance_id = "delete-instance",
}))
assert(adapter.delete_linked_item(deletable), "delete retired Linked Item")
assert(not adapter.valid_item(deletable), "deleted Linked Item is removed")

local reference = {
  schemaVersion = 2,
  masterProjectId = "master-1",
  masterProjectName = "Reference Master",
  referenceId = "reference-set-1",
  referenceRevision = 1,
  timeline = {
    sampleRate = 48000,
    projectTimecodeOffsetSamples = 3600000,
    referenceStartSamples = 48000,
    referenceStartMarkerId = "marker-reference-start",
    frameRate = { numerator = 30000, denominator = 1001, dropFrame = true },
  },
  lanes = {
    { laneId = "reference-lane-1", displayName = "Reference Main", order = 0, items = {
      { itemId = "reference-item-1", displayName = "Shot A", videoFile = wav_path,
        videoHash = "sha256:test", startSamples = 48000, sourceOffsetSamples = 0,
        durationSamples = 48000, playbackRate = 1 },
    } },
    { laneId = "reference-lane-2", displayName = "Reference Overlay", order = 1, items = {
      { itemId = "reference-item-2", displayName = "Overlay", videoFile = wav_path,
        videoHash = "sha256:test", startSamples = 96000, sourceOffsetSamples = 0,
        durationSamples = 24000, playbackRate = 1 },
    } },
  },
  markers = {
    { entryId = "marker-reference-start", name = "FFOP", startSamples = 48000, color = 0 },
  },
  regions = {
    { entryId = "region-scene", name = "Scene", startSamples = 48000, endSamples = 144000, color = 0 },
  },
}
local synced_reference = assert(adapter.sync_reference(reference, { alignment_mode = "mirror" }))
assert(synced_reference.created_tracks == 2, "multi-track Reference creates Reference Tracks")
assert(synced_reference.created_items == 2, "multi-track Reference creates video Items")
local mirrored_timeline = adapter.timeline_state()
assert(mirrored_timeline.frame_rate.numerator == 30000 and
  mirrored_timeline.frame_rate.denominator == 1001,
  string.format("Master frame rate is mirrored (got %s/%s)",
    tostring(mirrored_timeline.frame_rate.numerator),
    tostring(mirrored_timeline.frame_rate.denominator)))
assert(mirrored_timeline.frame_rate.drop_frame,
  "Master drop-frame mode is mirrored")
assert(mirrored_timeline.project_timecode_offset_samples == 3600000,
  "Master project timecode offset is mirrored")
assert(adapter.set_timeline_state({
  sampleRate = 48000,
  projectTimecodeOffsetSamples = 0,
  frameRate = { numerator = 24000, denominator = 1001, dropFrame = false },
}))
local fractional_timeline = adapter.timeline_state()
assert(fractional_timeline.frame_rate.numerator == 24000 and
  fractional_timeline.frame_rate.denominator == 1001 and
  not fractional_timeline.frame_rate.drop_frame,
  "23.976 non-drop frame rate is mirrored")
local reference_item_count = 0
for _, candidate_track in ipairs(adapter.all_tracks()) do
  for _, candidate_item in ipairs(adapter.track_items(candidate_track)) do
    if adapter.get_item_reference_id(candidate_item) == "reference-set-1" then
      reference_item_count = reference_item_count + 1
    end
  end
end
assert(reference_item_count == 2, "both managed Reference Items are present")
local has_reference_start, has_scene = false, false
for _, entry in ipairs(adapter.timeline_entries()) do
  if entry.name == "FFOP" then has_reference_start = true end
  if entry.name == "Scene" and entry.kind == "region" then has_scene = true end
end
assert(has_reference_start and has_scene, "Marker and Region synchronized")

reference.referenceRevision = 2
table.remove(reference.lanes, 2)
reference.regions = {}
local reduced_reference = assert(adapter.sync_reference(reference, { alignment_mode = "mirror" }))
assert(reduced_reference.removed_items == 1, "retired Reference Item is removed")
for index = reaper.CountTracks(0) - 1, 0, -1 do
  local candidate_track = reaper.GetTrack(0, index)
  if adapter.get_track_reference_id(candidate_track) == "reference-set-1" or
      adapter.get_track_reference_lane_id(candidate_track) ~= "" or
      adapter.track_name(candidate_track) == "Reference Main" or
      adapter.track_name(candidate_track) == "Reference Overlay" then
    reaper.DeleteTrack(candidate_track)
  end
end
for _, mapping in ipairs(json.decode(adapter.get_project_value("reference_timeline_entries") or "[]")) do
  reaper.DeleteProjectMarker(0, mapping.number, mapping.kind == "region")
end
adapter.set_project_value("reference_timeline_entries", "")
os.remove(wav_path)

local folder = adapter.create_master_track("Delivery Folder")
local child_one = adapter.create_master_track("Lane One", folder)
local child_two = adapter.create_master_track("Lane Two", folder)
assert(reaper.GetTrack(0, 1) == folder, "Folder position")
assert(reaper.GetTrack(0, 2) == child_one, "first child order")
assert(reaper.GetTrack(0, 3) == child_two, "second child order")
assert(reaper.GetMediaTrackInfo_Value(folder, "I_FOLDERDEPTH") == 1, "Folder opened")
assert(reaper.GetMediaTrackInfo_Value(child_one, "I_FOLDERDEPTH") == 0, "intermediate child")
assert(reaper.GetMediaTrackInfo_Value(child_two, "I_FOLDERDEPTH") == -1, "last child closes Folder")

reaper.DeleteTrack(child_two)
reaper.DeleteTrack(child_one)
reaper.DeleteTrack(folder)

reaper.DeleteTrack(track)

local original_project_token = adapter.project_token()
reaper.Main_OnCommand(40859, 0)
assert(adapter.project_token() ~= original_project_token,
  "a new Project Tab has a distinct runtime token")
reaper.Main_OnCommand(40860, 0)
assert(adapter.project_token() == original_project_token,
  "returning to the original Project Tab restores its runtime token")

return 1
