local M = {}

local function sanitize_name(value)
  value = value or ""
  value = value:gsub("[%z\1-\31<>:\"/\\|%?%*]", "_")
  value = value:gsub("%s+", "_"):gsub("_+", "_")
  value = value:gsub("^[%._ ]+", ""):gsub("[%._ ]+$", "")
  if value == "" then return "clip" end
  return value
end

local function clone_take(take)
  take = take or {}
  return {
    volume = take.volume,
    pan = take.pan,
    playback_rate = take.playback_rate,
    pitch = take.pitch,
    channel_mode = take.channel_mode,
    polarity_inverted = take.polarity_inverted,
  }
end

local function build_clip(clip, new_id, assignments, media)
  local clip_id = new_id()
  table.insert(assignments, { item_ref = clip.item_ref, clip_id = clip_id })
  local base_name = ((clip.display_name or ""):gsub("%.[Ww][Aa][Vv]$", ""))
  local filename = sanitize_name(base_name) .. ".wav"
  local destination = "media/" .. clip_id .. "/" .. filename
  table.insert(media, {
    source_path = clip.media_path,
    destination = destination,
    size = clip.media_size,
    hash = clip.media_hash,
  })
  return {
    clip_id = clip_id,
    display_name = clip.display_name,
    media_revision = 1,
    media_file = "../" .. destination,
    media_hash = "sha256:" .. clip.media_hash,
    media_sample_rate = clip.media_sample_rate,
    channel_count = clip.channel_count,
    start_offset_samples = clip.start_offset_samples,
    source_offset_samples = clip.source_offset_samples,
    length_samples = clip.length_samples,
    item_gain = clip.item_gain,
    fade_in_samples = clip.fade_in_samples,
    fade_out_samples = clip.fade_out_samples,
    take = clone_take(clip.take),
  }
end

function M.build(input, new_id)
  local source_project_id = input.source_project_id or new_id()
  local delivery_id = input.delivery_id or new_id()
  local delivery_revision = input.previous_snapshot and
    input.previous_snapshot.deliveryRevision + 1 or 1
  local lanes, assignments, media = {}, {}, {}

  for lane_index, lane in ipairs(input.current.lanes or {}) do
    local output_lane = {
      lane_id = lane.lane_id,
      display_name = lane.display_name,
      order = lane.order or lane_index - 1,
      clips = {},
    }
    for _, clip in ipairs(lane.clips or {}) do
      table.insert(output_lane.clips, build_clip(clip, new_id, assignments, media))
    end
    table.insert(lanes, output_lane)
  end

  return {
    source_project_id = source_project_id,
    delivery_id = delivery_id,
    delivery_revision = delivery_revision,
    assignments = assignments,
    media = media,
    snapshot_input = {
      source_project_id = source_project_id,
      delivery_id = delivery_id,
      source_project_name = input.source_project_name,
      source_project_file = input.source_project_file,
      delivery_revision = delivery_revision,
      published_at = input.published_at,
      published_by = input.published_by,
      reference_id = input.reference_id,
      reviewed_reference_revision = input.reviewed_reference_revision,
      sample_rate = input.sample_rate,
      lanes = lanes,
    },
  }
end

return M
