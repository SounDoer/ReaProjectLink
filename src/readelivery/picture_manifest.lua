local M = {}

local function required(input, key)
  local value = input[key]
  if value == nil or value == "" then
    error("missing Picture Manifest field: " .. key, 3)
  end
  return value
end

function M.build(input)
  local revision = required(input, "picture_revision")
  local snapshot = {
    schemaVersion = 1,
    pictureId = required(input, "picture_id"),
    pictureRevision = revision,
    mixProjectName = required(input, "mix_project_name"),
    publishedAt = required(input, "published_at"),
    publishedBy = required(input, "published_by"),
    videoFile = required(input, "video_file"),
    videoHash = "sha256:" .. required(input, "video_hash"),
    sampleRate = required(input, "sample_rate"),
    pictureStartSamples = required(input, "picture_start_samples"),
    sourceOffsetSamples = required(input, "source_offset_samples"),
    durationSamples = required(input, "duration_samples"),
    playbackRate = required(input, "playback_rate"),
    frameRate = {
      numerator = required(input.frame_rate or {}, "numerator"),
      denominator = required(input.frame_rate or {}, "denominator"),
      dropFrame = input.frame_rate and input.frame_rate.drop_frame or false,
    },
    projectTimecodeOffsetSamples = required(input, "project_timecode_offset_samples"),
  }
  local pointer = {
    schemaVersion = 1,
    pictureId = input.picture_id,
    latestPictureRevision = revision,
    manifest = string.format("picture-history/picture-%04d.json", revision),
  }
  return snapshot, pointer
end

return M
