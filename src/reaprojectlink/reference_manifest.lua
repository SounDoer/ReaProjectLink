local json = require("reaprojectlink.json")

local M = {}

local function required(input, key)
  local value = input[key]
  if value == nil or value == "" then
    error("missing Reference Manifest field: " .. key, 3)
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
  local revision = required(input, "reference_revision")
  local snapshot = {
    schemaVersion = 2,
    referenceId = required(input, "reference_id"),
    referenceRevision = revision,
    masterProjectId = required(input, "master_project_id"),
    masterProjectName = required(input, "master_project_name"),
    publishedAt = required(input, "published_at"),
    publishedBy = required(input, "published_by"),
    alignmentMode = input.alignment_mode or "mirror",
    timeline = {
      sampleRate = required(input, "sample_rate"),
      projectTimecodeOffsetSamples = required(input, "project_timecode_offset_samples"),
      frameRate = build_frame_rate(input.frame_rate),
      referenceStartSamples = input.reference_start_samples or 0,
      referenceStartMarkerId = input.reference_start_marker_id,
    },
    lanes = build_lanes(input.lanes),
    markers = json.array(input.markers or {}),
    regions = json.array(input.regions or {}),
  }
  local pointer = {
    schemaVersion = 2,
    masterProjectId = input.master_project_id,
    referenceId = input.reference_id,
    latestReferenceRevision = revision,
    manifest = string.format("history/reference-%04d.json", revision),
  }
  return snapshot, pointer
end

return M
