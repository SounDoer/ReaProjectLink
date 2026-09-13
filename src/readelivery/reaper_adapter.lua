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
    take_fx_count = reaper.TakeFX_GetCount(take),
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

return M
