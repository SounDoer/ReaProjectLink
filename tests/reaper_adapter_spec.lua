local adapter = require("readelivery.reaper_adapter")
local json = require("readelivery.json")

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
adapter.set_item_picture_id(item, "picture-1")
reaper.SetMediaItemSelected(item, true)
local state = adapter.item_presentation(item)

assert(adapter.get_track_lane_id(track) == "lane-1", "Track identity round trip")
assert(adapter.get_item_clip_id(item) == "clip-1", "Item identity round trip")
assert(adapter.get_item_picture_id(item) == "picture-1", "Picture identity round trip")
assert(adapter.selected_items()[1] == item, "selected Item enumeration")
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
  publish_revision = 8,
  picture_revision = 7,
  instance_id = "instance-1",
}))
local imported_state = adapter.item_presentation(imported)
assert(imported_state.start_offset_samples == 144000, "imported position")
assert(imported_state.length_samples == 480, "imported length")
assert(imported_state.source_offset_samples == 240, "imported source offset")
assert(imported_state.take.polarity_inverted, "imported polarity")
assert(adapter.get_item_clip_id(imported) == "imported-clip", "imported Clip binding")

local instances = adapter.delivery_instances("source-1")
assert(#instances == 1 and instances[1].instance_id == "instance-1", "linked Instance scan")
assert(adapter.add_delivery_take(imported, {
  displayName = "Imported Line",
  mediaRevision = 5,
  sourceOffsetSamples = 0,
  take = { volume = 1, pan = 0, playbackRate = 1, pitch = 0, channelMode = 0, polarityInverted = false },
}, wav_path, { source_sample_rate = 48000 }))
assert(reaper.CountTakes(imported) == 2, "update adds a Take")
assert(adapter.apply_delivery_fields(imported, {
  position_seconds = { choice = "use_source", source = 2 },
  length_seconds = { choice = "use_source", source = 0.02 },
  source_offset_seconds = { choice = "keep_mix", mix = 0.005 },
  take_volume = { choice = "keep_mix", mix = 0.8 },
  take_polarity_inverted = { choice = "keep_mix", mix = true },
  take_pan = { choice = "keep_mix", mix = 0.2 },
  take_pitch = { choice = "keep_mix", mix = 1 },
}, { picture_start_samples = 96000, project_sample_rate = 48000 }))
assert(math.abs(reaper.GetMediaItemInfo_Value(imported, "D_POSITION") - 4) < 0.000001, "update position")
local updated_take = reaper.GetActiveTake(imported)
assert(math.abs(reaper.GetMediaItemTakeInfo_Value(updated_take, "D_STARTOFFS") - 0.005) < 0.000001, "new Take preserves Mix source offset")
assert(math.abs(reaper.GetMediaItemTakeInfo_Value(updated_take, "D_VOL") + 0.8) < 0.000001, "new Take preserves Mix volume and polarity")
assert(math.abs(reaper.GetMediaItemTakeInfo_Value(updated_take, "D_PAN") - 0.2) < 0.000001, "new Take preserves Mix pan")
assert(math.abs(reaper.GetMediaItemTakeInfo_Value(updated_take, "D_PITCH") - 1) < 0.000001, "new Take preserves Mix pitch")
adapter.set_instance_revisions(imported, 5, 9)
instances = adapter.delivery_instances("source-1")
assert(instances[1].accepted_media_revision == 5, "accepted media revision")
assert(instances[1].handled_publish_revision == 9, "handled Publish revision")
assert(adapter.detach_instance(imported), "detach Instance")
assert(#adapter.delivery_instances("source-1") == 0, "detached Item is ordinary")

local reference = {
  schemaVersion = 2,
  pictureId = "picture-set-1",
  pictureRevision = 1,
  timeline = {
    sampleRate = 48000,
    projectTimecodeOffsetSamples = 3600000,
    referenceStartSamples = 48000,
    frameRate = { numerator = 30000, denominator = 1001, dropFrame = true },
  },
  lanes = {
    { laneId = "picture-lane-1", displayName = "Picture Main", order = 0, items = {
      { itemId = "picture-item-1", displayName = "Shot A", videoFile = wav_path,
        videoHash = "sha256:test", startSamples = 48000, sourceOffsetSamples = 0,
        durationSamples = 48000, playbackRate = 1 },
    } },
    { laneId = "picture-lane-2", displayName = "Picture Overlay", order = 1, items = {
      { itemId = "picture-item-2", displayName = "Overlay", videoFile = wav_path,
        videoHash = "sha256:test", startSamples = 96000, sourceOffsetSamples = 0,
        durationSamples = 24000, playbackRate = 1 },
    } },
  },
  markers = {
    { entryId = "marker-ffop", name = "FFOP", startSamples = 48000, color = 0, semanticRole = "FFOP" },
  },
  regions = {
    { entryId = "region-scene", name = "Scene", startSamples = 48000, endSamples = 144000, color = 0 },
  },
}
local synced_reference = assert(adapter.sync_picture(reference, { alignment_mode = "mirror" }))
assert(synced_reference.created_tracks == 2, "multi-track Master Reference creates Picture Tracks")
assert(synced_reference.created_items == 2, "multi-track Master Reference creates video Items")
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
local picture_item_count = 0
for _, candidate_track in ipairs(adapter.all_tracks()) do
  for _, candidate_item in ipairs(adapter.track_items(candidate_track)) do
    if adapter.get_item_picture_id(candidate_item) == "picture-set-1" then
      picture_item_count = picture_item_count + 1
    end
  end
end
assert(picture_item_count == 2, "both managed Picture Items are present")
local has_ffop, has_scene = false, false
for _, entry in ipairs(adapter.timeline_entries()) do
  if entry.name == "FFOP" then has_ffop = true end
  if entry.name == "Scene" and entry.kind == "region" then has_scene = true end
end
assert(has_ffop and has_scene, "Marker and Region synchronized")

reference.pictureRevision = 2
table.remove(reference.lanes, 2)
reference.regions = {}
local reduced_reference = assert(adapter.sync_picture(reference, { alignment_mode = "mirror" }))
assert(reduced_reference.removed_items == 1, "retired Picture Item is removed")
for index = reaper.CountTracks(0) - 1, 0, -1 do
  local candidate_track = reaper.GetTrack(0, index)
  if adapter.get_track_picture_set_id(candidate_track) == "picture-set-1" or
      adapter.get_track_picture_lane_id(candidate_track) ~= "" or
      adapter.track_name(candidate_track) == "Picture Main" or
      adapter.track_name(candidate_track) == "Picture Overlay" then
    reaper.DeleteTrack(candidate_track)
  end
end
for _, mapping in ipairs(json.decode(adapter.get_project_value("picture_timeline_entries") or "[]")) do
  reaper.DeleteProjectMarker(0, mapping.number, mapping.kind == "region")
end
adapter.set_project_value("picture_timeline_entries", "")
os.remove(wav_path)

local folder = adapter.create_mix_track("Delivery Folder")
local child_one = adapter.create_mix_track("Lane One", folder)
local child_two = adapter.create_mix_track("Lane Two", folder)
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
