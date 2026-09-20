local constants = require("readelivery.constants")
local json = require("readelivery.json")
local mix_update_plan = require("readelivery.mix_update_plan")
local project_guard = require("readelivery.project_guard")
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

function M.review(adapter, fs, source_project_id, target_revision)
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
  local latest_revision = pointer.latestPublishRevision
  -- Every published snapshot is immutable, so any of them can serve as the
  -- target the Mix project is aligned to.
  local target = tonumber(target_revision) or latest_revision
  if target < 1 or target > latest_revision then
    return nil, "Requested Delivery revision was never published."
  end
  local target_path = target == latest_revision and
    fs.join(package_root, pointer.manifest) or
    fs.join(package_root, string.format("history/publish-%04d.json", target))
  local snapshot, snapshot_error = read_json(fs, target_path, "target Delivery Manifest")
  if not snapshot then return nil, snapshot_error end
  if snapshot.publishRevision ~= target then
    return nil, "Delivery snapshot does not carry the expected revision."
  end
  local target_clips = clip_index(snapshot)
  local target_directory = target_path:match("^(.*)[/\\][^/\\]+$")
  local declined = {}
  for _, clip_id in ipairs(subscription.declinedClips or {}) do declined[clip_id] = true end
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
    latest_revision = latest_revision,
    target_revision = target,
    target_snapshot = snapshot,
    instances = {},
    additions = {},
    unmapped_lanes = {},
    bound_lanes = {},
    declined_clips = {},
    blocker_count = 0,
    picture_warning = tonumber(adapter.get_project_value(
      constants.PROJECT_KEYS.picture_revision
    )) ~= snapshot.picture.reviewedRevision,
  }

  local mix_picture_id = adapter.get_project_value(constants.PROJECT_KEYS.picture_id)
  if mix_picture_id ~= snapshot.picture.pictureId then
    result.blocker_count = result.blocker_count + 1
    result.picture_error = "Targeted Source delivery references a different Picture ID."
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
    local target_clip = target_clips[instance.clip_id]
    local row = {
      item_ref = instance.item_ref,
      clip_id = instance.clip_id,
      instance_id = instance.instance_id,
      display_name = (target_clip and target_clip.displayName) or
        (baseline_clip and baseline_clip.displayName),
      clip_instance_index = clip_seen[instance.clip_id],
      clip_instance_total = clip_totals[instance.clip_id],
      decision_key = occurrence == 1 and instance_id or
        (instance_id .. "#" .. occurrence),
      needs_new_instance_id = instance_id == "" or occurrence > 1,
      accepted_media_revision = instance.accepted_media_revision,
      baseline = clip_state(baseline_clip, baseline.sampleRate),
      source = clip_state(target_clip, snapshot.sampleRate),
      mix = instance.state,
      target_clip = target_clip,
      advanced_take_state = instance.advanced_take_state,
    }
    row.plan = mix_update_plan.build({
      baseline = row.baseline,
      source = row.source,
      mix = row.mix,
      accepted_media_revision = instance.accepted_media_revision,
      source_media_revision = target_clip and target_clip.mediaRevision,
    })
    if target_clip then
      row.media_path = normalize_path(fs.join(target_directory, target_clip.mediaFile))
      if row.plan.media.pending then
        local digest = fs.hash_file(row.media_path)
        if digest ~= target_clip.mediaHash:gsub("^sha256:", "") then
          row.blocked = true
          row.error = digest and "Managed WAV hash mismatch." or
            "Managed WAV is missing or unreadable."
          result.blocker_count = result.blocker_count + 1
        end
      end
    end
    table.insert(result.instances, row)
  end

  local instance_clips, instance_tracks = {}, {}
  for _, instance in ipairs(instances) do
    instance_clips[instance.clip_id] = true
    instance_tracks[instance.clip_id] = instance_tracks[instance.clip_id] or instance.track_ref
  end
  local mix_tracks = adapter.all_tracks()
  for _, lane in ipairs(snapshot.lanes or {}) do
    local binding = lane_bindings[lane.laneId]
    -- Deleting the bound Mix Track must not strand the Lane; it becomes
    -- mappable again so its Clips can be imported onto a new Track.
    local bound_track = binding and binding.trackGuid and
      adapter.track_by_guid(binding.trackGuid) or nil
    local orphaned = binding ~= nil and binding.trackGuid ~= nil and bound_track == nil
    if not binding or binding.skipped or orphaned then
      local unmapped = {
        lane_id = lane.laneId,
        display_name = lane.displayName,
        orphaned = orphaned,
        clips = {},
        present_clips = {},
        suggestions = track_suggestions.for_lane(adapter, mix_tracks, lane.displayName),
      }
      for _, clip in ipairs(lane.clips or {}) do
        -- A Clip that already has an Instance stays where the mix user put it,
        -- so the Lane reports it instead of importing a second copy.
        if instance_clips[clip.clipId] then
          local track = instance_tracks[clip.clipId]
          table.insert(unmapped.present_clips, {
            clip_id = clip.clipId,
            display_name = clip.displayName,
            track_name = track and adapter.track_name(track),
            track_ref = track,
          })
        elseif declined[clip.clipId] then
          table.insert(result.declined_clips, {
            clip_id = clip.clipId,
            display_name = clip.displayName,
            lane_display_name = lane.displayName,
          })
        else
          local copy = {}
          for key, value in pairs(clip) do copy[key] = value end
          copy.media_path = normalize_path(fs.join(target_directory, clip.mediaFile))
          local digest = fs.hash_file(copy.media_path)
          if digest ~= clip.mediaHash:gsub("^sha256:", "") then
            copy.blocked = true
            copy.error = digest and "Managed WAV hash mismatch." or
              "Managed WAV is missing or unreadable."
            result.blocker_count = result.blocker_count + 1
          end
          table.insert(unmapped.clips, copy)
        end
      end
      -- The Track already holding the Lane's Clips is the likeliest target and
      -- display names alone would never suggest it.
      for _, present in ipairs(unmapped.present_clips) do
        local guid = present.track_ref and adapter.track_guid(present.track_ref)
        local known = guid == nil
        for _, suggestion in ipairs(unmapped.suggestions) do
          if suggestion.track_guid == guid then known = true end
        end
        if not known then
          table.insert(unmapped.suggestions, 1, {
            track_ref = present.track_ref,
            track_guid = guid,
            display_name = present.track_name,
          })
        end
      end
      table.insert(result.unmapped_lanes, unmapped)
    elseif binding.trackGuid then
      -- Moving an Item elsewhere never breaks its Instance, but the Lane still
      -- decides where the next new Clip lands, so the target stays visible.
      table.insert(result.bound_lanes, {
        lane_id = lane.laneId,
        display_name = lane.displayName,
        track_guid = binding.trackGuid,
        track_name = adapter.track_name(bound_track),
      })
      for _, clip in ipairs(lane.clips or {}) do
        -- A Clip belongs in the Mix unless an Item already carries it or the
        -- mix user declined it; a passing revision number proves nothing.
        if declined[clip.clipId] then
          table.insert(result.declined_clips, {
            clip_id = clip.clipId,
            display_name = clip.displayName,
            lane_display_name = lane.displayName,
          })
        elseif not instance_clips[clip.clipId] then
          local media_path = normalize_path(fs.join(target_directory, clip.mediaFile))
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
  return project_guard.bind(result, adapter, false)
end

function M.apply(review, adapter, options)
  local current, context_error = project_guard.check(review, adapter, "Update Review")
  if not current then return nil, context_error end
  options = options or {}
  local rebindings = options.lane_rebindings or {}
  if review.pending_count == 0 and next(rebindings) == nil then
    return nil, "Nothing to update."
  end
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
  if adapter.valid_item then
    for _, row in ipairs(review.instances) do
      if not adapter.valid_item(row.item_ref) then
        return nil, "An Update Review Item belongs to a different or closed REAPER project."
      end
      if adapter.delivery_instance_state and
          json.encode(adapter.delivery_instance_state(row.item_ref)) ~= json.encode(row.mix) then
        return nil, "An Item changed after Update Review. Refresh the Review first."
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
  -- Work on a private copy so a failed, rolled-back Apply does not mutate the
  -- still-visible Review and poison a retry with state that was never saved.
  local subscriptions = json.decode(json.encode(review.subscriptions))
  local subscription = subscriptions[review.subscription_index]
  local result = {
    new_takes = 0,
    new_items = 0,
    new_tracks = 0,
    updated_instances = 0,
    reassigned_instances = 0,
    rebound_lanes = 0,
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
      source_media_revision = row.target_clip and row.target_clip.mediaRevision,
      media_choice = decision.media_choice,
      field_choices = decision.field_choices,
    })
    local accepted_media_revision = row.accepted_media_revision
    if plan.media.pending and plan.media.choice == "accept_new_take" then
      if row.advanced_take_state and not decision.replace_anyway then
        cancel_undo(adapter, "Apply ReaDelivery Source update")
        return nil, "Advanced Take state requires Skip or Replace Anyway."
      end
      local added, add_error = adapter.add_delivery_take(
        row.item_ref,
        row.target_clip,
        row.media_path,
        { source_sample_rate = review.target_snapshot.sampleRate }
      )
      if not added then
        cancel_undo(adapter, "Apply ReaDelivery Source update")
        return nil, add_error
      end
      accepted_media_revision = row.target_clip.mediaRevision
      result.new_takes = result.new_takes + 1
    end
    if not plan.retired then
      local applied, apply_error = adapter.apply_delivery_fields(
        row.item_ref,
        plan.fields,
        { picture_start_samples = tonumber(adapter.get_project_value(
            constants.PROJECT_KEYS.picture_start_samples
          )) or 0,
          project_sample_rate = tonumber(adapter.get_project_value(
            constants.PROJECT_KEYS.picture_start_sample_rate
          )) or adapter.project_sample_rate() }
      )
      if not applied then
        cancel_undo(adapter, "Apply ReaDelivery Source update")
        return nil, apply_error
      end
    end
    adapter.set_instance_revisions(
      row.item_ref,
      accepted_media_revision,
      review.target_revision
    )
    result.updated_instances = result.updated_instances + 1
  end

  local picture_start = tonumber(adapter.get_project_value(
    constants.PROJECT_KEYS.picture_start_samples
  )) or 0
  local project_sample_rate = adapter.project_sample_rate()
  local picture_start_sample_rate = tonumber(adapter.get_project_value(
    constants.PROJECT_KEYS.picture_start_sample_rate
  )) or project_sample_rate
  local function import_clip(track, clip, media_path)
    local copy = {}
    for key, value in pairs(clip) do copy[key] = value end
    copy.media_path = media_path
    local item, item_error = adapter.create_delivery_item(track, copy, {
      position_seconds = picture_start / picture_start_sample_rate +
        clip.startOffsetSamples / review.target_snapshot.sampleRate,
      source_project_id = review.source_project_id,
      publish_revision = review.target_revision,
      picture_revision = review.target_snapshot.picture.reviewedRevision,
      instance_id = adapter.new_id(),
      source_sample_rate = review.target_snapshot.sampleRate,
    })
    if not item then return nil, item_error end
    result.new_items = result.new_items + 1
    return item
  end

  for _, addition in ipairs(review.additions) do
    if addition_decisions[addition.clip.clipId] == "import" then
      local track = adapter.track_by_guid(addition.track_guid)
      if not track then
        cancel_undo(adapter, "Apply ReaDelivery Source update")
        return nil, "A bound Mix Track is unavailable."
      end
      local item, item_error = import_clip(track, addition.clip, addition.media_path)
      if not item then
        cancel_undo(adapter, "Apply ReaDelivery Source update")
        return nil, item_error
      end
    end
  end

  for _, lane_review in ipairs(review.unmapped_lanes) do
    local mapping = lane_mappings[lane_review.lane_id]
    local binding
    for _, candidate in ipairs(subscription.lanes or {}) do
      if candidate.laneId == lane_review.lane_id then binding = candidate end
    end
    if not binding then
      binding = { laneId = lane_review.lane_id }
      table.insert(subscription.lanes, binding)
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
        cancel_undo(adapter, "Apply ReaDelivery Source update")
        return nil, "Unknown Lane mapping decision."
      end
      if not track then
        cancel_undo(adapter, "Apply ReaDelivery Source update")
        return nil, "Mapped Track is unavailable."
      end
      binding.skipped = nil
      binding.trackGuid = adapter.track_guid(track)
      for _, clip in ipairs(lane_review.clips) do
        local item, item_error = import_clip(track, clip, clip.media_path)
        if not item then
          cancel_undo(adapter, "Apply ReaDelivery Source update")
          return nil, item_error
        end
      end
    end
  end

  for lane_id, track in pairs(rebindings) do
    local binding
    for _, candidate in ipairs(subscription.lanes or {}) do
      if candidate.laneId == lane_id then binding = candidate end
    end
    local guid = track and adapter.track_guid(track)
    if not binding or not guid then
      cancel_undo(adapter, "Apply ReaDelivery Source update")
      return nil, "Rebound Mix Track is unavailable."
    end
    binding.skipped = nil
    binding.trackGuid = guid
    result.rebound_lanes = result.rebound_lanes + 1
  end

  -- Declining a Clip has to outlive the revision it was offered in, otherwise
  -- the Clip silently disappears once the accepted revision moves past it.
  local declined = {}
  for _, clip_id in ipairs(subscription.declinedClips or {}) do
    declined[clip_id] = true
  end
  for _, addition in ipairs(review.additions) do
    declined[addition.clip.clipId] = addition_decisions[addition.clip.clipId] == "skip" or nil
  end
  local declined_list = {}
  for clip_id in pairs(declined) do table.insert(declined_list, clip_id) end
  table.sort(declined_list)
  subscription.declinedClips = #declined_list > 0 and declined_list or nil

  subscription.acceptedPublishRevision = review.target_revision
  subscription.sourceProjectName = review.target_snapshot.sourceProjectName
  adapter.set_project_value(
    constants.PROJECT_KEYS.source_subscriptions,
    json.encode(subscriptions)
  )
  adapter.mark_project_dirty()
  adapter.end_undo("Apply ReaDelivery Source update")
  return result
end

function M.undecline(adapter, source_project_id, clip_id)
  local stored = adapter.get_project_value(constants.PROJECT_KEYS.source_subscriptions)
  local ok, subscriptions = pcall(json.decode, stored or "")
  if not ok or type(subscriptions) ~= "table" then
    return nil, "Stored Source subscriptions are invalid."
  end
  local subscription = find_subscription(subscriptions, source_project_id)
  if not subscription then return nil, "Source subscription was not found." end
  local kept = {}
  for _, id in ipairs(subscription.declinedClips or {}) do
    if id ~= clip_id then table.insert(kept, id) end
  end
  subscription.declinedClips = #kept > 0 and kept or nil
  adapter.set_project_value(
    constants.PROJECT_KEYS.source_subscriptions,
    json.encode(subscriptions)
  )
  adapter.mark_project_dirty()
  return { clip_id = clip_id }
end

function M.detach(adapter, item)
  adapter.begin_undo("Detach ReaDelivery Instance")
  local detached, detach_error = adapter.detach_instance(item)
  if not detached then
    cancel_undo(adapter, "Detach ReaDelivery Instance")
    return nil, detach_error
  end
  adapter.mark_project_dirty()
  adapter.end_undo("Detach ReaDelivery Instance")
  return { item_ref = item }
end

return M
