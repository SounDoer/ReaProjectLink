local picture_manifest = require("readelivery.picture_manifest")

local snapshot, pointer = picture_manifest.build({
  picture_id = "picture-1",
  picture_revision = 3,
  mix_project_name = "CIN_030_MIX",
  published_at = "2026-09-13T14:00:00+08:00",
  published_by = "Alice",
  video_file = "//nas/show/CIN_030_v003.mov",
  video_hash = "abc123",
  sample_rate = 48000,
  picture_start_samples = 96000,
  source_offset_samples = 0,
  duration_samples = 144000,
  playback_rate = 1,
  frame_rate = { numerator = 24000, denominator = 1001, drop_frame = false },
  project_timecode_offset_samples = 3600000,
})

assert(snapshot.schemaVersion == 1, "schema version")
assert(snapshot.pictureId == "picture-1", "Picture identity")
assert(snapshot.pictureRevision == 3, "Picture revision")
assert(snapshot.videoHash == "sha256:abc123", "video hash")
assert(snapshot.frameRate.denominator == 1001, "frame-rate denominator")
assert(pointer.latestPictureRevision == 3, "stable pointer revision")
assert(pointer.manifest == "picture-history/picture-0003.json", "history path")

return 1
