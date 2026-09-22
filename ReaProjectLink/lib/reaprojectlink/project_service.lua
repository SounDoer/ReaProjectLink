local constants = require("reaprojectlink.constants")

local M = {}

local function require_saved_project(adapter)
  local path = adapter.project_path()
  if path == nil or path == "" then
    return nil, "Save the REAPER project before initializing ReaProjectLink."
  end
  return path
end

local function current_type(adapter)
  return adapter.get_project_value(constants.PROJECT_KEYS.project_type)
end

local function initialize(adapter, project_type)
  local path, path_error = require_saved_project(adapter)
  if not path then
    return nil, path_error
  end

  local existing_type = current_type(adapter)
  if existing_type and existing_type ~= "" then
    return nil, "This project is already initialized as " .. existing_type .. "."
  end

  adapter.begin_undo("Initialize ReaProjectLink " .. project_type .. " project")
  adapter.set_project_value(
    constants.PROJECT_KEYS.schema_version,
    constants.PROJECT_SCHEMA_VERSION
  )
  local project_id = adapter.new_id()
  adapter.set_project_value(constants.PROJECT_KEYS.project_type, project_type)
  adapter.set_project_value(constants.PROJECT_KEYS.project_id, project_id)
  adapter.set_project_value(constants.PROJECT_KEYS.project_identity_path, path)

  adapter.mark_project_dirty()
  adapter.end_undo("Initialize ReaProjectLink " .. project_type .. " project")

  return {
    project_type = project_type,
    project_id = project_id,
    path = path,
  }
end

function M.initialize_source(adapter)
  return initialize(adapter, constants.PROJECT_TYPES.source)
end

function M.initialize_master(adapter)
  return initialize(adapter, constants.PROJECT_TYPES.master)
end

function M.reset(adapter)
  local path, path_error = require_saved_project(adapter)
  if not path then
    return nil, path_error
  end

  adapter.begin_undo("Reset ReaProjectLink state")
  local counts = adapter.clear_extension_state()
  adapter.mark_project_dirty()
  adapter.end_undo("Reset ReaProjectLink state")

  return counts
end

function M.project_state(adapter)
  local function revision(key)
    return tonumber(adapter.get_project_value(key)) or 0
  end
  return {
    project_type = current_type(adapter),
    project_id = adapter.get_project_value(constants.PROJECT_KEYS.project_id),
    path = adapter.project_path(),
    reference_id = adapter.get_project_value(constants.PROJECT_KEYS.reference_id),
    reference_manifest_path = adapter.get_project_value(
      constants.PROJECT_KEYS.reference_manifest_path
    ),
    delivery_revision = revision(constants.PROJECT_KEYS.delivery_revision),
    reference_revision = revision(constants.PROJECT_KEYS.reference_revision),
    synchronized_reference_revision = revision(
      constants.PROJECT_KEYS.synchronized_reference_revision
    ),
    reviewed_reference_revision = revision(
      constants.PROJECT_KEYS.reviewed_reference_revision
    ),
  }
end

function M.delivery_tracks(adapter)
  local lanes = {}
  for _, track in ipairs(adapter.all_tracks()) do
    local lane_id = adapter.get_track_lane_id(track)
    if lane_id and lane_id ~= "" then
      table.insert(lanes, {
        lane_id = lane_id,
        display_name = adapter.track_name(track),
        item_count = #adapter.track_items(track),
      })
    end
  end
  return lanes
end

function M.register_selected_tracks(adapter)
  if current_type(adapter) ~= constants.PROJECT_TYPES.source then
    return nil, "Only a Source Project can register Delivery Tracks."
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
    adapter.begin_undo("Register ReaProjectLink Delivery Tracks")
    for _, track in ipairs(pending) do
      adapter.set_track_lane_id(track, adapter.new_id())
    end
    adapter.mark_project_dirty()
    adapter.end_undo("Register ReaProjectLink Delivery Tracks")
  end

  return { selected = #selected, added = #pending }
end

function M.unregister_selected_tracks(adapter)
  if current_type(adapter) ~= constants.PROJECT_TYPES.source then
    return nil, "Only a Source Project can unregister Delivery Tracks."
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
    adapter.begin_undo("Unregister ReaProjectLink Delivery Tracks")
    for _, track in ipairs(pending) do
      adapter.set_track_lane_id(track, "")
    end
    adapter.mark_project_dirty()
    adapter.end_undo("Unregister ReaProjectLink Delivery Tracks")
  end

  return { selected = #selected, removed = #pending }
end

local function scan_item(adapter, item)
  local clip = {
    item_ref = item,
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
  clip.media_sample_rate = media.sample_rate
  clip.channel_count = media.channel_count
  clip.take_fx_count = media.take_fx_count or 0

  local presentation = adapter.item_presentation(item) or {}
  clip.start_offset_samples = presentation.start_offset_samples
  clip.source_offset_samples = presentation.source_offset_samples
  clip.length_samples = presentation.length_samples
  clip.item_gain = presentation.item_gain
  clip.fade_in_samples = presentation.fade_in_samples
  clip.fade_out_samples = presentation.fade_out_samples
  clip.take = presentation.take

  if media.path == nil or media.path == "" then
    table.insert(clip.blockers, "Active Take has no file-backed media")
  elseif not adapter.file_exists(media.path) then
    table.insert(clip.blockers, "Media File Not Found")
  elseif not media.path:lower():match("%.wav$") then
    table.insert(clip.blockers, "Only file-backed WAV media can be published")
  end

  if clip.take_fx_count > 0 then
    table.insert(clip.blockers, "Take FX will not be included; use Publish Unprocessed Media to continue")
  end

  return clip
end

function M.scan(adapter)
  if current_type(adapter) ~= constants.PROJECT_TYPES.source then
    return nil, "Only a Source Project can scan Delivery Tracks."
  end

  local result = {
    lanes = {},
    sample_rate = adapter.project_sample_rate(),
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
        order = #result.lanes,
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
