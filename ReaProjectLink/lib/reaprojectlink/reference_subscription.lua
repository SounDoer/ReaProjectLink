local constants = require("reaprojectlink.constants")
local manifest_validation = require("reaprojectlink.manifest_validation")
local project_guard = require("reaprojectlink.project_guard")
local manifest_file = require("reaprojectlink.manifest_file")

local M = {}

local function load(fs, pointer_path)
  local pointer, pointer_error = manifest_file.read(fs, pointer_path, "reference.json", 2)
  if not pointer then return nil, pointer_error end
  local valid, validation_error = manifest_validation.reference_pointer(pointer)
  if not valid then return nil, validation_error end
  local directory = pointer_path:match("^(.*)[/\\][^/\\]+$")
  if not directory then return nil, "Reference pointer path has no parent directory." end
  local snapshot, snapshot_error = manifest_file.read(
    fs,
    fs.join(directory, pointer.manifest),
    "Reference Manifest",
    2
  )
  if not snapshot then return nil, snapshot_error end
  valid, validation_error = manifest_validation.reference_snapshot(snapshot, {
    master_project_id = pointer.masterProjectId,
    reference_id = pointer.referenceId,
    revision = pointer.latestReferenceRevision,
  })
  if not valid then return nil, validation_error end
  return { pointer = pointer, snapshot = snapshot, directory = directory }
end

local function load_revision(fs, directory, master_project_id, reference_id, revision)
  if revision < 1 then return nil end
  local raw, read_error = manifest_file.read(
    fs,
    fs.join(directory, "history", string.format("reference-%04d.json", revision)),
    "previous Reference Manifest",
    2
  )
  if not raw then return nil, read_error end
  local valid, validation_error = manifest_validation.reference_snapshot(raw, {
    master_project_id = master_project_id,
    reference_id = reference_id,
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
  if adapter.get_project_value(constants.PROJECT_KEYS.project_type) ~=
      constants.PROJECT_TYPES.source then
    return nil, "Only a Source Project can subscribe to a Reference."
  end
  local loaded, load_error = load(fs, pointer_path)
  if not loaded then return nil, load_error end

  local existing = adapter.get_project_value(constants.PROJECT_KEYS.reference_id)
  if existing and existing ~= "" and existing ~= loaded.pointer.referenceId then
    return nil, "This Source Project is already subscribed to a different Reference ID."
  end
  local existing_master = adapter.get_project_value(
    constants.PROJECT_KEYS.reference_master_project_id
  )
  if existing_master and existing_master ~= "" and
      existing_master ~= loaded.pointer.masterProjectId then
    return nil, "This Source Project is already subscribed to a different Master Project."
  end
  adapter.set_project_value(constants.PROJECT_KEYS.reference_manifest_path, pointer_path)
  adapter.set_project_value(constants.PROJECT_KEYS.reference_master_project_id,
    loaded.pointer.masterProjectId)
  adapter.set_project_value(constants.PROJECT_KEYS.reference_id, loaded.pointer.referenceId)
  adapter.set_project_value(constants.PROJECT_KEYS.reference_alignment_mode, "mirror")
  adapter.mark_project_dirty()
  return loaded
end

function M.set_alignment_mode(adapter, mode)
  if mode ~= "mirror" and mode ~= "relative" then
    return nil, "Unknown Reference alignment mode."
  end
  adapter.set_project_value(constants.PROJECT_KEYS.reference_alignment_mode, mode)
  adapter.mark_project_dirty()
  return { alignment_mode = mode }
end

function M.detach_selected_reference_items(adapter)
  local selected = adapter.selected_items()
  if #selected == 0 then return nil, "Select at least one Reference Item." end
  local detached = 0
  adapter.begin_undo("Detach ReaProjectLink Reference Items")
  for _, item in ipairs(selected) do
    local item_id = adapter.get_item_reference_item_id(item)
    if item_id and item_id ~= "" then
      adapter.set_item_reference_item_id(item, "")
      adapter.set_item_reference_id(item, "")
      detached = detached + 1
    end
  end
  adapter.mark_project_dirty()
  adapter.end_undo("Detach ReaProjectLink Reference Items")
  return { detached = detached }
end

function M.detach_selected_reference_tracks(adapter)
  local selected = adapter.selected_tracks()
  if #selected == 0 then return nil, "Select at least one Reference Track." end
  local detached = 0
  adapter.begin_undo("Detach ReaProjectLink Reference Tracks")
  for _, track in ipairs(selected) do
    local lane_id = adapter.get_track_reference_lane_id(track)
    if lane_id and lane_id ~= "" then
      adapter.set_track_reference_lane_id(track, "")
      adapter.set_track_reference_id(track, "")
      detached = detached + 1
    end
  end
  adapter.mark_project_dirty()
  adapter.end_undo("Detach ReaProjectLink Reference Tracks")
  return { detached = detached }
end

function M.check(adapter, fs)
  local pointer_path = adapter.get_project_value(constants.PROJECT_KEYS.reference_manifest_path)
  if not pointer_path or pointer_path == "" then
    return nil, "Select reference.json to create a Reference subscription."
  end
  local loaded, load_error = load(fs, pointer_path)
  if not loaded then return nil, load_error end
  local expected_id = adapter.get_project_value(constants.PROJECT_KEYS.reference_id)
  if expected_id and expected_id ~= "" and loaded.pointer.referenceId ~= expected_id then
    return nil, "Subscribed Reference ID changed unexpectedly."
  end
  local expected_master_id = adapter.get_project_value(
    constants.PROJECT_KEYS.reference_master_project_id
  )
  if expected_master_id and expected_master_id ~= "" and
      loaded.pointer.masterProjectId ~= expected_master_id then
    return nil, "Subscribed Master Project ID changed unexpectedly."
  end

  local available, video_error = true, nil
  for _, lane in ipairs(loaded.snapshot.lanes or {}) do
    for _, item in ipairs(lane.items or {}) do
      local actual_hash = fs.hash_file(item.videoFile)
      local expected_hash = item.videoHash:gsub("^sha256:", "")
      if not actual_hash then
        available = false
        video_error = "Reference media cannot be read."
        break
      elseif actual_hash ~= expected_hash then
        available = false
        video_error = "Reference media content does not match the published Reference Revision."
        break
      end
    end
    if not available then break end
  end
  local synchronized = tonumber(adapter.get_project_value(
    constants.PROJECT_KEYS.synchronized_reference_revision
  )) or 0
  local previous, previous_error
  if synchronized > 0 then
    previous, previous_error = load_revision(
      fs, loaded.directory, loaded.pointer.masterProjectId,
      loaded.pointer.referenceId, synchronized
    )
    if not previous then
      return nil, "Could not validate the synchronized Reference history: " ..
        tostring(previous_error)
    end
  end
  local shift_seconds = uniform_timeline_shift(previous, loaded.snapshot) or 0
  return project_guard.bind({
    pointer_path = pointer_path,
    reference_id = loaded.pointer.referenceId,
    latest_revision = loaded.pointer.latestReferenceRevision,
    synchronized_revision = synchronized,
    reviewed_revision = tonumber(adapter.get_project_value(
      constants.PROJECT_KEYS.reviewed_reference_revision
    )) or 0,
    available = available,
    video_error = video_error,
    alignment_mode = adapter.get_project_value(
      constants.PROJECT_KEYS.reference_alignment_mode
    ) or "mirror",
    shift_seconds = shift_seconds,
    can_shift_entire_project = shift_seconds ~= 0,
    snapshot = loaded.snapshot,
  }, adapter, false)
end

-- Reads only reference.json. The third return value classifies a failure as
-- "unsubscribed", "unreachable", or "invalid" for the main panel.
function M.peek(adapter, fs)
  local pointer_path = adapter.get_project_value(constants.PROJECT_KEYS.reference_manifest_path)
  if not pointer_path or pointer_path == "" then
    return nil, "No Reference subscription.", "unsubscribed"
  end
  if not fs.exists(pointer_path) then
    return nil, "Couldn't reach shared storage.", "unreachable"
  end
  local pointer, pointer_error = manifest_file.read(fs, pointer_path, "reference.json", 2)
  if not pointer then return nil, pointer_error, "invalid" end
  local valid, validation_error = manifest_validation.reference_pointer(pointer)
  if not valid then return nil, validation_error, "invalid" end
  local expected_id = adapter.get_project_value(constants.PROJECT_KEYS.reference_id)
  if expected_id and expected_id ~= "" and pointer.referenceId ~= expected_id then
    return nil, "Subscribed Reference ID changed unexpectedly.", "invalid"
  end
  return { latest_revision = pointer.latestReferenceRevision }
end

function M.synchronize(adapter, status, options)
  local current, context_error = project_guard.check(
    status, adapter, "Reference Update Review"
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
  adapter.begin_undo("Synchronize ReaProjectLink Reference")
  if options.shift_entire_project and status.can_shift_entire_project and
      status.shift_seconds ~= 0 then
    local shifted, shift_error = adapter.shift_entire_project(status.shift_seconds)
    if not shifted then
      project_guard.cancel_undo(adapter, "Synchronize ReaProjectLink Reference")
      return nil, shift_error
    end
  end
  local result, sync_error = adapter.sync_reference(status.snapshot, {
    alignment_mode = status.alignment_mode,
  })
  if not result then
    project_guard.cancel_undo(adapter, "Synchronize ReaProjectLink Reference")
    return nil, restore_timeline(sync_error)
  end
  adapter.set_project_value(
    constants.PROJECT_KEYS.synchronized_reference_revision,
    tostring(status.latest_revision)
  )
  local project_sample_rate = adapter.project_sample_rate()
  local reference_sample_rate = status.snapshot.timeline.sampleRate
  local local_reference_start = math.floor(
    status.snapshot.timeline.referenceStartSamples /
      reference_sample_rate * project_sample_rate + 0.5
  )
  adapter.set_project_value(
    constants.PROJECT_KEYS.reference_start_samples,
    tostring(local_reference_start)
  )
  adapter.set_project_value(
    constants.PROJECT_KEYS.reference_start_sample_rate,
    tostring(project_sample_rate)
  )
  adapter.mark_project_dirty()
  adapter.end_undo("Synchronize ReaProjectLink Reference")
  return result
end


return M
