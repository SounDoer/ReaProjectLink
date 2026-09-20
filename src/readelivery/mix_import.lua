local constants = require("readelivery.constants")
local json = require("readelivery.json")
local track_suggestions = require("readelivery.track_suggestions")

local M = {}

local function cancel_undo(adapter, label)
  if adapter.cancel_undo then adapter.cancel_undo(label) else adapter.end_undo(label) end
end

local function normalize_path(path)
  path = path:gsub("\\", "/")
  local prefix = ""
  if path:match("^%a:/") then
    prefix, path = path:sub(1, 2), path:sub(4)
  elseif path:sub(1, 2) == "//" then
    prefix, path = "//", path:sub(3)
  elseif path:sub(1, 1) == "/" then
    prefix, path = "/", path:sub(2)
  end
  local parts = {}
  for part in path:gmatch("[^/]+") do
    if part == ".." then
      table.remove(parts)
    elseif part ~= "." then
      table.insert(parts, part)
    end
  end
  local separator = prefix == "//" and "" or "/"
  return prefix .. separator .. table.concat(parts, "/")
end

local function read_json(fs, path, label)
  local bytes, read_error = fs.read_file(path)
  if not bytes then return nil, read_error or ("Could not read " .. label .. ".") end
  local ok, value = pcall(json.decode, bytes)
  if not ok then return nil, label .. " is invalid JSON: " .. tostring(value) end
  if value.schemaVersion ~= 1 then return nil, label .. " uses an unsupported schema version." end
  return value
end

local function load_delivery(fs, pointer_path)
  local pointer, pointer_error = read_json(fs, pointer_path, "delivery.json")
  if not pointer then return nil, pointer_error end
  local package_root = pointer_path:match("^(.*)[/\\][^/\\]+$")
  local snapshot_path = fs.join(package_root, pointer.manifest)
  local snapshot, snapshot_error = read_json(fs, snapshot_path, "Delivery Manifest")
  if not snapshot then return nil, snapshot_error end
  if snapshot.sourceProjectId ~= pointer.sourceProjectId or
      snapshot.deliverySetId ~= pointer.deliverySetId or
      snapshot.publishRevision ~= pointer.latestPublishRevision then
    return nil, "Delivery pointer and snapshot identities do not match."
  end
  return {
    pointer = pointer,
    snapshot = snapshot,
    package_root = package_root,
    snapshot_directory = snapshot_path:match("^(.*)[/\\][^/\\]+$"),
  }
end

function M.review(adapter, fs, pointer_path)
  if adapter.get_project_value(constants.PROJECT_KEYS.project_mode) ~=
      constants.PROJECT_MODES.mix then
    return nil, "Only a Mix project can import Source deliveries."
  end
  local loaded, load_error = load_delivery(fs, pointer_path)
  if not loaded then return nil, load_error end
  local snapshot = loaded.snapshot
  local stored_subscriptions = adapter.get_project_value(
    constants.PROJECT_KEYS.source_subscriptions
  )
  if stored_subscriptions and stored_subscriptions ~= "" then
    local ok, subscriptions = pcall(json.decode, stored_subscriptions)
    if not ok then return nil, "Stored Source subscriptions are invalid." end
    for _, subscription in ipairs(subscriptions) do
      if subscription.sourceProjectId == loaded.pointer.sourceProjectId or
          subscription.deliverySetId == loaded.pointer.deliverySetId then
        return nil, "This Source delivery is already subscribed."
      end
    end
  end
  local mix_picture_id = adapter.get_project_value(constants.PROJECT_KEYS.picture_id)
  local mix_picture_revision = tonumber(adapter.get_project_value(
    constants.PROJECT_KEYS.picture_revision
  )) or 0
  local result = {
    pointer_path = pointer_path,
    pointer = loaded.pointer,
    snapshot = snapshot,
    lanes = {},
    blocker_count = 0,
    picture_warning = mix_picture_revision ~= snapshot.picture.reviewedRevision,
  }
  if not mix_picture_id or mix_picture_id == "" or
      mix_picture_id ~= snapshot.picture.pictureId then
    result.blocker_count = result.blocker_count + 1
    result.picture_error = "Source delivery was reviewed against a different Picture ID."
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
      reviewed_clip.media_path = normalize_path(fs.join(
        loaded.snapshot_directory,
        clip.mediaFile
      ))
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
  return result
end

function M.apply(review, adapter, options)
  options = options or {}
  if review.blocker_count > 0 then return nil, "Import Review has blockers." end
  if review.picture_warning and not options.allow_picture_revision_mismatch then
    return nil, "Source was reviewed against an older Picture revision."
  end
  local mappings = options.mappings or {}
  local result = { created_tracks = 0, created_items = 0, items = {} }
  local subscription = {
    pointerPath = review.pointer_path,
    sourceProjectId = review.pointer.sourceProjectId,
    sourceProjectName = review.snapshot.sourceProjectName,
    deliverySetId = review.pointer.deliverySetId,
    acceptedPublishRevision = review.pointer.latestPublishRevision,
    lanes = {},
  }
  local mix_sample_rate = adapter.project_sample_rate()
  local picture_start = tonumber(adapter.get_project_value(
    constants.PROJECT_KEYS.picture_start_samples
  )) or 0
  local picture_start_sample_rate = tonumber(adapter.get_project_value(
    constants.PROJECT_KEYS.picture_start_sample_rate
  )) or mix_sample_rate

  adapter.begin_undo("Import ReaDelivery Source")
  for _, lane in ipairs(review.lanes) do
    local mapping = mappings[lane.lane_id]
    if not mapping then
      cancel_undo(adapter, "Import ReaDelivery Source")
      return nil, "Every Delivery Lane requires a mapping decision."
    end
    local binding = { laneId = lane.lane_id }
    if mapping.kind == "skip" then
      binding.skipped = true
    else
      local track = mapping.track_ref
      if mapping.kind == "create" then
        track = adapter.create_mix_track(lane.display_name, mapping.parent_track_ref)
        result.created_tracks = result.created_tracks + 1
      elseif mapping.kind ~= "existing" then
        cancel_undo(adapter, "Import ReaDelivery Source")
        return nil, "Unknown Lane mapping decision."
      end
      if not track then
        cancel_undo(adapter, "Import ReaDelivery Source")
        return nil, "Mapped Track is unavailable."
      end
      binding.trackGuid = adapter.track_guid(track)
      for _, clip in ipairs(lane.clips) do
        local item, item_error = adapter.create_delivery_item(track, clip, {
          position_seconds = picture_start / picture_start_sample_rate +
            clip.startOffsetSamples / review.snapshot.sampleRate,
          source_project_id = review.pointer.sourceProjectId,
          publish_revision = review.pointer.latestPublishRevision,
          picture_revision = review.snapshot.picture.reviewedRevision,
          instance_id = adapter.new_id(),
          source_sample_rate = review.snapshot.sampleRate,
        })
        if not item then
          cancel_undo(adapter, "Import ReaDelivery Source")
          return nil, item_error
        end
        table.insert(result.items, item)
        result.created_items = result.created_items + 1
      end
    end
    table.insert(subscription.lanes, binding)
  end

  local stored = adapter.get_project_value(constants.PROJECT_KEYS.source_subscriptions)
  local subscriptions = stored and stored ~= "" and json.decode(stored) or {}
  table.insert(subscriptions, subscription)
  adapter.set_project_value(
    constants.PROJECT_KEYS.source_subscriptions,
    json.encode(subscriptions)
  )
  adapter.mark_project_dirty()
  adapter.end_undo("Import ReaDelivery Source")
  result.subscription = subscription
  return result
end

function M.remove_subscription(adapter, source_project_id)
  local stored = adapter.get_project_value(constants.PROJECT_KEYS.source_subscriptions)
  if not stored or stored == "" then return nil, "Source subscription was not found." end
  local ok, subscriptions = pcall(json.decode, stored)
  if not ok then return nil, "Stored Source subscriptions are invalid." end
  local remaining = json.array()
  local found = false
  for _, subscription in ipairs(subscriptions) do
    if subscription.sourceProjectId == source_project_id then
      found = true
    else
      table.insert(remaining, subscription)
    end
  end
  if not found then return nil, "Source subscription was not found." end
  adapter.begin_undo("Remove ReaDelivery Source subscription")
  adapter.set_project_value(
    constants.PROJECT_KEYS.source_subscriptions,
    json.encode(remaining)
  )
  adapter.mark_project_dirty()
  adapter.end_undo("Remove ReaDelivery Source subscription")
  return { source_project_id = source_project_id }
end

return M
