local constants = require("reaprojectlink.constants")
local json = require("reaprojectlink.json")
local manifest_validation = require("reaprojectlink.manifest_validation")
local project_guard = require("reaprojectlink.project_guard")
local track_suggestions = require("reaprojectlink.track_suggestions")

local M = {}

local function cancel_undo(adapter, label)
  if adapter.cancel_undo then adapter.cancel_undo(label) else adapter.end_undo(label) end
end

local function read_json(fs, path, label)
  local bytes, read_error = fs.read_file(path)
  if not bytes then return nil, read_error or ("Could not read " .. label .. ".") end
  local ok, value = pcall(json.decode, bytes)
  if not ok then return nil, label .. " is invalid JSON: " .. tostring(value) end
  if value.schemaVersion ~= 1 then return nil, label .. " uses an unsupported schema version." end
  return value
end

local function find_subscription(subscriptions, source_project_id)
  for index, subscription in ipairs(subscriptions) do
    if subscription.sourceProjectId == source_project_id then return subscription, index end
  end
end

local function checked_clip(fs, package_root, lane, clip)
  local media_path, media_error = manifest_validation.delivery_media_path(
    fs, package_root, clip.mediaFile
  )
  if not media_path then return nil, media_error end
  local digest = fs.hash_file(media_path)
  local blocked = digest ~= clip.mediaHash:gsub("^sha256:", "")
  return {
    lane_id = lane.laneId,
    lane_display_name = lane.displayName,
    clip = clip,
    media_path = media_path,
    blocked = blocked,
    error = blocked and (digest and "Managed WAV hash mismatch." or
      "Managed WAV is missing or unreadable.") or nil,
  }
end

function M.review(adapter, fs, source_project_id, target_revision)
  local stored = adapter.get_project_value(constants.PROJECT_KEYS.delivery_subscriptions)
  if not stored or stored == "" then return nil, "Master Project has no Delivery Subscriptions." end
  local ok, subscriptions = pcall(json.decode, stored)
  if not ok then return nil, "Stored Delivery subscriptions are invalid." end
  local subscription, subscription_index = find_subscription(subscriptions, source_project_id)
  if not subscription then return nil, "Delivery subscription was not found." end

  local pointer, pointer_error = read_json(fs, subscription.pointerPath, "delivery.json")
  if not pointer then return nil, pointer_error end
  local valid, validation_error = manifest_validation.delivery_pointer(pointer)
  if not valid then return nil, validation_error end
  if pointer.sourceProjectId ~= subscription.sourceProjectId or
      pointer.deliveryId ~= subscription.deliveryId then
    return nil, "Subscribed Source or Delivery identity changed."
  end

  local package_root = subscription.pointerPath:match("^(.*)[/\\][^/\\]+$")
  local latest_revision = pointer.latestDeliveryRevision
  local target = tonumber(target_revision) or latest_revision
  if target < 1 or target > latest_revision then
    return nil, "Requested Delivery revision was never published."
  end
  local target_path = target == latest_revision and
    fs.join(package_root, pointer.manifest) or
    fs.join(package_root, string.format("history/delivery-%04d.json", target))
  local snapshot, snapshot_error = read_json(fs, target_path, "target Delivery Manifest")
  if not snapshot then return nil, snapshot_error end
  valid, validation_error = manifest_validation.delivery_snapshot(snapshot, {
    source_project_id = subscription.sourceProjectId,
    delivery_id = subscription.deliveryId,
    revision = target,
  })
  if not valid then return nil, validation_error end

  local lane_bindings = {}
  for _, binding in ipairs(subscription.lanes or {}) do lane_bindings[binding.laneId] = binding end
  local result = {
    source_project_id = source_project_id,
    subscription_index = subscription_index,
    subscriptions = subscriptions,
    subscription = subscription,
    latest_revision = latest_revision,
    target_revision = target,
    target_snapshot = snapshot,
    instances = adapter.delivery_instances(source_project_id),
    additions = {},
    unmapped_lanes = {},
    bound_lanes = {},
    blocker_count = 0,
    reference_warning = tonumber(adapter.get_project_value(
      constants.PROJECT_KEYS.reference_revision
    )) ~= snapshot.reference.reviewedRevision,
    reference_context = {
      reference_id = adapter.get_project_value(constants.PROJECT_KEYS.reference_id),
      reference_revision = tonumber(adapter.get_project_value(
        constants.PROJECT_KEYS.reference_revision
      )) or 0,
      reference_start_samples = adapter.get_project_value(constants.PROJECT_KEYS.reference_start_samples),
      reference_start_sample_rate = adapter.get_project_value(constants.PROJECT_KEYS.reference_start_sample_rate),
    },
  }
  if result.reference_context.reference_id ~= snapshot.reference.referenceId then
    result.blocker_count = result.blocker_count + 1
    result.reference_error = "Targeted Source delivery references a different Reference ID."
  end

  local master_tracks = adapter.all_tracks()
  local clip_count = 0
  for _, lane in ipairs(snapshot.lanes or {}) do
    local binding = lane_bindings[lane.laneId]
    local bound_track = binding and binding.trackGuid and
      adapter.track_by_guid(binding.trackGuid) or nil
    local orphaned = binding and binding.trackGuid and not bound_track or false
    if not binding or binding.unmapped or orphaned then
      local unmapped = {
        lane_id = lane.laneId,
        display_name = lane.displayName,
        orphaned = orphaned,
        clips = {},
        suggestions = track_suggestions.for_lane(adapter, master_tracks, lane.displayName),
      }
      for _, clip in ipairs(lane.clips or {}) do
        local checked, check_error = checked_clip(fs, package_root, lane, clip)
        if not checked then return nil, check_error end
        if checked.blocked then result.blocker_count = result.blocker_count + 1 end
        table.insert(unmapped.clips, checked)
        clip_count = clip_count + 1
      end
      table.insert(result.unmapped_lanes, unmapped)
    else
      table.insert(result.bound_lanes, {
        lane_id = lane.laneId,
        display_name = lane.displayName,
        track_guid = binding.trackGuid,
        track_name = adapter.track_name(bound_track),
      })
      for _, clip in ipairs(lane.clips or {}) do
        local checked, check_error = checked_clip(fs, package_root, lane, clip)
        if not checked then return nil, check_error end
        checked.track_guid = binding.trackGuid
        if checked.blocked then result.blocker_count = result.blocker_count + 1 end
        table.insert(result.additions, checked)
        clip_count = clip_count + 1
      end
    end
  end

  result.replacement_count = #result.instances
  result.source_item_count = clip_count
  -- Resynchronizing the currently handled revision is intentional: it restores
  -- Source-owned Items that the Master user previously detached or removed.
  result.pending_count = result.replacement_count + clip_count + #result.unmapped_lanes
  return project_guard.bind(result, adapter, false)
end

function M.apply(review, adapter, options)
  local current, context_error = project_guard.check(review, adapter, "Update Review")
  if not current then return nil, context_error end
  options = options or {}
  local lane_mappings = options.lane_mappings or {}
  local rebindings = options.lane_rebindings or {}
  if review.pending_count == 0 and next(rebindings) == nil then return nil, "Nothing to synchronize." end
  if review.blocker_count > 0 then return nil, "Update Review has blockers." end

  local reference_context = review.reference_context or {}
  if adapter.get_project_value(constants.PROJECT_KEYS.reference_id) ~= reference_context.reference_id or
      (tonumber(adapter.get_project_value(constants.PROJECT_KEYS.reference_revision)) or 0) ~= reference_context.reference_revision or
      adapter.get_project_value(constants.PROJECT_KEYS.reference_start_samples) ~= reference_context.reference_start_samples or
      adapter.get_project_value(constants.PROJECT_KEYS.reference_start_sample_rate) ~= reference_context.reference_start_sample_rate then
    return nil, "Reference state changed after Delivery Update Review. Refresh the Review first."
  end
  if review.reference_warning and not options.allow_reference_revision_mismatch then
    return nil, "Source was reviewed against a different Reference revision."
  end
  for _, lane in ipairs(review.unmapped_lanes) do
    if not lane_mappings[lane.lane_id] then
      return nil, "Every new Delivery Lane requires a mapping decision."
    end
  end
  if adapter.valid_item then
    for _, instance in ipairs(review.instances) do
      if not adapter.valid_item(instance.item_ref) then
        return nil, "A synchronized Item belongs to a different or closed REAPER project."
      end
      if adapter.delivery_instance_state and
          json.encode(adapter.delivery_instance_state(instance.item_ref)) ~= json.encode(instance.state) then
        return nil, "A synchronized Item changed after Update Review. Refresh the Review first."
      end
    end
  end
  if adapter.valid_track then
    for _, mapping in pairs(lane_mappings) do
      if (mapping.track_ref and not adapter.valid_track(mapping.track_ref)) or
          (mapping.parent_track_ref and not adapter.valid_track(mapping.parent_track_ref)) then
        return nil, "A mapped Track belongs to a different or closed REAPER project."
      end
    end
    for _, track in pairs(rebindings) do
      if not adapter.valid_track(track) then
        return nil, "A rebound Track belongs to a different or closed REAPER project."
      end
    end
  end

  local subscriptions = json.decode(json.encode(review.subscriptions))
  local subscription = subscriptions[review.subscription_index]
  local result = { new_items = 0, new_tracks = 0, deleted_items = 0, rebound_lanes = 0 }
  local label = "Synchronize ReaProjectLink Delivery"
  adapter.begin_undo(label)

  for _, instance in ipairs(review.instances) do
    local deleted, delete_error = adapter.delete_linked_item(instance.item_ref)
    if not deleted then cancel_undo(adapter, label); return nil, delete_error end
    result.deleted_items = result.deleted_items + 1
  end

  local reference_start = tonumber(adapter.get_project_value(
    constants.PROJECT_KEYS.reference_start_samples
  )) or 0
  local reference_start_sample_rate = tonumber(adapter.get_project_value(
    constants.PROJECT_KEYS.reference_start_sample_rate
  )) or adapter.project_sample_rate()
  local function import_clip(track, entry)
    local copy = {}
    for key, value in pairs(entry.clip) do copy[key] = value end
    copy.media_path = entry.media_path
    local item, item_error = adapter.create_delivery_item(track, copy, {
      position_seconds = reference_start / reference_start_sample_rate +
        entry.clip.startOffsetSamples / review.target_snapshot.sampleRate,
      source_project_id = review.source_project_id,
      lane_id = entry.lane_id,
      delivery_revision = review.target_revision,
      reference_revision = review.target_snapshot.reference.reviewedRevision,
      source_sample_rate = review.target_snapshot.sampleRate,
    })
    if not item then return nil, item_error end
    result.new_items = result.new_items + 1
    return item
  end

  for _, entry in ipairs(review.additions) do
    local track = rebindings[entry.lane_id] or adapter.track_by_guid(entry.track_guid)
    if not track then cancel_undo(adapter, label); return nil, "Target Track Missing." end
    local item, item_error = import_clip(track, entry)
    if not item then cancel_undo(adapter, label); return nil, item_error end
  end

  for _, lane in ipairs(review.unmapped_lanes) do
    local mapping = lane_mappings[lane.lane_id]
    local binding
    for _, candidate in ipairs(subscription.lanes or {}) do
      if candidate.laneId == lane.lane_id then binding = candidate end
    end
    if not binding then binding = { laneId = lane.lane_id }; table.insert(subscription.lanes, binding) end
    if mapping.kind == "unmapped" then
      binding.unmapped, binding.trackGuid = true, nil
    else
      local track = mapping.track_ref
      if mapping.kind == "create" then
        track = adapter.create_master_track(lane.display_name, mapping.parent_track_ref)
        result.new_tracks = result.new_tracks + 1
      elseif mapping.kind ~= "existing" then
        cancel_undo(adapter, label); return nil, "Unknown Lane mapping decision."
      end
      if not track then cancel_undo(adapter, label); return nil, "Mapped Track is unavailable." end
      binding.unmapped, binding.trackGuid = nil, adapter.track_guid(track)
      for _, entry in ipairs(lane.clips) do
        local item, item_error = import_clip(track, entry)
        if not item then cancel_undo(adapter, label); return nil, item_error end
      end
    end
  end

  for lane_id, track in pairs(rebindings) do
    local binding
    for _, candidate in ipairs(subscription.lanes or {}) do
      if candidate.laneId == lane_id then binding = candidate end
    end
    if not binding or not track then cancel_undo(adapter, label); return nil, "Target Track Missing." end
    binding.unmapped, binding.trackGuid = nil, adapter.track_guid(track)
    result.rebound_lanes = result.rebound_lanes + 1
  end

  subscription.acceptedDeliveryRevision = review.target_revision
  subscription.sourceProjectName = review.target_snapshot.sourceProjectName
  adapter.set_project_value(constants.PROJECT_KEYS.delivery_subscriptions, json.encode(subscriptions))
  adapter.mark_project_dirty()
  adapter.end_undo(label)
  return result
end

function M.moved_instances(adapter)
  local stored = adapter.get_project_value(constants.PROJECT_KEYS.delivery_subscriptions)
  local ok, subscriptions = pcall(json.decode, stored or "")
  if not ok or type(subscriptions) ~= "table" then return {} end
  local moved = {}
  for _, subscription in ipairs(subscriptions) do
    local expected = {}
    for _, binding in ipairs(subscription.lanes or {}) do
      if binding.trackGuid and not binding.unmapped then expected[binding.laneId] = binding.trackGuid end
    end
    for _, instance in ipairs(adapter.delivery_instances(subscription.sourceProjectId)) do
      local expected_guid = expected[instance.lane_id]
      if expected_guid and adapter.track_guid(instance.track_ref) ~= expected_guid then
        table.insert(moved, instance)
      end
    end
  end
  return moved
end

function M.detach_many(adapter, instances)
  if #instances == 0 then return { detached = 0 } end
  local label = "Keep ReaProjectLink Items as Local"
  adapter.begin_undo(label)
  for _, instance in ipairs(instances) do
    local detached, detach_error = adapter.detach_instance(instance.item_ref)
    if not detached then cancel_undo(adapter, label); return nil, detach_error end
  end
  adapter.mark_project_dirty()
  adapter.end_undo(label)
  return { detached = #instances }
end

function M.detach(adapter, item)
  if not adapter.is_linked_item(item) then return nil, "Selected Item is not a synchronized Item." end
  return M.detach_many(adapter, { { item_ref = item } })
end

return M
