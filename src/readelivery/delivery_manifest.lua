local json = require("readelivery.json")

local M = {}

local function required(input, key)
  local value = input[key]
  if value == nil or value == "" then
    error("missing delivery manifest field: " .. key, 3)
  end
  return value
end

local function build_take(take)
  take = take or {}
  return {
    volume = take.volume,
    pan = take.pan,
    playbackRate = take.playback_rate,
    pitch = take.pitch,
    channelMode = take.channel_mode,
    polarityInverted = take.polarity_inverted,
  }
end

local function build_clip(clip)
  return {
    clipId = required(clip, "clip_id"),
    displayName = clip.display_name,
    mediaRevision = required(clip, "media_revision"),
    mediaFile = required(clip, "media_file"),
    mediaHash = required(clip, "media_hash"),
    mediaSampleRate = clip.media_sample_rate,
    channelCount = clip.channel_count,
    startOffsetSamples = required(clip, "start_offset_samples"),
    sourceOffsetSamples = required(clip, "source_offset_samples"),
    lengthSamples = required(clip, "length_samples"),
    itemGain = clip.item_gain,
    fadeInSamples = clip.fade_in_samples,
    fadeOutSamples = clip.fade_out_samples,
    take = build_take(clip.take),
  }
end

local function build_lane(lane, fallback_order)
  local clips = json.array()
  for _, clip in ipairs(lane.clips or {}) do
    table.insert(clips, build_clip(clip))
  end
  return {
    laneId = required(lane, "lane_id"),
    displayName = lane.display_name,
    order = lane.order or fallback_order,
    clips = clips,
  }
end

function M.build(input)
  local revision = required(input, "publish_revision")
  local lanes = json.array()
  for index, lane in ipairs(input.lanes or {}) do
    table.insert(lanes, build_lane(lane, index - 1))
  end

  local snapshot = {
    schemaVersion = 1,
    sourceProjectId = required(input, "source_project_id"),
    deliverySetId = required(input, "delivery_set_id"),
    sourceProjectName = required(input, "source_project_name"),
    sourceProjectFile = input.source_project_file,
    publishRevision = revision,
    publishedAt = required(input, "published_at"),
    publishedBy = required(input, "published_by"),
    picture = {
      pictureId = required(input, "picture_id"),
      reviewedRevision = required(input, "reviewed_picture_revision"),
    },
    sampleRate = required(input, "sample_rate"),
    lanes = lanes,
  }

  local pointer = {
    schemaVersion = 1,
    sourceProjectId = input.source_project_id,
    deliverySetId = input.delivery_set_id,
    latestPublishRevision = revision,
    manifest = string.format("history/publish-%04d.json", revision),
  }

  return snapshot, pointer
end

return M
