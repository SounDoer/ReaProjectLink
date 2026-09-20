local json = require("readelivery.json")

local M = {}

local function required(input, key)
  local value = input[key]
  if value == nil or value == "" then
    error("missing Master Reference Manifest field: " .. key, 3)
  end
  return value
end

local function build_frame_rate(input)
  input = input or {}
  return {
    numerator = required(input, "numerator"),
    denominator = required(input, "denominator"),
    dropFrame = input.drop_frame ~= nil and input.drop_frame or input.dropFrame or false,
  }
end

local function build_lanes(input)
  local lanes = json.array(input or {})
  for _, lane in ipairs(lanes) do lane.items = json.array(lane.items or {}) end
  return lanes
end

function M.build(input)
  local revision = required(input, "picture_revision")
  local snapshot = {
    schemaVersion = 2,
    pictureId = required(input, "picture_id"),
    pictureRevision = revision,
    mixProjectName = required(input, "mix_project_name"),
    publishedAt = required(input, "published_at"),
    publishedBy = required(input, "published_by"),
    alignmentMode = input.alignment_mode or "mirror",
    timeline = {
      sampleRate = required(input, "sample_rate"),
      projectTimecodeOffsetSamples = required(input, "project_timecode_offset_samples"),
      frameRate = build_frame_rate(input.frame_rate),
      referenceStartSamples = input.reference_start_samples or 0,
      referenceRole = input.reference_role,
    },
    lanes = build_lanes(input.lanes),
    markers = json.array(input.markers or {}),
    regions = json.array(input.regions or {}),
  }
  local pointer = {
    schemaVersion = 2,
    pictureId = input.picture_id,
    latestPictureRevision = revision,
    manifest = string.format("picture-history/picture-%04d.json", revision),
  }
  return snapshot, pointer
end

return M
