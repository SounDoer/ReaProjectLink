local M = {}

local function raw_hash(value)
  return value and value:gsub("^sha256:", "") or nil
end

local function previous_index(snapshot)
  local by_id = {}
  local ordered = {}
  for _, lane in ipairs(snapshot and snapshot.lanes or {}) do
    for _, clip in ipairs(lane.clips or {}) do
      local entry = { lane_id = lane.laneId, clip = clip }
      by_id[clip.clipId] = entry
      table.insert(ordered, entry)
    end
  end
  return by_id, ordered
end

local function equal_take(current, previous)
  current = current or {}
  previous = previous or {}
  return current.volume == previous.volume and
    current.pan == previous.pan and
    current.playback_rate == previous.playbackRate and
    current.pitch == previous.pitch and
    current.channel_mode == previous.channelMode and
    current.polarity_inverted == previous.polarityInverted
end

local function classify(current, previous)
  if raw_hash(previous.mediaHash) ~= current.media_hash then
    return "Audio Changed"
  end
  if current.start_offset_samples ~= previous.startOffsetSamples or
      current.source_offset_samples ~= previous.sourceOffsetSamples or
      current.length_samples ~= previous.lengthSamples then
    return "Placement Changed"
  end
  if current.display_name ~= previous.displayName or
      current.item_gain ~= previous.itemGain or
      current.fade_in_samples ~= previous.fadeInSamples or
      current.fade_out_samples ~= previous.fadeOutSamples or
      not equal_take(current.take, previous.take) then
    return "Metadata Changed"
  end
  return "Unchanged"
end

local function copy_clip(clip)
  local result = {}
  for key, value in pairs(clip) do result[key] = value end
  return result
end

local function effective_blockers(blockers, publish_anyway)
  local result = {}
  for _, blocker in ipairs(blockers or {}) do
    if not publish_anyway or blocker ~=
        "Take FX will not be included; use Publish Unprocessed Media to continue" then
      table.insert(result, blocker)
    end
  end
  return result
end

local function suggestions_for(lane_id, current, ordered_previous, current_ids)
  local suggestions = {}
  for _, entry in ipairs(ordered_previous) do
    local clip_id = entry.clip.clipId
    if not current_ids[clip_id] then
      local reasons = {}
      if entry.lane_id == lane_id then
        table.insert(reasons, "same Delivery Lane")
      end
      if raw_hash(entry.clip.mediaHash) == current.media_hash then
        table.insert(reasons, "identical audio content")
      end
      if entry.clip.startOffsetSamples == current.start_offset_samples then
        table.insert(reasons, "same timeline position")
      end
      if entry.clip.lengthSamples == current.length_samples then
        table.insert(reasons, "same duration")
      end
      if entry.clip.displayName == current.display_name then
        table.insert(reasons, "same display name")
      end
      table.insert(suggestions, {
        clip_id = clip_id,
        display_name = entry.clip.displayName,
        reasons = reasons,
        same_lane = entry.lane_id == lane_id,
        reason_count = #reasons,
      })
    end
  end
  table.sort(suggestions, function(left, right)
    if left.same_lane ~= right.same_lane then return left.same_lane end
    if left.reason_count ~= right.reason_count then
      return left.reason_count > right.reason_count
    end
    return left.clip_id < right.clip_id
  end)
  return suggestions
end

function M.build(input, fs)
  local previous_by_id, ordered_previous = previous_index(input.previous_snapshot)
  local decisions = input.identity_decisions or {}
  local current_ids = {}
  local current_id_counts = {}
  for _, lane in ipairs(input.current.lanes or {}) do
    for _, clip in ipairs(lane.clips or {}) do
      if clip.clip_id and clip.clip_id ~= "" then
        current_ids[clip.clip_id] = true
        current_id_counts[clip.clip_id] = (current_id_counts[clip.clip_id] or 0) + 1
      end
    end
  end

  -- Exactly one Item may continue the published lineage of a duplicated ID.
  local keep_counts = {}
  for _, lane in ipairs(input.current.lanes or {}) do
    for _, clip in ipairs(lane.clips or {}) do
      local decision = decisions[clip.item_ref]
      if decision and decision.kind == "keep" and clip.clip_id and
          clip.clip_id ~= "" and current_id_counts[clip.clip_id] > 1 then
        keep_counts[clip.clip_id] = (keep_counts[clip.clip_id] or 0) + 1
      end
    end
  end

  local result = {
    delivery_revision = input.previous_snapshot and
      input.previous_snapshot.deliveryRevision + 1 or 1,
    lanes = {},
    retired = {},
    blocker_count = 0,
    needs_decision_count = 0,
    has_unprocessed_fx = false,
    current = { sample_rate = input.current.sample_rate, lanes = {} },
  }

  for lane_index, lane in ipairs(input.current.lanes or {}) do
    if (lane.track_fx_count or 0) > 0 then
      result.has_unprocessed_fx = true
    end
    local reviewed_lane = {
      lane_id = lane.lane_id,
      display_name = lane.display_name,
      clips = {},
      fx_blocked = (lane.track_fx_count or 0) > 0 and not input.publish_anyway,
    }
    local current_lane = {
      lane_id = lane.lane_id,
      display_name = lane.display_name,
      order = lane.order or lane_index - 1,
      clips = {},
    }
    if reviewed_lane.fx_blocked then
      result.blocker_count = result.blocker_count + 1
    end

    for _, original in ipairs(lane.clips or {}) do
      local clip = copy_clip(original)
      if (clip.take_fx_count or 0) > 0 then
        result.has_unprocessed_fx = true
      end
      clip.media_hash = fs.hash_file(clip.media_path)
      clip.media_size = fs.file_size(clip.media_path)
      local row = {
        clip = clip,
        blockers = effective_blockers(clip.blockers, input.publish_anyway),
      }
      local decision = decisions[clip.item_ref]

      -- The flag stays on every Item of a duplicated ID whatever it resolves
      -- to, so the UI can always offer a way back to another decision.
      local duplicated = clip.clip_id and clip.clip_id ~= "" and
        current_id_counts[clip.clip_id] > 1
      row.duplicate = duplicated
      local contested = duplicated and (keep_counts[clip.clip_id] or 0) > 1
      if duplicated and decision and decision.kind == "new" then
        clip.clip_id = ""
        duplicated = false
      end

      if duplicated and not (decision and decision.kind == "keep") then
        row.status = "Needs Decision"
        table.insert(row.blockers, "Duplicate Clip ID must be resolved")
        result.needs_decision_count = result.needs_decision_count + 1
        result.blocker_count = result.blocker_count + 1
      elseif contested then
        row.status = "Blocked"
        table.insert(row.blockers, "Only one Item may keep a duplicated Clip ID")
        result.blocker_count = result.blocker_count + 1
      elseif #row.blockers > 0 or not clip.media_hash or not clip.media_size then
        row.status = "Blocked"
        result.blocker_count = result.blocker_count + math.max(1, #row.blockers)
      elseif not clip.clip_id or clip.clip_id == "" then
        if decision and decision.kind == "new" then
          clip.confirmed_new = true
          row.status = "Added"
        elseif decision and decision.kind == "link" then
          local target = previous_by_id[decision.clip_id]
          if not target or current_ids[decision.clip_id] then
            row.status = "Blocked"
            table.insert(row.blockers, "Selected Clip is not eligible for linking")
            result.blocker_count = result.blocker_count + 1
          else
            clip.clip_id = decision.clip_id
            current_ids[clip.clip_id] = true
            row.status = classify(clip, target.clip)
          end
        else
          row.status = "Needs Decision"
          row.suggestions = suggestions_for(
            lane.lane_id,
            clip,
            ordered_previous,
            current_ids
          )
          result.needs_decision_count = result.needs_decision_count + 1
          result.blocker_count = result.blocker_count + 1
        end
      else
        local prior = previous_by_id[clip.clip_id]
        if prior then
          row.status = classify(clip, prior.clip)
        elseif input.previous_snapshot then
          row.status = "Blocked"
          table.insert(row.blockers, "Unknown Clip ID requires an identity decision")
          result.blocker_count = result.blocker_count + 1
        else
          row.status = "Added"
        end
      end

      row.clip_id = clip.clip_id
      row.display_name = clip.display_name
      table.insert(reviewed_lane.clips, row)
      table.insert(current_lane.clips, clip)
    end
    table.insert(result.lanes, reviewed_lane)
    table.insert(result.current.lanes, current_lane)
  end

  for _, entry in ipairs(ordered_previous) do
    if not current_ids[entry.clip.clipId] then
      table.insert(result.retired, {
        status = "Retired",
        clip_id = entry.clip.clipId,
        display_name = entry.clip.displayName,
        lane_id = entry.lane_id,
      })
    end
  end

  return result
end

return M
