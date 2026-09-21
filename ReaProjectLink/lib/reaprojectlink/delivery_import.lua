local constants = require("reaprojectlink.constants")
local json = require("reaprojectlink.json")
local manifest_validation = require("reaprojectlink.manifest_validation")
local project_guard = require("reaprojectlink.project_guard")
local track_suggestions = require("reaprojectlink.track_suggestions")
local manifest_file = require("reaprojectlink.manifest_file")

local M = {}

local function load_delivery(fs, pointer_path)
  local pointer, pointer_error = manifest_file.read(fs, pointer_path, "delivery.json", 1)
  if not pointer then return nil, pointer_error end
  local valid, validation_error = manifest_validation.delivery_pointer(pointer)
  if not valid then return nil, validation_error end
  local package_root = pointer_path:match("^(.*)[/\\][^/\\]+$")
  local snapshot_path = fs.join(package_root, pointer.manifest)
  local snapshot, snapshot_error = manifest_file.read(fs, snapshot_path, "Delivery Manifest", 1)
  if not snapshot then return nil, snapshot_error end
  valid, validation_error = manifest_validation.delivery_snapshot(snapshot, {
    source_project_id = pointer.sourceProjectId,
    delivery_id = pointer.deliveryId,
    revision = pointer.latestDeliveryRevision,
  })
  if not valid then return nil, validation_error end
  return {
    pointer = pointer,
    snapshot = snapshot,
    package_root = package_root,
  }
end

function M.review(adapter, fs, pointer_path)
  if adapter.get_project_value(constants.PROJECT_KEYS.project_type) ~=
      constants.PROJECT_TYPES.master then
    return nil, "Only a Master Project can import Deliveries."
  end
  local loaded, load_error = load_delivery(fs, pointer_path)
  if not loaded then return nil, load_error end
  local snapshot = loaded.snapshot
  local stored_subscriptions = adapter.get_project_value(
    constants.PROJECT_KEYS.delivery_subscriptions
  )
  if stored_subscriptions and stored_subscriptions ~= "" then
    local ok, subscriptions = pcall(json.decode, stored_subscriptions)
    if not ok then return nil, "Stored Delivery subscriptions are invalid." end
    for _, subscription in ipairs(subscriptions) do
      if subscription.sourceProjectId == loaded.pointer.sourceProjectId or
          subscription.deliveryId == loaded.pointer.deliveryId then
        return nil, "This Source delivery is already subscribed."
      end
    end
  end
  local master_reference_id = adapter.get_project_value(constants.PROJECT_KEYS.reference_id)
  local master_reference_revision = tonumber(adapter.get_project_value(
    constants.PROJECT_KEYS.reference_revision
  )) or 0
  local result = {
    pointer_path = pointer_path,
    pointer = loaded.pointer,
    snapshot = snapshot,
    lanes = {},
    blocker_count = 0,
    reference_warning = master_reference_revision ~= snapshot.reference.reviewedRevision,
    reference_context = {
      reference_id = master_reference_id,
      reference_revision = master_reference_revision,
      reference_start_samples = adapter.get_project_value(constants.PROJECT_KEYS.reference_start_samples),
      reference_start_sample_rate = adapter.get_project_value(constants.PROJECT_KEYS.reference_start_sample_rate),
    },
  }
  if not master_reference_id or master_reference_id == "" or
      master_reference_id ~= snapshot.reference.referenceId then
    result.blocker_count = result.blocker_count + 1
    result.reference_error = "Source delivery was reviewed against a different Reference ID."
  end

  local tracks = adapter.all_tracks()
  for _, lane in ipairs(snapshot.lanes or {}) do
    local reviewed_lane = {
      lane_id = lane.laneId,
      display_name = lane.displayName,
      order = lane.order,
      clips = {},
      suggestions = track_suggestions.for_lane(adapter, tracks, lane.displayName),
    }

    for _, clip in ipairs(lane.clips or {}) do
      local reviewed_clip = {}
      for key, value in pairs(clip) do reviewed_clip[key] = value end
      local media_path, media_error = manifest_validation.delivery_media_path(
        fs, loaded.package_root, clip.mediaFile
      )
      if not media_path then return nil, media_error end
      reviewed_clip.media_path = media_path
      local actual_hash = fs.hash_file(reviewed_clip.media_path)
      if actual_hash ~= clip.mediaHash:gsub("^sha256:", "") then
        reviewed_clip.blocked = true
        reviewed_clip.error = actual_hash and
          "Managed WAV hash mismatch." or "Managed WAV is missing or unreadable."
        result.blocker_count = result.blocker_count + 1
      end
      table.insert(reviewed_lane.clips, reviewed_clip)
    end
    table.insert(result.lanes, reviewed_lane)
  end
  return project_guard.bind(result, adapter, false)
end

function M.apply(review, adapter, options)
  local current, context_error = project_guard.check(review, adapter, "Import Review")
  if not current then return nil, context_error end
  options = options or {}
  if review.blocker_count > 0 then return nil, "Import Review has blockers." end
  local reference_context = review.reference_context or {}
  local current_reference_revision = tonumber(adapter.get_project_value(
    constants.PROJECT_KEYS.reference_revision
  )) or 0
  if adapter.get_project_value(constants.PROJECT_KEYS.reference_id) ~= reference_context.reference_id or
      current_reference_revision ~= reference_context.reference_revision or
      adapter.get_project_value(constants.PROJECT_KEYS.reference_start_samples) ~= reference_context.reference_start_samples or
      adapter.get_project_value(constants.PROJECT_KEYS.reference_start_sample_rate) ~= reference_context.reference_start_sample_rate then
    return nil, "Reference state changed after Delivery Import Review. Refresh the Review first."
  end
  if review.reference_warning and not options.allow_reference_revision_mismatch then
    return nil, "Source was reviewed against an older Reference revision."
  end
  local mappings = options.mappings or {}
  local result = { created_tracks = 0, created_items = 0, items = {} }
  local subscription = {
    pointerPath = review.pointer_path,
    sourceProjectId = review.pointer.sourceProjectId,
    sourceProjectName = review.snapshot.sourceProjectName,
    deliveryId = review.pointer.deliveryId,
    acceptedDeliveryRevision = review.pointer.latestDeliveryRevision,
    lanes = {},
  }
  local master_sample_rate = adapter.project_sample_rate()
  local reference_start = tonumber(adapter.get_project_value(
    constants.PROJECT_KEYS.reference_start_samples
  )) or 0
  local reference_start_sample_rate = tonumber(adapter.get_project_value(
    constants.PROJECT_KEYS.reference_start_sample_rate
  )) or master_sample_rate

  if adapter.valid_track then
    for _, mapping in pairs(mappings) do
      if (mapping.track_ref and not adapter.valid_track(mapping.track_ref)) or
          (mapping.parent_track_ref and not adapter.valid_track(mapping.parent_track_ref)) then
        return nil, "A mapped Track belongs to a different or closed REAPER project."
      end
    end
  end

  adapter.begin_undo("Import ReaProjectLink Delivery")
  for _, lane in ipairs(review.lanes) do
    local mapping = mappings[lane.lane_id]
    if not mapping then
      project_guard.cancel_undo(adapter, "Import ReaProjectLink Delivery")
      return nil, "Every Delivery Lane requires a mapping decision."
    end
    local binding = { laneId = lane.lane_id }
    if mapping.kind == "unmapped" then
      binding.unmapped = true
    else
      local track = mapping.track_ref
      if mapping.kind == "create" then
        track = adapter.create_master_track(lane.display_name, mapping.parent_track_ref)
        result.created_tracks = result.created_tracks + 1
      elseif mapping.kind ~= "existing" then
        project_guard.cancel_undo(adapter, "Import ReaProjectLink Delivery")
        return nil, "Unknown Lane mapping decision."
      end
      if not track or adapter.valid_track and not adapter.valid_track(track) then
        project_guard.cancel_undo(adapter, "Import ReaProjectLink Delivery")
        return nil, "Mapped Track is unavailable."
      end
      binding.trackGuid = adapter.track_guid(track)
      for _, clip in ipairs(lane.clips) do
        local item, item_error = adapter.create_delivery_item(track, clip, {
          position_seconds = reference_start / reference_start_sample_rate +
            clip.startOffsetSamples / review.snapshot.sampleRate,
           source_project_id = review.pointer.sourceProjectId,
           lane_id = lane.lane_id,
          delivery_revision = review.pointer.latestDeliveryRevision,
          reference_revision = review.snapshot.reference.reviewedRevision,
          source_sample_rate = review.snapshot.sampleRate,
        })
        if not item then
          project_guard.cancel_undo(adapter, "Import ReaProjectLink Delivery")
          return nil, item_error
        end
        table.insert(result.items, item)
        result.created_items = result.created_items + 1
      end
    end
    table.insert(subscription.lanes, binding)
  end

  local stored = adapter.get_project_value(constants.PROJECT_KEYS.delivery_subscriptions)
  local subscriptions = stored and stored ~= "" and json.decode(stored) or {}
  table.insert(subscriptions, subscription)
  adapter.set_project_value(
    constants.PROJECT_KEYS.delivery_subscriptions,
    json.encode(subscriptions)
  )
  adapter.mark_project_dirty()
  adapter.end_undo("Import ReaProjectLink Delivery")
  result.subscription = subscription
  return result
end

function M.remove_subscription(adapter, source_project_id)
  local stored = adapter.get_project_value(constants.PROJECT_KEYS.delivery_subscriptions)
  if not stored or stored == "" then return nil, "Delivery subscription was not found." end
  local ok, subscriptions = pcall(json.decode, stored)
  if not ok then return nil, "Stored Delivery subscriptions are invalid." end
  local remaining = json.array()
  local found = false
  for _, subscription in ipairs(subscriptions) do
    if subscription.sourceProjectId == source_project_id then
      found = true
    else
      table.insert(remaining, subscription)
    end
  end
  if not found then return nil, "Delivery subscription was not found." end
  adapter.begin_undo("Remove ReaProjectLink Delivery subscription")
  adapter.set_project_value(
    constants.PROJECT_KEYS.delivery_subscriptions,
    json.encode(remaining)
  )
  adapter.mark_project_dirty()
  adapter.end_undo("Remove ReaProjectLink Delivery subscription")
  return { source_project_id = source_project_id }
end

return M
