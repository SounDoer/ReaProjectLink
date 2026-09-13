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
local state = adapter.item_presentation(item)

assert(adapter.get_track_lane_id(track) == "lane-1", "Track identity round trip")
assert(adapter.get_item_clip_id(item) == "clip-1", "Item identity round trip")
assert(state.start_offset_samples == 96000, "timeline position conversion")
assert(state.source_offset_samples == 2400, "source offset conversion")
assert(state.length_samples == 48000, "length conversion")
assert(state.fade_in_samples == 240, "fade-in conversion")
assert(state.fade_out_samples == 480, "fade-out conversion")
assert(math.abs(state.take.playback_rate - 1.1) < 0.000001, "take rate")
assert(math.abs(state.take.volume - 0.8) < 0.000001, "absolute take volume")
assert(state.take.polarity_inverted, "take polarity")

reaper.DeleteTrack(track)

return 1
