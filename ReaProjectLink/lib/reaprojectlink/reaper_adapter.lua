local constants = require("reaprojectlink.constants")
local json = require("reaprojectlink.json")

local M = {}

local function project()
  return 0
end

function M.project_path()
  local _, path = reaper.EnumProjects(-1, "")
  return path or ""
end

function M.project_token()
  local current, path = reaper.EnumProjects(-1, "")
  return tostring(current) .. "\31" .. tostring(path or "")
end

function M.project_change_count()
  return reaper.GetProjectStateChangeCount(project())
end

function M.valid_track(track)
  return track and reaper.ValidatePtr2(project(), track, "MediaTrack*") or false
end

function M.valid_item(item)
  return item and reaper.ValidatePtr2(project(), item, "MediaItem*") or false
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

function M.select_items(items)
  reaper.SelectAllMediaItems(project(), false)
  for _, item in ipairs(items) do
    if reaper.ValidatePtr2(project(), item, "MediaItem*") then
      reaper.SetMediaItemSelected(item, true)
    end
  end
  reaper.UpdateArrange()
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

function M.get_track_reference_lane_id(track)
  local _, value = reaper.GetSetMediaTrackInfo_String(
    track, constants.TRACK_KEYS.reference_lane_id, "", false
  )
  return value
end

function M.set_track_reference_lane_id(track, lane_id)
  reaper.GetSetMediaTrackInfo_String(
    track, constants.TRACK_KEYS.reference_lane_id, lane_id or "", true
  )
end

function M.get_track_reference_id(track)
  local _, value = reaper.GetSetMediaTrackInfo_String(
    track, constants.TRACK_KEYS.reference_id, "", false
  )
  return value
end

function M.set_track_reference_id(track, reference_id)
  reaper.GetSetMediaTrackInfo_String(
    track, constants.TRACK_KEYS.reference_id, reference_id or "", true
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

function M.get_item_reference_id(item)
  local _, value = reaper.GetSetMediaItemInfo_String(
    item,
    constants.ITEM_KEYS.reference_id,
    "",
    false
  )
  return value
end

function M.set_item_reference_id(item, reference_id)
  reaper.GetSetMediaItemInfo_String(
    item,
    constants.ITEM_KEYS.reference_id,
    reference_id,
    true
  )
end

function M.get_item_reference_item_id(item)
  local _, value = reaper.GetSetMediaItemInfo_String(
    item, constants.ITEM_KEYS.reference_item_id, "", false
  )
  return value
end

function M.set_item_reference_item_id(item, item_id)
  reaper.GetSetMediaItemInfo_String(
    item, constants.ITEM_KEYS.reference_item_id, tostring(item_id or ""), true
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

function M.create_master_track(name, parent_track)
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

function M.reference_item_state(item)
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
    reference_start_samples = seconds_to_samples(
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

function M.timeline_state()
  local sample_rate = M.project_sample_rate()
  local frame_rate, drop_frame = reaper.TimeMap_curFrameRate(project())
  local numerator, denominator = frame_rate_ratio(frame_rate)
  return {
    sample_rate = sample_rate,
    project_timecode_offset_samples = seconds_to_samples(
      reaper.GetProjectTimeOffset(project(), false), sample_rate
    ),
    frame_rate = {
      numerator = numerator,
      denominator = denominator,
      drop_frame = drop_frame,
    },
  }
end

function M.timeline_entries()
  local result = {}
  local sample_rate = M.project_sample_rate()
  for index = 0, reaper.GetNumRegionsOrMarkers(project()) - 1 do
    local retval, is_region, position, region_end, name, number, color =
      reaper.EnumProjectMarkers3(project(), index)
    if retval and retval > 0 then
      local marker = reaper.GetRegionOrMarker and
        reaper.GetRegionOrMarker(project(), index, "") or nil
      local guid
      local selected = false
      if marker then
        local _, value = reaper.GetSetRegionOrMarkerInfo_String(
          project(), marker, "GUID", "", false
        )
        guid = value
        selected = reaper.GetRegionOrMarkerInfo_Value(
          project(), marker, "B_UISEL"
        ) ~= 0
      end
      table.insert(result, {
        ref = marker,
        guid = guid and guid ~= "" and guid or
          string.format("%s:%d", is_region and "region" or "marker", number),
        kind = is_region and "region" or "marker",
        number = number,
        name = name,
        start_samples = seconds_to_samples(position, sample_rate),
        end_samples = seconds_to_samples(region_end, sample_rate),
        color = color,
        selected = selected,
      })
    end
  end
  return result
end

function M.set_timeline_state(timeline)
  local sample_rate = timeline.sampleRate
  local offset = timeline.projectTimecodeOffsetSamples / sample_rate
  local frame_rate = timeline.frameRate
  local nominal = frame_rate.numerator / frame_rate.denominator
  local base, fractional_mode
  if frame_rate.denominator == 1 then
    base, fractional_mode = frame_rate.numerator, 0
  elseif frame_rate.denominator == 1001 and
      (frame_rate.numerator == 24000 or frame_rate.numerator == 30000 or
       frame_rate.numerator == 60000) then
    base = math.floor(nominal + 0.5)
    fractional_mode = frame_rate.dropFrame and 1 or 2
  else
    return nil, "The Master uses a frame rate that REAPER cannot mirror safely."
  end
  if reaper.set_config_var_string(
      "projtimeoffs", string.format("%.17g", offset), 0
    ) ~= 2 then
    return nil, "REAPER could not mirror the Master project timecode offset."
  end
  if reaper.set_config_var_string("projfrbase", tostring(base), 0) ~= 2 or
      reaper.set_config_var_string("projfrdrop", tostring(fractional_mode), 0) ~= 2 then
    return nil, "REAPER could not mirror the Master frame rate."
  end

  local actual_rate, actual_drop = reaper.TimeMap_curFrameRate(project())
  if math.abs(actual_rate - nominal) > 0.001 or
      not not actual_drop ~= not not frame_rate.dropFrame then
    return nil, "REAPER did not adopt the Master frame rate and drop-frame mode."
  end
  return true
end

function M.shift_entire_project(delta_seconds)
  if delta_seconds == 0 then return true end
  for _, track in ipairs(M.all_tracks()) do
    for _, item in ipairs(M.track_items(track)) do
      reaper.SetMediaItemInfo_Value(
        item, "D_POSITION",
        reaper.GetMediaItemInfo_Value(item, "D_POSITION") + delta_seconds
      )
    end
  end
  local entries = M.timeline_entries()
  for _, entry in ipairs(entries) do
    reaper.SetProjectMarker3(
      project(), entry.number, entry.kind == "region",
      entry.start_samples / M.project_sample_rate() + delta_seconds,
      entry.end_samples / M.project_sample_rate() + delta_seconds,
      entry.name, entry.color
    )
  end
  return true
end

function M.sync_reference(snapshot, options)
  options = options or {}
  local timeline = snapshot.timeline
  local sample_rate = timeline.sampleRate
  if options.alignment_mode ~= "relative" then
    local timeline_set, timeline_error = M.set_timeline_state(timeline)
    if not timeline_set then return nil, timeline_error end
  end

  local existing_tracks, existing_items = {}, {}
  for _, track in ipairs(M.all_tracks()) do
    local lane_id = M.get_track_reference_lane_id(track)
    if lane_id and lane_id ~= "" then
      if existing_tracks[lane_id] then
        return nil, "Duplicate local Reference Track identity; make one Track new before synchronizing."
      end
      existing_tracks[lane_id] = track
    end
    for _, item in ipairs(M.track_items(track)) do
      if M.get_item_reference_id(item) == snapshot.referenceId then
        local item_id = M.get_item_reference_item_id(item)
        if item_id and item_id ~= "" then
          if existing_items[item_id] then
            return nil, "Duplicate local Reference Item identity; make one Item new before synchronizing."
          end
          existing_items[item_id] = { item = item, track = track }
        end
      end
    end
  end

  local expected_lanes, expected_items = {}, {}
  local created_tracks, created_items, updated_items, removed_items = 0, 0, 0, 0
  for _, lane in ipairs(snapshot.lanes or {}) do
    expected_lanes[lane.laneId] = true
    local track = existing_tracks[lane.laneId]
    if not track then
      track = M.create_master_track(lane.displayName)
      M.set_track_reference_lane_id(track, lane.laneId)
      created_tracks = created_tracks + 1
    end
    M.set_track_reference_id(track, snapshot.referenceId)
    for _, published in ipairs(lane.items or {}) do
      expected_items[published.itemId] = true
      local existing = existing_items[published.itemId]
      local item = existing and existing.item or reaper.AddMediaItemToTrack(track)
      if existing and existing.track ~= track then
        reaper.MoveMediaItemToTrack(item, track)
        existing.track = track
      end
      local source = reaper.PCM_Source_CreateFromFile(published.videoFile)
      if not source then return nil, "Cannot Read Media: " .. published.videoFile end
      local take = reaper.GetActiveTake(item)
      if not take then take = reaper.AddTakeToMediaItem(item) end
      local old_source = reaper.GetMediaItemTake_Source(take)
      reaper.SetMediaItemTake_Source(take, source)
      if old_source then reaper.PCM_Source_Destroy(old_source) end
      reaper.SetActiveTake(take)
      local start_seconds = published.startSamples / sample_rate
      if options.alignment_mode == "relative" then
        local local_start = tonumber(M.get_project_value(
          constants.PROJECT_KEYS.reference_start_samples
        )) or 0
        local local_rate = tonumber(M.get_project_value(
          constants.PROJECT_KEYS.reference_start_sample_rate
        )) or M.project_sample_rate()
        start_seconds = local_start / local_rate +
          (published.startSamples - timeline.referenceStartSamples) / sample_rate
      end
      reaper.SetMediaItemInfo_Value(item, "D_POSITION", start_seconds)
      reaper.SetMediaItemInfo_Value(item, "D_LENGTH", published.durationSamples / sample_rate)
      reaper.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", published.sourceOffsetSamples / sample_rate)
      reaper.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", published.playbackRate)
      reaper.GetSetMediaItemTakeInfo_String(take, "P_NAME", published.displayName or "", true)
      M.set_item_reference_id(item, snapshot.referenceId)
      M.set_item_reference_item_id(item, published.itemId)
      if existing then updated_items = updated_items + 1 else created_items = created_items + 1 end
    end
  end

  for item_id, existing in pairs(existing_items) do
    if not expected_items[item_id] then
      reaper.DeleteTrackMediaItem(existing.track, existing.item)
      removed_items = removed_items + 1
    end
  end
  for lane_id, track in pairs(existing_tracks) do
    if not expected_lanes[lane_id] and
        M.get_track_reference_id(track) == snapshot.referenceId then
      M.set_track_reference_lane_id(track, "")
      M.set_track_reference_id(track, "")
    end
  end

  local stored = M.get_project_value(constants.PROJECT_KEYS.reference_timeline_entries)
  local ok, mappings = pcall(json.decode, stored or "")
  if not ok or type(mappings) ~= "table" then mappings = {} end
  local by_id = {}
  for _, mapping in ipairs(mappings) do by_id[mapping.entryId] = mapping end
  local next_mappings = {}
  local function sync_entry(entry, is_region)
    local mapping = by_id[entry.entryId]
    local position = entry.startSamples / sample_rate
    local region_end = is_region and entry.endSamples / sample_rate or 0
    if options.alignment_mode == "relative" then
      local local_start = tonumber(M.get_project_value(
        constants.PROJECT_KEYS.reference_start_samples
      )) or 0
      local local_rate = tonumber(M.get_project_value(
        constants.PROJECT_KEYS.reference_start_sample_rate
      )) or M.project_sample_rate()
      local anchor = local_start / local_rate
      position = anchor + (entry.startSamples - timeline.referenceStartSamples) / sample_rate
      if is_region then
        region_end = anchor + (entry.endSamples - timeline.referenceStartSamples) / sample_rate
      end
    end
    local number = mapping and mapping.number or -1
    local actual = reaper.AddProjectMarker(
      project(), is_region, position, region_end, entry.name or "", number
    )
    if actual < 0 then return nil, "Could not synchronize Marker or Region." end
    reaper.SetProjectMarker3(
      project(), actual, is_region, position, region_end, entry.name or "", entry.color or 0
    )
    table.insert(next_mappings, {
      entryId = entry.entryId,
      kind = is_region and "region" or "marker",
      number = actual,
    })
    return true
  end
  -- Recreate managed entries to avoid relying on display-number ordering.
  for _, mapping in ipairs(mappings) do
    reaper.DeleteProjectMarker(project(), mapping.number, mapping.kind == "region")
  end
  for _, entry in ipairs(snapshot.markers or {}) do
    local synced, err = sync_entry(entry, false); if not synced then return nil, err end
  end
  for _, entry in ipairs(snapshot.regions or {}) do
    local synced, err = sync_entry(entry, true); if not synced then return nil, err end
  end
  M.set_project_value(constants.PROJECT_KEYS.reference_timeline_entries, json.encode(next_mappings))
  reaper.UpdateArrange()
  return {
    created_tracks = created_tracks,
    created_items = created_items,
    updated_items = updated_items,
    removed_items = removed_items,
  }
end

local function set_item_string(item, key, value)
  reaper.GetSetMediaItemInfo_String(item, key, tostring(value or ""), true)
end

local function get_item_string(item, key)
  local _, value = reaper.GetSetMediaItemInfo_String(item, key, "", false)
  return value
end

local function build_item_peaks(take, item)
  reaper.UpdateItemInProject(item)
  if not reaper.PCM_Source_BuildPeaks then
    reaper.UpdateArrange()
    return
  end

  local source = reaper.GetMediaItemTake_Source(take)
  if not source then
    reaper.UpdateArrange()
    return
  end
  local remaining = reaper.PCM_Source_BuildPeaks(source, 0)
  if remaining == 0 then
    reaper.UpdateArrange()
    return
  end

  reaper.UpdateArrange()
  local function continue_building()
    if not reaper.ValidatePtr2(project(), item, "MediaItem*") or
        not reaper.ValidatePtr2(project(), take, "MediaItem_Take*") then
      return
    end
    if reaper.GetMediaItemTake_Source(take) ~= source then return end
    remaining = reaper.PCM_Source_BuildPeaks(source, 1)
    if remaining > 0 then
      reaper.defer(continue_building)
      return
    end
    reaper.PCM_Source_BuildPeaks(source, 2)
    reaper.UpdateItemInProject(item)
    reaper.UpdateArrange()
  end
  reaper.defer(continue_building)
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
  set_item_string(item, constants.ITEM_KEYS.lane_id, context.lane_id)
  set_item_string(item, constants.ITEM_KEYS.reference_revision, context.reference_revision)
  build_item_peaks(take, item)
  return item
end

local function current_instance_state(item, reference_start_seconds)
  local take = reaper.GetActiveTake(item)
  if not take then return nil end
  local take_volume = reaper.GetMediaItemTakeInfo_Value(take, "D_VOL")
  return {
    position_seconds = reaper.GetMediaItemInfo_Value(item, "D_POSITION") -
      reference_start_seconds,
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

function M.delivery_instance_state(item)
  local sample_rate = M.project_sample_rate()
  local reference_start_samples = tonumber(M.get_project_value(
    constants.PROJECT_KEYS.reference_start_samples
  )) or 0
  local reference_start_sample_rate = tonumber(M.get_project_value(
    constants.PROJECT_KEYS.reference_start_sample_rate
  )) or sample_rate
  return current_instance_state(
    item,
    reference_start_samples / reference_start_sample_rate
  )
end

function M.delivery_instances(source_project_id)
  local instances = {}
  local sample_rate = M.project_sample_rate()
  local reference_start_samples = tonumber(M.get_project_value(
    constants.PROJECT_KEYS.reference_start_samples
  )) or 0
  local reference_start_sample_rate = tonumber(M.get_project_value(
    constants.PROJECT_KEYS.reference_start_sample_rate
  )) or sample_rate
  local reference_start_seconds = reference_start_samples / reference_start_sample_rate
  for _, track in ipairs(M.all_tracks()) do
    for _, item in ipairs(M.track_items(track)) do
      if get_item_string(item, constants.ITEM_KEYS.source_project_id) == source_project_id then
        table.insert(instances, {
          item_ref = item,
          track_ref = track,
          clip_id = M.get_item_clip_id(item),
          lane_id = get_item_string(item, constants.ITEM_KEYS.lane_id),
          state = current_instance_state(item, reference_start_seconds),
        })
      end
    end
  end
  return instances
end

function M.is_linked_item(item)
  local source_project_id = get_item_string(
    item,
    constants.ITEM_KEYS.source_project_id
  )
  return source_project_id ~= nil and source_project_id ~= ""
end

function M.detach_instance(item)
  if not M.is_linked_item(item) then
    return nil, "Selected Item is not a synchronized Item."
  end
  M.set_item_clip_id(item, "")
  set_item_string(item, constants.ITEM_KEYS.source_project_id, "")
  set_item_string(item, constants.ITEM_KEYS.lane_id, "")
  set_item_string(item, constants.ITEM_KEYS.reference_revision, "")
  M.mark_project_dirty()
  return true
end

function M.delete_linked_item(item)
  if not M.is_linked_item(item) then
    return nil, "Selected Item is not a synchronized Item."
  end
  local track = reaper.GetMediaItem_Track(item)
  if not track or not reaper.DeleteTrackMediaItem(track, item) then
    return nil, "Could not delete the synchronized Item."
  end
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
  if reaper.IsProjectDirty and reaper.IsProjectDirty(project()) ~= 0 then
    return nil, "REAPER project is still dirty after Save."
  end
  local path = M.project_path()
  if path == "" or not reaper.file_exists(path) then
    return nil, "REAPER project file was not written."
  end
  return true
end

function M.cancel_undo(label)
  reaper.Undo_EndBlock2(project(), label, -1)
  reaper.Undo_DoUndo2(project())
end

function M.clear_extension_state()
  local counts = { tracks = 0, items = 0 }
  for _, track in ipairs(M.all_tracks()) do
    local had_value = false
    for _, key in pairs(constants.TRACK_KEYS) do
      local _, value = reaper.GetSetMediaTrackInfo_String(track, key, "", false)
      if value and value ~= "" then had_value = true end
      reaper.GetSetMediaTrackInfo_String(track, key, "", true)
    end
    if had_value then counts.tracks = counts.tracks + 1 end

    for _, item in ipairs(M.track_items(track)) do
      local item_had_value = false
      for _, key in pairs(constants.ITEM_KEYS) do
        local _, value = reaper.GetSetMediaItemInfo_String(item, key, "", false)
        if value and value ~= "" then item_had_value = true end
        reaper.GetSetMediaItemInfo_String(item, key, "", true)
      end
      if item_had_value then counts.items = counts.items + 1 end
    end
  end

  reaper.SetProjExtState(project(), constants.EXTENSION_NAME, "", "")

  return counts
end

return M
