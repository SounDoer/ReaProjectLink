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

local function previous_clips_by_id(snapshot)
  local result = {}
  for _, lane in ipairs(snapshot and snapshot.lanes or {}) do
    for _, clip in ipairs(lane.clips or {}) do
      result[clip.clipId] = clip
    end
  end
  return result
end

local function raw_hash(value)
  return value and value:gsub("^sha256:", "") or nil
end

local function build_clip(clip, previous_clips, has_previous, new_id, assignments, media)
  local clip_id = clip.clip_id
  local created = false
  if not clip_id or clip_id == "" then
    if not clip.confirmed_new then
      error("untagged Item requires an explicit identity decision", 3)
    end
    clip_id = new_id()
    created = true
    table.insert(assignments, { item_ref = clip.item_ref, clip_id = clip_id })
  end

  local previous = previous_clips[clip_id]
  if has_previous and not previous and not created then
    error("unknown Clip ID requires an explicit identity decision: " .. clip_id, 3)
  end
  local unchanged = previous and raw_hash(previous.mediaHash) == clip.media_hash
  local media_revision = unchanged and previous.mediaRevision or
    ((previous and previous.mediaRevision or 0) + 1)
  local media_file

  if unchanged then
    media_file = previous.mediaFile
  else
    -- REAPER Item names usually carry the source extension already.
    local base_name = ((clip.display_name or ""):gsub("%.[Ww][Aa][Vv]$", ""))
    local filename = string.format(
      "%s_r%04d.wav",
      sanitize_name(base_name),
      media_revision
    )
    local destination = "media/" .. clip_id .. "/" .. filename
    media_file = "../" .. destination
    table.insert(media, {
      source_path = clip.media_path,
      destination = destination,
      size = clip.media_size,
      hash = clip.media_hash,
    })
  end

  return {
    clip_id = clip_id,
    display_name = clip.display_name,
    media_revision = media_revision,
    media_file = media_file,
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
  local delivery_set_id = input.delivery_set_id or new_id()
  local publish_revision = input.previous_snapshot and
    input.previous_snapshot.publishRevision + 1 or 1
  local lanes = {}
  local assignments = {}
  local media = {}
  local previous_clips = previous_clips_by_id(input.previous_snapshot)

  for lane_index, lane in ipairs(input.current.lanes or {}) do
    local output_lane = {
      lane_id = lane.lane_id,
      display_name = lane.display_name,
      order = lane.order or lane_index - 1,
      clips = {},
    }
    for _, clip in ipairs(lane.clips or {}) do
      table.insert(
        output_lane.clips,
        build_clip(
          clip,
          previous_clips,
          input.previous_snapshot ~= nil,
          new_id,
          assignments,
          media
        )
      )
    end
    table.insert(lanes, output_lane)
  end

  return {
    source_project_id = source_project_id,
    delivery_set_id = delivery_set_id,
    publish_revision = publish_revision,
    assignments = assignments,
    media = media,
    snapshot_input = {
      source_project_id = source_project_id,
      delivery_set_id = delivery_set_id,
      source_project_name = input.source_project_name,
      source_project_file = input.source_project_file,
      publish_revision = publish_revision,
      published_at = input.published_at,
      published_by = input.published_by,
      picture_id = input.picture_id,
      reviewed_picture_revision = input.reviewed_picture_revision,
      sample_rate = input.sample_rate,
      lanes = lanes,
    },
  }
end

return M
