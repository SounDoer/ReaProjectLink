local adapter = require("readelivery.reaper_adapter")

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

return 1
