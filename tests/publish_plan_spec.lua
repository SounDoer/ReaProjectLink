local publish_plan = require("readelivery.publish_plan")

local ids = { "source-1", "set-1", "clip-1" }
local id_index = 0
local function new_id()
  id_index = id_index + 1
  return ids[id_index]
end

local plan = publish_plan.build({
  source_project_name = "CIN_030_DX",
  source_project_file = "C:/show/CIN_030_DX.rpp",
  published_at = "2026-09-13T12:00:00+08:00",
  published_by = "Alice",
  picture_id = "picture-1",
  reviewed_picture_revision = 7,
  sample_rate = 48000,
  current = {
    lanes = {
      {
        lane_id = "lane-1",
        display_name = "DX Print",
        order = 0,
        clips = {
          {
            item_ref = "item-1",
            confirmed_new = true,
            display_name = "Commander Radio Close",
            media_path = "C:/bounce/latest.wav",
            media_hash = "abc123",
            media_size = 100,
            start_offset_samples = 24000,
            source_offset_samples = 0,
            length_samples = 48000,
          },
        },
      },
    },
  },
}, new_id)

assert(plan.source_project_id == "source-1", "new Source identity")
assert(plan.delivery_set_id == "set-1", "new Delivery Set identity")
assert(plan.publish_revision == 1, "first Publish revision")
assert(plan.snapshot_input.lanes[1].clips[1].clip_id == "clip-1", "new Clip identity")
assert(plan.snapshot_input.lanes[1].clips[1].media_revision == 1, "first media revision")
assert(
  plan.snapshot_input.lanes[1].clips[1].media_file ==
    "../media/clip-1/Commander_Radio_Close_r0001.wav",
  "managed manifest path"
)
assert(plan.media[1].destination == "media/clip-1/Commander_Radio_Close_r0001.wav", "copy target")
assert(plan.assignments[1].item_ref == "item-1", "identity assignment target")

local unchanged = publish_plan.build({
  source_project_id = "source-1",
  delivery_set_id = "set-1",
  source_project_name = "CIN_030_DX",
  source_project_file = "C:/show/CIN_030_DX.rpp",
  published_at = "2026-09-13T12:10:00+08:00",
  published_by = "Alice",
  picture_id = "picture-1",
  reviewed_picture_revision = 7,
  sample_rate = 48000,
  previous_snapshot = {
    publishRevision = 1,
    lanes = {
      {
        laneId = "lane-1",
        clips = {
          {
            clipId = "clip-1",
            displayName = "Old Name",
            mediaRevision = 3,
            mediaFile = "../media/clip-1/Old_Name_r0003.wav",
            mediaHash = "sha256:abc123",
          },
        },
      },
    },
  },
  current = {
    lanes = {
      {
        lane_id = "lane-1",
        display_name = "DX Print",
        clips = {
          {
            item_ref = "item-1",
            clip_id = "clip-1",
            display_name = "Renamed Clip",
            media_path = "C:/bounce/latest.wav",
            media_hash = "abc123",
            media_size = 100,
            start_offset_samples = 24000,
            source_offset_samples = 0,
            length_samples = 48000,
          },
        },
      },
    },
  },
}, new_id)

local unchanged_clip = unchanged.snapshot_input.lanes[1].clips[1]
assert(unchanged.publish_revision == 2, "Publish revision advances")
assert(unchanged_clip.media_revision == 3, "unchanged media keeps its revision")
assert(unchanged_clip.media_file == "../media/clip-1/Old_Name_r0003.wav", "unchanged media keeps its file")
assert(#unchanged.media == 0, "unchanged media is not copied again")

local changed_input = {
  source_project_id = "source-1",
  delivery_set_id = "set-1",
  source_project_name = "CIN_030_DX",
  source_project_file = "C:/show/CIN_030_DX.rpp",
  published_at = "2026-09-13T12:20:00+08:00",
  published_by = "Alice",
  picture_id = "picture-1",
  reviewed_picture_revision = 7,
  sample_rate = 48000,
  previous_snapshot = {
    publishRevision = 3,
    lanes = {
      {
        laneId = "lane-1",
        clips = {
          {
            clipId = "clip-1",
            mediaRevision = 3,
            mediaFile = "../media/clip-1/Old_Name_r0003.wav",
            mediaHash = "sha256:abc123",
          },
        },
      },
    },
  },
  current = {
    lanes = {
      {
        lane_id = "lane-1",
        display_name = "DX Print",
        clips = {
          {
            item_ref = "item-1",
            clip_id = "clip-1",
            display_name = "Renamed Clip",
            media_path = "C:/bounce/latest.wav",
            media_hash = "def456",
            media_size = 120,
            start_offset_samples = 24000,
            source_offset_samples = 0,
            length_samples = 48000,
          },
        },
      },
    },
  },
}

local changed = publish_plan.build(changed_input, new_id)
local changed_clip = changed.snapshot_input.lanes[1].clips[1]
assert(changed.publish_revision == 4, "changed Publish revision")
assert(changed_clip.media_revision == 4, "changed media increments its revision")
assert(changed_clip.media_file == "../media/clip-1/Renamed_Clip_r0004.wav", "changed media gets a new file")
assert(changed.media[1].destination == "media/clip-1/Renamed_Clip_r0004.wav", "changed media is copied")

changed_input.current.lanes[1].clips[1].clip_id = "missing-clip"
local ok, err = pcall(publish_plan.build, changed_input, new_id)
assert(not ok and err:find("unknown Clip ID", 1, true), "unknown Clip identity is blocked")

return 3
