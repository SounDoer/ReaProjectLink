local M = {}

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

-- A Delivery Revision is a complete Source-owned snapshot. Clip identities are
-- deliberately revision-local, so Source edits never need lineage decisions.
function M.build(input, fs)
  local result = {
    delivery_revision = input.previous_snapshot and
      input.previous_snapshot.deliveryRevision + 1 or 1,
    lanes = {},
    blocker_count = 0,
    has_unprocessed_fx = false,
    current = { sample_rate = input.current.sample_rate, lanes = {} },
  }

  for lane_index, lane in ipairs(input.current.lanes or {}) do
    if (lane.track_fx_count or 0) > 0 then result.has_unprocessed_fx = true end
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
    if reviewed_lane.fx_blocked then result.blocker_count = result.blocker_count + 1 end

    for _, original in ipairs(lane.clips or {}) do
      local clip = copy_clip(original)
      clip.clip_id = ""
      if (clip.take_fx_count or 0) > 0 then result.has_unprocessed_fx = true end
      clip.media_hash = fs.hash_file(clip.media_path)
      clip.media_size = fs.file_size(clip.media_path)
      local blockers = effective_blockers(clip.blockers, input.publish_anyway)
      if not clip.media_hash or not clip.media_size then
        table.insert(blockers, "Source media is missing or unreadable")
      end
      local row = {
        clip = clip,
        status = #blockers == 0 and "Included" or "Blocked",
        blockers = blockers,
        display_name = clip.display_name,
      }
      if #blockers > 0 then
        result.blocker_count = result.blocker_count + math.max(1, #blockers)
      end
      table.insert(reviewed_lane.clips, row)
      table.insert(current_lane.clips, clip)
    end
    table.insert(result.lanes, reviewed_lane)
    table.insert(result.current.lanes, current_lane)
  end

  return result
end

return M
