local constants = require("readelivery.constants")

local M = {}

local function project()
  return 0
end

function M.project_path()
  local _, path = reaper.EnumProjects(-1, "")
  return path or ""
end

function M.new_id()
  local value = reaper.genGuid("")
  return value:gsub("[{}]", ""):lower()
end

function M.get_project_value(key)
  local found, value = reaper.GetProjExtState(
    project(),
    constants.EXTENSION_NAME,
    key
  )
  if found == 0 then
    return nil
  end
  return value
end

function M.set_project_value(key, value)
  reaper.SetProjExtState(
    project(),
    constants.EXTENSION_NAME,
    key,
    value or ""
  )
end

function M.selected_tracks()
  local tracks = {}
  for index = 0, reaper.CountSelectedTracks(project()) - 1 do
    table.insert(tracks, reaper.GetSelectedTrack(project(), index))
  end
  return tracks
end

function M.selected_items()
  local items = {}
  for index = 0, reaper.CountSelectedMediaItems(project()) - 1 do
    table.insert(items, reaper.GetSelectedMediaItem(project(), index))
  end
  return items
end

function M.all_tracks()
  local tracks = {}
  for index = 0, reaper.CountTracks(project()) - 1 do
    table.insert(tracks, reaper.GetTrack(project(), index))
  end
  return tracks
end

function M.get_track_lane_id(track)
  local _, value = reaper.GetSetMediaTrackInfo_String(
    track,
    constants.TRACK_KEYS.lane_id,
    "",
    false
  )
  return value
end

function M.set_track_lane_id(track, lane_id)
  reaper.GetSetMediaTrackInfo_String(
    track,
    constants.TRACK_KEYS.lane_id,
    lane_id,
    true
  )
end

function M.get_item_clip_id(item)
  local _, value = reaper.GetSetMediaItemInfo_String(
    item,
    constants.ITEM_KEYS.clip_id,
    "",
    false
  )
  return value
end

function M.set_item_clip_id(item, clip_id)
  reaper.GetSetMediaItemInfo_String(
    item,
    constants.ITEM_KEYS.clip_id,
    clip_id,
    true
  )
end

function M.get_item_picture_id(item)
  local _, value = reaper.GetSetMediaItemInfo_String(
    item,
    constants.ITEM_KEYS.picture_id,
    "",
    false
  )
  return value
end

function M.set_item_picture_id(item, picture_id)
  reaper.GetSetMediaItemInfo_String(
    item,
    constants.ITEM_KEYS.picture_id,
    picture_id,
    true
  )
end

function M.track_name(track)
  local _, value = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
  return value ~= "" and value or "(unnamed track)"
end

function M.item_display_name(item)
  local take = reaper.GetActiveTake(item)
  if take then
    local _, take_name = reaper.GetSetMediaItemTakeInfo_String(
      take,
      "P_NAME",
      "",
      false
    )
    if take_name and take_name ~= "" then
      return take_name
    end
  end

  local _, notes = reaper.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
  return notes ~= "" and notes or "(unnamed item)"
end

function M.track_items(track)
  local items = {}
  for index = 0, reaper.CountTrackMediaItems(track) - 1 do
    table.insert(items, reaper.GetTrackMediaItem(track, index))
  end
  return items
end

function M.track_fx_count(track)
  return reaper.TrackFX_GetCount(track)
end

function M.active_take_media(item)
  local take = reaper.GetActiveTake(item)
  if not take or reaper.TakeIsMIDI(take) then
    return nil
  end

  local source = reaper.GetMediaItemTake_Source(take)
  if not source then
    return nil
  end

  local path = reaper.GetMediaSourceFileName(source, "")
  return {
    path = path,
    sample_rate = reaper.GetMediaSourceSampleRate(source),
    channel_count = reaper.GetMediaSourceNumChannels(source),
    take_fx_count = reaper.TakeFX_GetCount(take),
  }
end

local function seconds_to_samples(seconds, sample_rate)
  return math.floor(seconds * sample_rate + 0.5)
end

function M.project_sample_rate()
  local sample_rate = reaper.GetSetProjectInfo(project(), "PROJECT_SRATE", 0, false)
  if sample_rate and sample_rate > 0 then
    return math.floor(sample_rate + 0.5)
  end

  local ok, device_rate = reaper.GetAudioDeviceInfo("SRATE")
  sample_rate = ok and tonumber(device_rate) or nil
  return sample_rate and math.floor(sample_rate + 0.5) or 48000
end

function M.item_presentation(item)
  local take = reaper.GetActiveTake(item)
  if not take then return nil end

  local sample_rate = M.project_sample_rate()
  local take_volume = reaper.GetMediaItemTakeInfo_Value(take, "D_VOL")
  return {
    start_offset_samples = seconds_to_samples(
      reaper.GetMediaItemInfo_Value(item, "D_POSITION"),
      sample_rate
    ),
    source_offset_samples = seconds_to_samples(
      reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS"),
      sample_rate
    ),
    length_samples = seconds_to_samples(
      reaper.GetMediaItemInfo_Value(item, "D_LENGTH"),
      sample_rate
    ),
    item_gain = reaper.GetMediaItemInfo_Value(item, "D_VOL"),
    fade_in_samples = seconds_to_samples(
      reaper.GetMediaItemInfo_Value(item, "D_FADEINLEN"),
      sample_rate
    ),
    fade_out_samples = seconds_to_samples(
      reaper.GetMediaItemInfo_Value(item, "D_FADEOUTLEN"),
      sample_rate
    ),
    take = {
      volume = math.abs(take_volume),
      pan = reaper.GetMediaItemTakeInfo_Value(take, "D_PAN"),
      playback_rate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE"),
      pitch = reaper.GetMediaItemTakeInfo_Value(take, "D_PITCH"),
      channel_mode = reaper.GetMediaItemTakeInfo_Value(take, "I_CHANMODE"),
      polarity_inverted = take_volume < 0,
    },
  }
end

local function frame_rate_ratio(frame_rate)
  local ntsc_rates = {
    { value = 24000 / 1001, numerator = 24000 },
    { value = 30000 / 1001, numerator = 30000 },
    { value = 60000 / 1001, numerator = 60000 },
  }
  for _, candidate in ipairs(ntsc_rates) do
    if math.abs(frame_rate - candidate.value) < 0.001 then
      return candidate.numerator, 1001
    end
  end
  return math.floor(frame_rate + 0.5), 1
end

function M.picture_item_state(item)
  local take = reaper.GetActiveTake(item)
  if not take or reaper.TakeIsMIDI(take) then return nil end
  local source = reaper.GetMediaItemTake_Source(take)
  if not source then return nil end
  local path = reaper.GetMediaSourceFileName(source, "")
  local sample_rate = M.project_sample_rate()
  local frame_rate, drop_frame = reaper.TimeMap_curFrameRate(project())
  local numerator, denominator = frame_rate_ratio(frame_rate)
  return {
    video_file = path,
    sample_rate = sample_rate,
    picture_start_samples = seconds_to_samples(
      reaper.GetMediaItemInfo_Value(item, "D_POSITION"),
      sample_rate
    ),
    source_offset_samples = seconds_to_samples(
      reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS"),
      sample_rate
    ),
    duration_samples = seconds_to_samples(
      reaper.GetMediaItemInfo_Value(item, "D_LENGTH"),
      sample_rate
    ),
    playback_rate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE"),
    frame_rate = {
      numerator = numerator,
      denominator = denominator,
      drop_frame = drop_frame,
    },
    project_timecode_offset_samples = seconds_to_samples(
      reaper.GetProjectTimeOffset(project(), false),
      sample_rate
    ),
  }
end

function M.file_exists(path)
  return reaper.file_exists(path)
end

function M.begin_undo(label)
  reaper.Undo_BeginBlock2(project())
end

function M.end_undo(label)
  reaper.Undo_EndBlock2(project(), label, -1)
end

function M.mark_project_dirty()
  reaper.MarkProjectDirty(project())
end

function M.save_project()
  reaper.Main_SaveProject(project(), false)
  return true
end

return M
