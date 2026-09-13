local constants = require("readelivery.constants")

local M = {}

local function require_saved_project(adapter)
  local path = adapter.project_path()
  if path == nil or path == "" then
    return nil, "Save the REAPER project before initializing ReaDelivery."
  end
  return path
end

local function current_mode(adapter)
  return adapter.get_project_value(constants.PROJECT_KEYS.project_mode)
end

local function initialize(adapter, mode)
  local path, path_error = require_saved_project(adapter)
  if not path then
    return nil, path_error
  end

  local existing_mode = current_mode(adapter)
  if existing_mode and existing_mode ~= "" then
    return nil, "This project is already initialized as " .. existing_mode .. "."
  end

  adapter.begin_undo("Initialize ReaDelivery " .. mode .. " project")
  adapter.set_project_value(
    constants.PROJECT_KEYS.schema_version,
    constants.PROJECT_SCHEMA_VERSION
  )
  adapter.set_project_value(constants.PROJECT_KEYS.project_mode, mode)

  adapter.mark_project_dirty()
  adapter.end_undo("Initialize ReaDelivery " .. mode .. " project")

  return {
    mode = mode,
    path = path,
  }
end

function M.ensure_source_project_id(adapter)
  if current_mode(adapter) ~= constants.PROJECT_MODES.source then
    return nil, "Only a Source project can have a Source Project ID."
  end

  local source_project_id = adapter.get_project_value(
    constants.PROJECT_KEYS.source_project_id
  )
  if source_project_id and source_project_id ~= "" then
    return source_project_id, false
  end

  source_project_id = adapter.new_id()
  adapter.set_project_value(
    constants.PROJECT_KEYS.source_project_id,
    source_project_id
  )
  adapter.mark_project_dirty()
  return source_project_id, true
end

function M.initialize_source(adapter)
  return initialize(adapter, constants.PROJECT_MODES.source)
end

function M.initialize_mix(adapter)
  return initialize(adapter, constants.PROJECT_MODES.mix)
end

function M.project_state(adapter)
  return {
    mode = current_mode(adapter),
    source_project_id = adapter.get_project_value(
      constants.PROJECT_KEYS.source_project_id
    ),
    path = adapter.project_path(),
  }
end

function M.register_selected_tracks(adapter)
  if current_mode(adapter) ~= constants.PROJECT_MODES.source then
    return nil, "Only a Source project can register Delivery Tracks."
  end

  local selected = adapter.selected_tracks()
  if #selected == 0 then
    return nil, "Select at least one Track."
  end

  local pending = {}
  for _, track in ipairs(selected) do
    local lane_id = adapter.get_track_lane_id(track)
    if lane_id == nil or lane_id == "" then
      table.insert(pending, track)
    end
  end

  if #pending > 0 then
    adapter.begin_undo("Register ReaDelivery Delivery Tracks")
    for _, track in ipairs(pending) do
      adapter.set_track_lane_id(track, adapter.new_id())
    end
    adapter.mark_project_dirty()
    adapter.end_undo("Register ReaDelivery Delivery Tracks")
  end

  return { selected = #selected, added = #pending }
end

function M.unregister_selected_tracks(adapter)
  if current_mode(adapter) ~= constants.PROJECT_MODES.source then
    return nil, "Only a Source project can remove Delivery Tracks."
  end

  local selected = adapter.selected_tracks()
  if #selected == 0 then
    return nil, "Select at least one Track."
  end

  local pending = {}
  for _, track in ipairs(selected) do
    local lane_id = adapter.get_track_lane_id(track)
    if lane_id and lane_id ~= "" then
      table.insert(pending, track)
    end
  end

  if #pending > 0 then
    adapter.begin_undo("Remove ReaDelivery Delivery Tracks")
    for _, track in ipairs(pending) do
      adapter.set_track_lane_id(track, "")
    end
    adapter.mark_project_dirty()
    adapter.end_undo("Remove ReaDelivery Delivery Tracks")
  end

  return { selected = #selected, removed = #pending }
end

local function scan_item(adapter, item)
  local clip = {
    clip_id = adapter.get_item_clip_id(item),
    display_name = adapter.item_display_name(item),
    blockers = {},
  }

  local media = adapter.active_take_media(item)
  if not media then
    table.insert(clip.blockers, "No active audio Take")
    return clip
  end

  clip.media_path = media.path
  clip.take_fx_count = media.take_fx_count or 0

  if media.path == nil or media.path == "" then
    table.insert(clip.blockers, "Active Take has no file-backed media")
  elseif not adapter.file_exists(media.path) then
    table.insert(clip.blockers, "Active Take media is missing or offline")
  end

  if clip.take_fx_count > 0 then
    table.insert(clip.blockers, "Take FX requires Publish Anyway")
  end

  return clip
end

function M.scan(adapter)
  if current_mode(adapter) ~= constants.PROJECT_MODES.source then
    return nil, "Only a Source project can scan Delivery Tracks."
  end

  local result = {
    lanes = {},
    clip_count = 0,
    blocker_count = 0,
    untagged_count = 0,
  }

  for _, track in ipairs(adapter.all_tracks()) do
    local lane_id = adapter.get_track_lane_id(track)
    if lane_id and lane_id ~= "" then
      local lane = {
        lane_id = lane_id,
        display_name = adapter.track_name(track),
        track_fx_count = adapter.track_fx_count(track),
        clips = {},
      }

      if lane.track_fx_count > 0 then
        result.blocker_count = result.blocker_count + 1
      end

      for _, item in ipairs(adapter.track_items(track)) do
        local clip = scan_item(adapter, item)
        table.insert(lane.clips, clip)
        result.clip_count = result.clip_count + 1
        result.blocker_count = result.blocker_count + #clip.blockers
        if clip.clip_id == nil or clip.clip_id == "" then
          result.untagged_count = result.untagged_count + 1
        end
      end

      table.insert(result.lanes, lane)
    end
  end

  return result
end

return M
