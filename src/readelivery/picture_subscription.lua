local constants = require("readelivery.constants")
local json = require("readelivery.json")
local manifest_validation = require("readelivery.manifest_validation")
local project_guard = require("readelivery.project_guard")

local M = {}

local function cancel_undo(adapter, label)
  if adapter.cancel_undo then adapter.cancel_undo(label) else adapter.end_undo(label) end
end

local function read_json(fs, path, label)
  local bytes, read_error = fs.read_file(path)
  if not bytes then return nil, read_error or ("Could not read " .. label .. ".") end
  local ok, value = pcall(json.decode, bytes)
  if not ok then return nil, label .. " is invalid JSON: " .. tostring(value) end
  if value.schemaVersion ~= 2 then
    return nil, label .. " uses an unsupported schema version."
  end
  return value
end

local function load(fs, pointer_path)
  local pointer, pointer_error = read_json(fs, pointer_path, "picture.json")
  if not pointer then return nil, pointer_error end
  local valid, validation_error = manifest_validation.picture_pointer(pointer)
  if not valid then return nil, validation_error end
  local directory = pointer_path:match("^(.*)[/\\][^/\\]+$")
  if not directory then return nil, "Picture pointer path has no parent directory." end
  local snapshot, snapshot_error = read_json(
    fs,
    fs.join(directory, pointer.manifest),
    "Picture Manifest"
  )
  if not snapshot then return nil, snapshot_error end
  valid, validation_error = manifest_validation.picture_snapshot(snapshot, {
    picture_id = pointer.pictureId,
    revision = pointer.latestPictureRevision,
  })
  if not valid then return nil, validation_error end
  return { pointer = pointer, snapshot = snapshot, directory = directory }
end

local function load_revision(fs, directory, picture_id, revision)
  if revision < 1 then return nil end
  local raw, read_error = read_json(
    fs,
    fs.join(directory, "picture-history", string.format("picture-%04d.json", revision)),
    "previous Master Reference Manifest"
  )
  if not raw then return nil, read_error end
  local valid, validation_error = manifest_validation.picture_snapshot(raw, {
    picture_id = picture_id,
    revision = revision,
  })
  if not valid then return nil, validation_error end
  return raw
end

local function positions(snapshot)
  local result = {}
  local rate = snapshot.timeline.sampleRate
  for _, lane in ipairs(snapshot.lanes or {}) do
    for _, item in ipairs(lane.items or {}) do
      result["item:" .. item.itemId] = {
        item.startSamples / rate,
        (item.startSamples + item.durationSamples) / rate,
      }
    end
  end
  for _, marker in ipairs(snapshot.markers or {}) do
    result["marker:" .. marker.entryId] = { marker.startSamples / rate }
  end
  for _, region in ipairs(snapshot.regions or {}) do
    result["region:" .. region.entryId] = {
      region.startSamples / rate,
      region.endSamples / rate,
    }
  end
  return result
end

local function uniform_timeline_shift(previous, current)
  if not previous or not current then return nil end
  local previous_reference = previous.timeline.referenceStartSamples /
    previous.timeline.sampleRate
  local current_reference = current.timeline.referenceStartSamples /
    current.timeline.sampleRate
  local delta = current_reference - previous_reference
  if math.abs(delta) <= 0.000000001 then return nil end

  local before, after = positions(previous), positions(current)
  local count = 0
  for identity, old_points in pairs(before) do
    local new_points = after[identity]
    if not new_points or #new_points ~= #old_points then return nil end
    for index, old_position in ipairs(old_points) do
      if math.abs((new_points[index] - old_position) - delta) > 0.000001 then
        return nil
      end
    end
    count = count + 1
  end
  for identity in pairs(after) do
    if not before[identity] then return nil end
  end
  if count == 0 then return nil end
  return delta
end

function M.subscribe(adapter, fs, pointer_path)
  if adapter.get_project_value(constants.PROJECT_KEYS.project_mode) ~=
      constants.PROJECT_MODES.source then
    return nil, "Only a Source project can subscribe to Picture."
  end
  local loaded, load_error = load(fs, pointer_path)
  if not loaded then return nil, load_error end

  local existing = adapter.get_project_value(constants.PROJECT_KEYS.picture_id)
  if existing and existing ~= "" and existing ~= loaded.pointer.pictureId then
    return nil, "This Source project is already bound to a different Picture ID."
  end
  adapter.set_project_value(constants.PROJECT_KEYS.picture_manifest_path, pointer_path)
  adapter.set_project_value(constants.PROJECT_KEYS.picture_id, loaded.pointer.pictureId)
  adapter.set_project_value(constants.PROJECT_KEYS.picture_alignment_mode, "mirror")
  adapter.mark_project_dirty()
  return loaded
end

function M.set_alignment_mode(adapter, mode)
  if mode ~= "mirror" and mode ~= "relative" then
    return nil, "Unknown Master Reference alignment mode."
  end
  adapter.set_project_value(constants.PROJECT_KEYS.picture_alignment_mode, mode)
  adapter.mark_project_dirty()
  return { alignment_mode = mode }
end

function M.detach_selected_picture_items(adapter)
  local selected = adapter.selected_items()
  if #selected == 0 then return nil, "Select at least one Picture Item." end
  local detached = 0
  adapter.begin_undo("Detach ReaDelivery Picture Items")
  for _, item in ipairs(selected) do
    local item_id = adapter.get_item_picture_item_id(item)
    if item_id and item_id ~= "" then
      adapter.set_item_picture_item_id(item, "")
      adapter.set_item_picture_id(item, "")
      detached = detached + 1
    end
  end
  adapter.mark_project_dirty()
  adapter.end_undo("Detach ReaDelivery Picture Items")
  return { detached = detached }
end

function M.detach_selected_picture_tracks(adapter)
  local selected = adapter.selected_tracks()
  if #selected == 0 then return nil, "Select at least one Picture Track." end
  local detached = 0
  adapter.begin_undo("Detach ReaDelivery Picture Tracks")
  for _, track in ipairs(selected) do
    local lane_id = adapter.get_track_picture_lane_id(track)
    if lane_id and lane_id ~= "" then
      adapter.set_track_picture_lane_id(track, "")
      adapter.set_track_picture_set_id(track, "")
      detached = detached + 1
    end
  end
  adapter.mark_project_dirty()
  adapter.end_undo("Detach ReaDelivery Picture Tracks")
  return { detached = detached }
end

function M.check(adapter, fs)
  local pointer_path = adapter.get_project_value(constants.PROJECT_KEYS.picture_manifest_path)
  if not pointer_path or pointer_path == "" then
    return nil, "Select picture.json to create a Picture subscription."
  end
  local loaded, load_error = load(fs, pointer_path)
  if not loaded then return nil, load_error end
  local expected_id = adapter.get_project_value(constants.PROJECT_KEYS.picture_id)
  if expected_id and expected_id ~= "" and loaded.pointer.pictureId ~= expected_id then
    return nil, "Subscribed Picture ID changed unexpectedly."
  end

  local available, video_error = true, nil
  for _, lane in ipairs(loaded.snapshot.lanes or {}) do
    for _, item in ipairs(lane.items or {}) do
      local actual_hash = fs.hash_file(item.videoFile)
      local expected_hash = item.videoHash:gsub("^sha256:", "")
      if not actual_hash then
        available = false
        video_error = "Master Reference video is missing or unreadable."
        break
      elseif actual_hash ~= expected_hash then
        available = false
        video_error = "Master Reference video hash does not match its published revision."
        break
      end
    end
    if not available then break end
  end
  local synchronized = tonumber(adapter.get_project_value(
    constants.PROJECT_KEYS.synchronized_picture_revision
  )) or 0
  local previous, previous_error
  if synchronized > 0 then
    previous, previous_error = load_revision(
      fs, loaded.directory, loaded.pointer.pictureId, synchronized
    )
    if not previous then
      return nil, "Could not validate the synchronized Picture history: " ..
        tostring(previous_error)
    end
  end
  local shift_seconds = uniform_timeline_shift(previous, loaded.snapshot) or 0
  return project_guard.bind({
    pointer_path = pointer_path,
    picture_id = loaded.pointer.pictureId,
    latest_revision = loaded.pointer.latestPictureRevision,
    synchronized_revision = synchronized,
    reviewed_revision = tonumber(adapter.get_project_value(
      constants.PROJECT_KEYS.reviewed_picture_revision
    )) or 0,
    available = available,
    video_error = video_error,
    alignment_mode = adapter.get_project_value(
      constants.PROJECT_KEYS.picture_alignment_mode
    ) or "mirror",
    shift_seconds = shift_seconds,
    can_shift_entire_project = shift_seconds ~= 0,
    snapshot = loaded.snapshot,
  }, adapter, false)
end

function M.synchronize(adapter, status, options)
  local current, context_error = project_guard.check(
    status, adapter, "Master Reference synchronization status"
  )
  if not current then return nil, context_error end
  options = options or {}
  if not status.available then return nil, status.video_error end
  local previous_timeline = adapter.timeline_state and adapter.timeline_state() or nil
  local function restore_timeline(original_error)
    if not previous_timeline or not adapter.set_timeline_state then return original_error end
    local restored, restore_error = adapter.set_timeline_state({
      sampleRate = previous_timeline.sample_rate,
      projectTimecodeOffsetSamples = previous_timeline.project_timecode_offset_samples,
      frameRate = {
        numerator = previous_timeline.frame_rate.numerator,
        denominator = previous_timeline.frame_rate.denominator,
        dropFrame = previous_timeline.frame_rate.drop_frame,
      },
    })
    if restored then return original_error end
    return tostring(original_error) .. " Timeline restoration also failed: " ..
      tostring(restore_error)
  end
  adapter.begin_undo("Synchronize ReaDelivery Picture")
  if options.shift_entire_project and status.can_shift_entire_project and
      status.shift_seconds ~= 0 then
    local shifted, shift_error = adapter.shift_entire_project(status.shift_seconds)
    if not shifted then
      cancel_undo(adapter, "Synchronize ReaDelivery Picture")
      return nil, shift_error
    end
  end
  local result, sync_error = adapter.sync_picture(status.snapshot, {
    alignment_mode = status.alignment_mode,
  })
  if not result then
    cancel_undo(adapter, "Synchronize ReaDelivery Picture")
    return nil, restore_timeline(sync_error)
  end
  adapter.set_project_value(
    constants.PROJECT_KEYS.synchronized_picture_revision,
    tostring(status.latest_revision)
  )
  local project_sample_rate = adapter.project_sample_rate()
  local picture_sample_rate = status.snapshot.timeline.sampleRate
  local local_picture_start = math.floor(
    status.snapshot.timeline.referenceStartSamples /
      picture_sample_rate * project_sample_rate + 0.5
  )
  adapter.set_project_value(
    constants.PROJECT_KEYS.picture_start_samples,
    tostring(local_picture_start)
  )
  adapter.set_project_value(
    constants.PROJECT_KEYS.picture_start_sample_rate,
    tostring(project_sample_rate)
  )
  adapter.mark_project_dirty()
  adapter.end_undo("Synchronize ReaDelivery Picture")
  return result
end

function M.mark_reviewed(adapter, status)
  local current, context_error = project_guard.check(
    status, adapter, "Master Reference synchronization status"
  )
  if not current then return nil, context_error end
  local synchronized = tonumber(adapter.get_project_value(
    constants.PROJECT_KEYS.synchronized_picture_revision
  )) or 0
  if synchronized ~= status.latest_revision then
    return nil, "Synchronize the latest Picture revision before marking it reviewed."
  end
  adapter.set_project_value(
    constants.PROJECT_KEYS.reviewed_picture_revision,
    tostring(status.latest_revision)
  )
  adapter.mark_project_dirty()
  return { reviewed_revision = status.latest_revision }
end

return M
