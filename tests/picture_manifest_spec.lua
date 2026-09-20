local picture_manifest = require("readelivery.picture_manifest")
local json = require("readelivery.json")

local snapshot, pointer = picture_manifest.build({
  picture_id = "picture-1",
  picture_revision = 3,
  mix_project_name = "CIN_030_MIX",
  published_at = "2026-09-13T14:00:00+08:00",
  published_by = "Alice",
  sample_rate = 48000,
  reference_start_samples = 96000,
  reference_role = "FFOP",
  frame_rate = { numerator = 24000, denominator = 1001, drop_frame = false },
  project_timecode_offset_samples = 3600000,
  lanes = {
    {
      laneId = "lane-1",
      displayName = "Picture Main",
      order = 0,
      items = {
        {
          itemId = "item-1",
          videoFile = "//nas/show/CIN_030_v003.mov",
          videoHash = "sha256:abc123",
          startSamples = 96000,
          sourceOffsetSamples = 0,
          durationSamples = 144000,
          playbackRate = 1,
        },
      },
    },
  },
  markers = { { entryId = "marker-1", name = "FFOP", startSamples = 96000, semanticRole = "FFOP" } },
  regions = {},
})

assert(snapshot.schemaVersion == 2, "schema version")
assert(snapshot.pictureId == "picture-1", "Picture identity")
assert(snapshot.pictureRevision == 3, "Picture revision")
assert(snapshot.lanes[1].items[1].videoHash == "sha256:abc123", "video hash")
assert(snapshot.timeline.frameRate.denominator == 1001, "frame-rate denominator")
assert(snapshot.timeline.referenceRole == "FFOP", "semantic Reference Start")
assert(json.encode(snapshot.regions) == "[]", "empty Regions encode as an array")
assert(pointer.latestPictureRevision == 3, "stable pointer revision")
assert(pointer.manifest == "picture-history/picture-0003.json", "history path")

return 1
