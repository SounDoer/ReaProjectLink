local delivery_publish_plan = require("reaprojectlink.delivery_publish_plan")

local ids = { "source-1", "delivery-1", "clip-1", "clip-2", "clip-3" }
local index = 0
local function new_id() index = index + 1; return ids[index] end

local function input(previous)
  return {
    source_project_id = previous and "source-1" or nil,
    delivery_id = previous and "delivery-1" or nil,
    source_project_name = "Music",
    source_project_file = "C:/show/Music.rpp",
    published_at = "2026-09-20T12:00:00+08:00",
    published_by = "Alice",
    reference_id = "reference-1",
    reviewed_reference_revision = 7,
    sample_rate = 48000,
    previous_snapshot = previous,
    current = { lanes = {{
      lane_id = "lane-1",
      display_name = "Music Print",
      clips = {{
        item_ref = "item-1",
        clip_id = "old-clip",
        display_name = "Cue A.wav",
        media_path = "C:/bounce/cue.wav",
        media_hash = "abc123",
        media_size = 100,
        start_offset_samples = 0,
        source_offset_samples = 0,
        length_samples = 48000,
      }},
    }}},
  }
end

local first = delivery_publish_plan.build(input(nil), new_id)
assert(first.source_project_id == "source-1", "new Source identity")
assert(first.delivery_id == "delivery-1", "new Delivery identity")
assert(first.delivery_revision == 1, "first Delivery Revision")
assert(first.snapshot_input.lanes[1].clips[1].clip_id == "clip-1", "fresh Clip identity")
assert(first.snapshot_input.lanes[1].clips[1].media_revision == 1, "revision-local media identity")
assert(first.media[1].destination == "media/clip-1/Cue_A.wav", "managed media path")
assert(first.assignments[1].item_ref == "item-1", "Source Item receives the new identity")

local second = delivery_publish_plan.build(input({ deliveryRevision = 1, lanes = first.snapshot_input.lanes }), new_id)
assert(second.delivery_revision == 2, "Delivery Revision advances")
assert(second.snapshot_input.lanes[1].clips[1].clip_id == "clip-2", "same Item gets a new Clip next Publish")
assert(second.snapshot_input.lanes[1].clips[1].media_revision == 1, "new Clip starts at Media Revision 1")
assert(#second.media == 1, "every snapshot copies its media independently")

return 2
