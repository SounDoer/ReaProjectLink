local constants = require("readelivery.constants")
local json = require("readelivery.json")
local mix_update_plan = require("readelivery.mix_update_plan")
local track_suggestions = require("readelivery.track_suggestions")

local M = {}

local function normalize_path(path)
  path = path:gsub("\\", "/")
  local prefix = ""
  if path:match("^%a:/") then
    prefix, path = path:sub(1, 2), path:sub(4)
  elseif path:sub(1, 2) == "//" then
    prefix, path = "//", path:sub(3)
  end
  local parts = {}
  for part in path:gmatch("[^/]+") do
    if part == ".." then table.remove(parts)
    elseif part ~= "." then table.insert(parts, part) end
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

local function clip_index(snapshot)
  local result = {}
  for _, lane in ipairs(snapshot.lanes or {}) do
    for _, clip in ipairs(lane.clips or {}) do result[clip.clipId] = clip end
  end
  return result
end

local function clip_state(clip, sample_rate)
  if not clip then return nil end
  local take = clip.take or {}
  return {
    position_seconds = clip.startOffsetSamples / sample_rate,
    length_seconds = clip.lengthSamples / sample_rate,
    source_offset_seconds = clip.sourceOffsetSamples / sample_rate,
    fade_in_seconds = (clip.fadeInSamples or 0) / sample_rate,
    fade_out_seconds = (clip.fadeOutSamples or 0) / sample_rate,
    item_gain = clip.itemGain,
    take_volume = take.volume,
    take_pan = take.pan,
    take_playback_rate = take.playbackRate,
    take_pitch = take.pitch,
    take_channel_mode = take.channelMode,
    take_polarity_inverted = take.polarityInverted,
  }
end

-- A `mix_only` or `same_change` field already matches the desired result, so
-- applying it would change nothing.
local function instance_has_work(plan)
  if plan.retired or plan.media.pending then return true end
  for _, field in pairs(plan.fields) do
    if field.kind == "source_only" or field.kind == "conflict" then return true end
  end
  return false
end

local function find_subscription(subscriptions, source_project_id)
  for index, subscription in ipairs(subscriptions) do
    if subscription.sourceProjectId == source_project_id then
      return subscription, index
    end
  end
end

function M.review(adapter, fs, source_project_id)
  local stored = adapter.get_project_value(constants.PROJECT_KEYS.source_subscriptions)
  if not stored or stored == "" then return nil, "Mix project has no Source subscriptions." end
  local ok, subscriptions = pcall(json.decode, stored)
  if not ok then return nil, "Stored Source subscriptions are invalid." end
  local subscription, subscription_index = find_subscription(subscriptions, source_project_id)
  if not subscription then return nil, "Source subscription was not found." end

  local pointer, pointer_error = read_json(fs, subscription.pointerPath, "delivery.json")
  if not pointer then return nil, pointer_error end
  if pointer.sourceProjectId ~= subscription.sourceProjectId or
      pointer.deliverySetId ~= subscription.deliverySetId then
    return nil, "Subscribed Source or Delivery Set identity changed."
  end
  local package_root = subscription.pointerPath:match("^(.*)[/\\][^/\\]+$")
  local latest_path = fs.join(package_root, pointer.manifest)
  local latest, latest_error = read_json(fs, latest_path, "latest Delivery Manifest")
  if not latest then return nil, latest_error end
  if latest.publishRevision ~= pointer.latestPublishRevision then
    return nil, "Delivery pointer and latest snapshot revision do not match."
  end
  local latest_clips = clip_index(latest)
  local latest_directory = latest_path:match("^(.*)[/\\][^/\\]+$")
  local accepted_path = fs.join(
    package_root,
    string.format("history/publish-%04d.json", subscription.acceptedPublishRevision)
  )
  local accepted_snapshot, accepted_error = read_json(
    fs,
    accepted_path,
    "accepted Delivery Manifest"
  )
  if not accepted_snapshot then return nil, accepted_error end
  local accepted_clips = clip_index(accepted_snapshot)
  local lane_bindings = {}
  for _, binding in ipairs(subscription.lanes or {}) do
    lane_bindings[binding.laneId] = binding
  end
  local baseline_cache = {}
  local instances = adapter.delivery_instances(source_project_id)
  local instance_id_counts = {}
  local result = {
    source_project_id = source_project_id,
    subscription_index = subscription_index,
    subscriptions = subscriptions,
    subscription = subscription,
    latest_revision = pointer.latestPublishRevision,
    latest_snapshot = latest,
    instances = {},
    additions = {},
    unmapped_lanes = {},
    blocker_count = 0,
    picture_warning = tonumber(adapter.get_project_value(
      constants.PROJECT_KEYS.picture_revision
    )) ~= latest.picture.reviewedRevision,
  }

  local mix_picture_id = adapter.get_project_value(constants.PROJECT_KEYS.picture_id)
  if mix_picture_id ~= latest.picture.pictureId then
    result.blocker_count = result.blocker_count + 1
    result.picture_error = "Latest Source delivery references a different Picture ID."
  end

  -- Several Mix Items may legitimately carry one Clip, so the review numbers
  -- them instead of leaning on identifiers the user cannot read.
  local clip_totals, clip_seen = {}, {}
  for _, instance in ipairs(instances) do
    clip_totals[instance.clip_id] = (clip_totals[instance.clip_id] or 0) + 1
  end

  for _, instance in ipairs(instances) do
    local instance_id = instance.instance_id or ""
    instance_id_counts[instance_id] = (instance_id_counts[instance_id] or 0) + 1
    local occurrence = instance_id_counts[instance_id]
    clip_seen[instance.clip_id] = (clip_seen[instance.clip_id] or 0) + 1
    local baseline_revision = instance.handled_publish_revision
    local baseline = baseline_cache[baseline_revision]
    if not baseline then
      local baseline_path = fs.join(
        package_root,
        string.format("history/publish-%04d.json", baseline_revision)
      )
      local baseline_error
      baseline, baseline_error = read_json(fs, baseline_path, "handled Delivery Manifest")
      if not baseline then return nil, baseline_error end
      baseline_cache[baseline_revision] = baseline
    end
    local baseline_clip = clip_index(baseline)[instance.clip_id]
    local latest_clip = latest_clips[instance.clip_id]
    local row = {
      item_ref = instance.item_ref,
      clip_id = instance.clip_id,
      instance_id = instance.instance_id,
      display_name = (latest_clip and latest_clip.displayName) or
        (baseline_clip and baseline_clip.displayName),
      clip_instance_index = clip_seen[instance.clip_id],
      clip_instance_total = clip_totals[instance.clip_id],
      decision_key = occurrence == 1 and instance_id or
        (instance_id .. "#" .. occurrence),
      needs_new_instance_id = instance_id == "" or occurrence > 1,
      accepted_media_revision = instance.accepted_media_revision,
      baseline = clip_state(baseline_clip, baseline.sampleRate),
      source = clip_state(latest_clip, latest.sampleRate),
      mix = instance.state,
      latest_clip = latest_clip,
      advanced_take_state = instance.advanced_take_state,
    }
    row.plan = mix_update_plan.build({
      baseline = row.baseline,
      source = row.source,
      mix = row.mix,
      accepted_media_revision = instance.accepted_media_revision,
      source_media_revision = latest_clip and latest_clip.mediaRevision,
    })
    if latest_clip then
      row.media_path = normalize_path(fs.join(latest_directory, latest_clip.mediaFile))
      if row.plan.media.pending then
        local digest = fs.hash_file(row.media_path)
        if digest ~= latest_clip.mediaHash:gsub("^sha256:", "") then
          row.blocked = true
          row.error = digest and "Managed WAV hash mismatch." or
            "Managed WAV is missing or unreadable."
          result.blocker_count = result.blocker_count + 1
        end
      end
    end
    table.insert(result.instances, row)
  end

  local instance_clips = {}
  for _, instance in ipairs(instances) do instance_clips[instance.clip_id] = true end
  local mix_tracks = adapter.all_tracks()
  for _, lane in ipairs(latest.lanes or {}) do
    local binding = lane_bindings[lane.laneId]
    if not binding or binding.skipped then
      local unmapped = {
        lane_id = lane.laneId,
        display_name = lane.displayName,
        clips = {},
        suggestions = track_suggestions.for_lane(adapter, mix_tracks, lane.displayName),
      }
      for _, clip in ipairs(lane.clips or {}) do
        local copy = {}
        for key, value in pairs(clip) do copy[key] = value end
        copy.media_path = normalize_path(fs.join(latest_directory, clip.mediaFile))
        local digest = fs.hash_file(copy.media_path)
        if digest ~= clip.mediaHash:gsub("^sha256:", "") then
          copy.blocked = true
          copy.error = digest and "Managed WAV hash mismatch." or
            "Managed WAV is missing or unreadable."
          result.blocker_count = result.blocker_count + 1
        end
        table.insert(unmapped.clips, copy)
      end
      table.insert(result.unmapped_lanes, unmapped)
    elseif binding.trackGuid then
      for _, clip in ipairs(lane.clips or {}) do
        if not accepted_clips[clip.clipId] and not instance_clips[clip.clipId] then
          local media_path = normalize_path(fs.join(latest_directory, clip.mediaFile))
          local digest = fs.hash_file(media_path)
          local addition = {
            lane_id = lane.laneId,
            track_guid = binding.trackGuid,
            clip = clip,
            media_path = media_path,
          }
          if digest ~= clip.mediaHash:gsub("^sha256:", "") then
            addition.blocked = true
            addition.error = digest and "Managed WAV hash mismatch." or
              "Managed WAV is missing or unreadable."
            result.blocker_count = result.blocker_count + 1
          end
          table.insert(result.additions, addition)
        end
      end
    end
  end

  result.pending_count = #result.additions + #result.unmapped_lanes
  for _, row in ipairs(result.instances) do
    if instance_has_work(row.plan) then
      result.pending_count = result.pending_count + 1
    end
  end
  return result
end

function M.apply(review, adapter, options)
  options = options or {}
  if review.pending_count == 0 then return nil, "Nothing to update." end
  if review.blocker_count > 0 then return nil, "Update Review has blockers." end
  if review.picture_warning and not options.allow_picture_revision_mismatch then
    return nil, "Source was reviewed against a different Picture revision."
  end
  local decisions = options.instances or {}
  local addition_decisions = options.additions or {}
  local lane_mappings = options.lane_mappings or {}
  for _, addition in ipairs(review.additions) do
    if addition_decisions[addition.clip.clipId] ~= "import" and
        addition_decisions[addition.clip.clipId] ~= "skip" then
      return nil, "Every new Clip requires Import or Skip."
    end
  end
  for _, lane in ipairs(review.unmapped_lanes) do
    if not lane_mappings[lane.lane_id] then
      return nil, "Every new Delivery Lane requires a mapping decision."
    end
  end
  local result = {
    new_takes = 0,
    new_items = 0,
    new_tracks = 0,
    updated_instances = 0,
    reassigned_instances = 0,
  }

  adapter.begin_undo("Apply ReaDelivery Source update")
  for _, row in ipairs(review.instances) do
    local decision = decisions[row.decision_key] or {}
    if row.needs_new_instance_id then
      adapter.set_instance_id(row.item_ref, adapter.new_id())
      result.reassigned_instances = result.reassigned_instances + 1
    end
    local plan = mix_update_plan.build({
      baseline = row.baseline,
      source = row.source,
      mix = row.mix,
      accepted_media_revision = row.accepted_media_revision,
      source_media_revision = row.latest_clip and row.latest_clip.mediaRevision,
      media_choice = decision.media_choice,
      field_choices = decision.field_choices,
    })
    local accepted_media_revision = row.accepted_media_revision
    if plan.media.pending and plan.media.choice == "accept_new_take" then
      if row.advanced_take_state and not decision.replace_anyway then
        adapter.end_undo("Apply ReaDelivery Source update")
        return nil, "Advanced Take state requires Skip or Replace Anyway."
      end
      local added, add_error = adapter.add_delivery_take(
        row.item_ref,
        row.latest_clip,
        row.media_path,
        { source_sample_rate = review.latest_snapshot.sampleRate }
      )
      if not added then
        adapter.end_undo("Apply ReaDelivery Source update")
        return nil, add_error
      end
      accepted_media_revision = row.latest_clip.mediaRevision
      result.new_takes = result.new_takes + 1
    end
    if not plan.retired then
      local applied, apply_error = adapter.apply_delivery_fields(
        row.item_ref,
        plan.fields,
        { picture_start_samples = tonumber(adapter.get_project_value(
            constants.PROJECT_KEYS.picture_start_samples
          )) or 0,
          project_sample_rate = adapter.project_sample_rate() }
      )
      if not applied then
        adapter.end_undo("Apply ReaDelivery Source update")
        return nil, apply_error
      end
    end
    adapter.set_instance_revisions(
      row.item_ref,
      accepted_media_revision,
      review.latest_revision
    )
    result.updated_instances = result.updated_instances + 1
  end

  local picture_start = tonumber(adapter.get_project_value(
    constants.PROJECT_KEYS.picture_start_samples
  )) or 0
  local project_sample_rate = adapter.project_sample_rate()
  local function import_clip(track, clip, media_path)
    local copy = {}
    for key, value in pairs(clip) do copy[key] = value end
    copy.media_path = media_path
    local item, item_error = adapter.create_delivery_item(track, copy, {
      position_seconds = picture_start / project_sample_rate +
        clip.startOffsetSamples / review.latest_snapshot.sampleRate,
      source_project_id = review.source_project_id,
      publish_revision = review.latest_revision,
      picture_revision = review.latest_snapshot.picture.reviewedRevision,
      instance_id = adapter.new_id(),
      source_sample_rate = review.latest_snapshot.sampleRate,
    })
    if not item then return nil, item_error end
    result.new_items = result.new_items + 1
    return item
  end

  for _, addition in ipairs(review.additions) do
    if addition_decisions[addition.clip.clipId] == "import" then
      local track = adapter.track_by_guid(addition.track_guid)
      if not track then
        adapter.end_undo("Apply ReaDelivery Source update")
        return nil, "A bound Mix Track is unavailable."
      end
      local item, item_error = import_clip(track, addition.clip, addition.media_path)
      if not item then
        adapter.end_undo("Apply ReaDelivery Source update")
        return nil, item_error
      end
    end
  end

  for _, lane_review in ipairs(review.unmapped_lanes) do
    local mapping = lane_mappings[lane_review.lane_id]
    local binding
    for _, candidate in ipairs(review.subscription.lanes or {}) do
      if candidate.laneId == lane_review.lane_id then binding = candidate end
    end
    if not binding then
      binding = { laneId = lane_review.lane_id }
      table.insert(review.subscription.lanes, binding)
    end
    if mapping.kind == "skip" then
      binding.skipped = true
      binding.trackGuid = nil
    else
      local track = mapping.track_ref
      if mapping.kind == "create" then
        track = adapter.create_mix_track(lane_review.display_name, mapping.parent_track_ref)
        result.new_tracks = result.new_tracks + 1
      elseif mapping.kind ~= "existing" then
        adapter.end_undo("Apply ReaDelivery Source update")
        return nil, "Unknown Lane mapping decision."
      end
      if not track then
        adapter.end_undo("Apply ReaDelivery Source update")
        return nil, "Mapped Track is unavailable."
      end
      binding.skipped = nil
      binding.trackGuid = adapter.track_guid(track)
      for _, clip in ipairs(lane_review.clips) do
        local item, item_error = import_clip(track, clip, clip.media_path)
        if not item then
          adapter.end_undo("Apply ReaDelivery Source update")
          return nil, item_error
        end
      end
    end
  end

  review.subscription.acceptedPublishRevision = review.latest_revision
  review.subscription.sourceProjectName = review.latest_snapshot.sourceProjectName
  adapter.set_project_value(
    constants.PROJECT_KEYS.source_subscriptions,
    json.encode(review.subscriptions)
  )
  adapter.mark_project_dirty()
  adapter.end_undo("Apply ReaDelivery Source update")
  return result
end

function M.detach(adapter, item)
  adapter.begin_undo("Detach ReaDelivery Instance")
  local detached, detach_error = adapter.detach_instance(item)
  if not detached then
    adapter.end_undo("Detach ReaDelivery Instance")
    return nil, detach_error
  end
  adapter.mark_project_dirty()
  adapter.end_undo("Detach ReaDelivery Instance")
  return { item_ref = item }
end

return M
