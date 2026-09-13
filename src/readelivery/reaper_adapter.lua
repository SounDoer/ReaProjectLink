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

function M.track_guid(track)
  return reaper.GetTrackGUID(track)
end

function M.track_by_guid(guid)
  for _, track in ipairs(M.all_tracks()) do
    if M.track_guid(track) == guid then return track end
  end
end

function M.create_mix_track(name, parent_track)
  local index = reaper.CountTracks(project())
  local close_folder = false
  if parent_track then
    local parent_index = math.floor(
      reaper.GetMediaTrackInfo_Value(parent_track, "IP_TRACKNUMBER")
    ) - 1
    local parent_depth = math.floor(
      reaper.GetMediaTrackInfo_Value(parent_track, "I_FOLDERDEPTH")
    )
    if parent_depth <= 0 then
      reaper.SetMediaTrackInfo_Value(parent_track, "I_FOLDERDEPTH", 1)
      index = parent_index + 1
      close_folder = true
    else
      local depth = parent_depth
      for candidate_index = parent_index + 1, reaper.CountTracks(project()) - 1 do
        local candidate = reaper.GetTrack(project(), candidate_index)
        depth = depth + math.floor(
          reaper.GetMediaTrackInfo_Value(candidate, "I_FOLDERDEPTH")
        )
        if depth <= 0 then
          local closing_depth = math.floor(
            reaper.GetMediaTrackInfo_Value(candidate, "I_FOLDERDEPTH")
          )
          reaper.SetMediaTrackInfo_Value(
            candidate,
            "I_FOLDERDEPTH",
            closing_depth + 1
          )
          index = candidate_index + 1
          close_folder = true
          break
        end
      end
      if not close_folder then close_folder = true end
    end
  end
  reaper.InsertTrackAtIndex(index, true)
  local track = reaper.GetTrack(project(), index)
  reaper.GetSetMediaTrackInfo_String(track, "P_NAME", name or "Delivery Lane", true)
  if close_folder then
    reaper.SetMediaTrackInfo_Value(track, "I_FOLDERDEPTH", -1)
  end
  return track
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

local function picture_items(picture_id)
  local items = {}
  for _, track in ipairs(M.all_tracks()) do
    for _, item in ipairs(M.track_items(track)) do
      if M.get_item_picture_id(item) == picture_id then
        table.insert(items, item)
      end
    end
  end
  return items
end

function M.sync_picture(snapshot)
  local matches = picture_items(snapshot.pictureId)
  if #matches > 1 then
    return nil, "Multiple Items carry the subscribed Picture ID."
  end

  local item = matches[1]
  local created = false
  if not item then
    reaper.InsertTrackAtIndex(reaper.CountTracks(project()), true)
    local track = reaper.GetTrack(project(), reaper.CountTracks(project()) - 1)
    reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "ReaDelivery Picture", true)
    item = reaper.AddMediaItemToTrack(track)
    created = true
  end

  local source = reaper.PCM_Source_CreateFromFile(snapshot.videoFile)
  if not source then return nil, "Could not open the published Picture video." end
  local take = reaper.GetActiveTake(item)
  if not take then take = reaper.AddTakeToMediaItem(item) end
  local old_source = reaper.GetMediaItemTake_Source(take)
  reaper.SetMediaItemTake_Source(take, source)
  if old_source then reaper.PCM_Source_Destroy(old_source) end
  reaper.SetActiveTake(take)

  local sample_rate = snapshot.sampleRate
  reaper.SetMediaItemInfo_Value(item, "D_POSITION", snapshot.pictureStartSamples / sample_rate)
  reaper.SetMediaItemInfo_Value(item, "D_LENGTH", snapshot.durationSamples / sample_rate)
  reaper.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", snapshot.sourceOffsetSamples / sample_rate)
  reaper.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", snapshot.playbackRate)
  M.set_item_picture_id(item, snapshot.pictureId)
  reaper.UpdateArrange()
  return { item_ref = item, created = created }
end

local function set_item_string(item, key, value)
  reaper.GetSetMediaItemInfo_String(item, key, tostring(value or ""), true)
end

local function get_item_string(item, key)
  local _, value = reaper.GetSetMediaItemInfo_String(item, key, "", false)
  return value
end

function M.create_delivery_item(track, clip, context)
  local source = reaper.PCM_Source_CreateFromFile(clip.media_path)
  if not source then return nil, "Could not open managed WAV: " .. clip.media_path end
  local item = reaper.AddMediaItemToTrack(track)
  local take = reaper.AddTakeToMediaItem(item)
  reaper.SetMediaItemTake_Source(take, source)
  reaper.SetActiveTake(take)

  local sample_rate = context.source_sample_rate
  reaper.SetMediaItemInfo_Value(item, "D_POSITION", context.position_seconds)
  reaper.SetMediaItemInfo_Value(item, "D_LENGTH", clip.lengthSamples / sample_rate)
  reaper.SetMediaItemInfo_Value(item, "D_VOL", clip.itemGain or 1)
  reaper.SetMediaItemInfo_Value(item, "D_FADEINLEN", (clip.fadeInSamples or 0) / sample_rate)
  reaper.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", (clip.fadeOutSamples or 0) / sample_rate)

  local take_state = clip.take or {}
  local take_volume = take_state.volume or 1
  if take_state.polarityInverted then take_volume = -math.abs(take_volume) end
  reaper.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", clip.sourceOffsetSamples / sample_rate)
  reaper.SetMediaItemTakeInfo_Value(take, "D_VOL", take_volume)
  reaper.SetMediaItemTakeInfo_Value(take, "D_PAN", take_state.pan or 0)
  reaper.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", take_state.playbackRate or 1)
  reaper.SetMediaItemTakeInfo_Value(take, "D_PITCH", take_state.pitch or 0)
  reaper.SetMediaItemTakeInfo_Value(take, "I_CHANMODE", take_state.channelMode or 0)
  reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", clip.displayName or "", true)

  M.set_item_clip_id(item, clip.clipId)
  set_item_string(item, constants.ITEM_KEYS.source_project_id, context.source_project_id)
  set_item_string(item, constants.ITEM_KEYS.instance_id, context.instance_id)
  set_item_string(item, constants.ITEM_KEYS.accepted_media_revision, clip.mediaRevision)
  set_item_string(item, constants.ITEM_KEYS.handled_publish_revision, context.publish_revision)
  set_item_string(item, constants.ITEM_KEYS.picture_revision, context.picture_revision)
  return item
end

local function current_instance_state(item, picture_start_seconds)
  local take = reaper.GetActiveTake(item)
  if not take then return nil end
  local take_volume = reaper.GetMediaItemTakeInfo_Value(take, "D_VOL")
  return {
    position_seconds = reaper.GetMediaItemInfo_Value(item, "D_POSITION") -
      picture_start_seconds,
    length_seconds = reaper.GetMediaItemInfo_Value(item, "D_LENGTH"),
    source_offset_seconds = reaper.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS"),
    fade_in_seconds = reaper.GetMediaItemInfo_Value(item, "D_FADEINLEN"),
    fade_out_seconds = reaper.GetMediaItemInfo_Value(item, "D_FADEOUTLEN"),
    item_gain = reaper.GetMediaItemInfo_Value(item, "D_VOL"),
    take_volume = math.abs(take_volume),
    take_pan = reaper.GetMediaItemTakeInfo_Value(take, "D_PAN"),
    take_playback_rate = reaper.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE"),
    take_pitch = reaper.GetMediaItemTakeInfo_Value(take, "D_PITCH"),
    take_channel_mode = reaper.GetMediaItemTakeInfo_Value(take, "I_CHANMODE"),
    take_polarity_inverted = take_volume < 0,
  }
end

local function has_advanced_take_state(take)
  if reaper.TakeFX_GetCount(take) > 0 then return true end
  if reaper.CountTakeEnvelopes and reaper.CountTakeEnvelopes(take) > 0 then return true end
  if reaper.GetTakeNumStretchMarkers and reaper.GetTakeNumStretchMarkers(take) > 0 then return true end
  if reaper.GetNumTakeMarkers and reaper.GetNumTakeMarkers(take) > 0 then return true end
  local source = reaper.GetMediaItemTake_Source(take)
  local source_type = source and reaper.GetMediaSourceType(source, "") or ""
  return source_type ~= "WAVE" and source_type ~= "WAV"
end

function M.delivery_instances(source_project_id)
  local instances = {}
  local sample_rate = M.project_sample_rate()
  local picture_start_samples = tonumber(M.get_project_value(
    constants.PROJECT_KEYS.picture_start_samples
  )) or 0
  local picture_start_seconds = picture_start_samples / sample_rate
  for _, track in ipairs(M.all_tracks()) do
    for _, item in ipairs(M.track_items(track)) do
      if get_item_string(item, constants.ITEM_KEYS.source_project_id) == source_project_id then
        local take = reaper.GetActiveTake(item)
        table.insert(instances, {
          item_ref = item,
          clip_id = M.get_item_clip_id(item),
          instance_id = get_item_string(item, constants.ITEM_KEYS.instance_id),
          accepted_media_revision = tonumber(get_item_string(
            item,
            constants.ITEM_KEYS.accepted_media_revision
          )) or 0,
          handled_publish_revision = tonumber(get_item_string(
            item,
            constants.ITEM_KEYS.handled_publish_revision
          )) or 0,
          state = current_instance_state(item, picture_start_seconds),
          advanced_take_state = take and has_advanced_take_state(take) or false,
        })
      end
    end
  end
  return instances
end

local function apply_take_state(take, clip)
  local state = clip.take or {}
  local volume = state.volume or 1
  if state.polarityInverted then volume = -math.abs(volume) end
  reaper.SetMediaItemTakeInfo_Value(take, "D_VOL", volume)
  reaper.SetMediaItemTakeInfo_Value(take, "D_PAN", state.pan or 0)
  reaper.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", state.playbackRate or 1)
  reaper.SetMediaItemTakeInfo_Value(take, "D_PITCH", state.pitch or 0)
  reaper.SetMediaItemTakeInfo_Value(take, "I_CHANMODE", state.channelMode or 0)
end

function M.add_delivery_take(item, clip, media_path, context)
  local source = reaper.PCM_Source_CreateFromFile(media_path)
  if not source then return nil, "Could not open managed WAV: " .. media_path end
  local take = reaper.AddTakeToMediaItem(item)
  reaper.SetMediaItemTake_Source(take, source)
  reaper.SetMediaItemTakeInfo_Value(
    take,
    "D_STARTOFFS",
    clip.sourceOffsetSamples / context.source_sample_rate
  )
  apply_take_state(take, clip)
  reaper.GetSetMediaItemTakeInfo_String(
    take,
    "P_NAME",
    string.format("%s r%04d", clip.displayName or "Delivery", clip.mediaRevision),
    true
  )
  reaper.SetActiveTake(take)
  return true
end

function M.apply_delivery_fields(item, fields, context)
  local take = reaper.GetActiveTake(item)
  if not take then return nil, "Linked Instance has no active Take." end
  local function source_value(field)
    local decision = fields[field]
    return decision and decision.choice == "use_source" and decision.source or nil
  end
  local value = source_value("position_seconds")
  if value ~= nil then
    reaper.SetMediaItemInfo_Value(
      item,
      "D_POSITION",
      context.picture_start_samples / context.project_sample_rate + value
    )
  end
  value = source_value("length_seconds")
  if value ~= nil then reaper.SetMediaItemInfo_Value(item, "D_LENGTH", value) end
  value = source_value("source_offset_seconds")
  if value ~= nil then reaper.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", value) end
  value = source_value("fade_in_seconds")
  if value ~= nil then reaper.SetMediaItemInfo_Value(item, "D_FADEINLEN", value) end
  value = source_value("fade_out_seconds")
  if value ~= nil then reaper.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", value) end
  value = source_value("item_gain")
  if value ~= nil then reaper.SetMediaItemInfo_Value(item, "D_VOL", value) end

  local current_volume = reaper.GetMediaItemTakeInfo_Value(take, "D_VOL")
  local volume = source_value("take_volume") or math.abs(current_volume)
  local polarity = source_value("take_polarity_inverted")
  if polarity == nil then polarity = current_volume < 0 end
  reaper.SetMediaItemTakeInfo_Value(take, "D_VOL", polarity and -math.abs(volume) or math.abs(volume))
  local take_fields = {
    take_pan = "D_PAN",
    take_playback_rate = "D_PLAYRATE",
    take_pitch = "D_PITCH",
    take_channel_mode = "I_CHANMODE",
  }
  for field, parameter in pairs(take_fields) do
    value = source_value(field)
    if value ~= nil then reaper.SetMediaItemTakeInfo_Value(take, parameter, value) end
  end
  return true
end

function M.set_instance_revisions(item, media_revision, publish_revision)
  set_item_string(item, constants.ITEM_KEYS.accepted_media_revision, media_revision)
  set_item_string(item, constants.ITEM_KEYS.handled_publish_revision, publish_revision)
end

function M.set_instance_id(item, instance_id)
  set_item_string(item, constants.ITEM_KEYS.instance_id, instance_id)
end

function M.detach_instance(item)
  M.set_item_clip_id(item, "")
  set_item_string(item, constants.ITEM_KEYS.source_project_id, "")
  set_item_string(item, constants.ITEM_KEYS.instance_id, "")
  set_item_string(item, constants.ITEM_KEYS.accepted_media_revision, "")
  set_item_string(item, constants.ITEM_KEYS.handled_publish_revision, "")
  set_item_string(item, constants.ITEM_KEYS.picture_revision, "")
  M.mark_project_dirty()
  return true
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
