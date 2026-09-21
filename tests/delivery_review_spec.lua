local delivery_review = require("reaprojectlink.delivery_review")

local files = {
  ["one.wav"] = { hash = "hash-one", size = 10 },
  ["two.wav"] = { hash = "hash-two", size = 20 },
}
local fs = {}
function fs.hash_file(path) return files[path] and files[path].hash end
function fs.file_size(path) return files[path] and files[path].size end

local current = {
  sample_rate = 48000,
  lanes = {{
    lane_id = "lane-1",
    display_name = "Music",
    order = 0,
    track_fx_count = 1,
    clips = {
      { item_ref = "item-1", clip_id = "old-clip", display_name = "One.wav", media_path = "one.wav", blockers = {} },
      { item_ref = "item-2", clip_id = "old-clip", display_name = "Two.wav", media_path = "two.wav", blockers = {} },
    },
  }},
}
local previous = { deliveryRevision = 4, lanes = {} }

local blocked = delivery_review.build({ current = current, previous_snapshot = previous }, fs)
assert(blocked.delivery_revision == 5, "next Delivery Revision")
assert(blocked.blocker_count == 1, "Track FX remains the only blocker")
assert(blocked.has_unprocessed_fx, "Track FX is reported")
assert(blocked.lanes[1].clips[1].status == "Included", "all readable Items are included")
assert(blocked.lanes[1].clips[2].status == "Included", "duplicate old Clip IDs need no decision")
assert(blocked.current.lanes[1].clips[1].clip_id == "", "old Clip identity is discarded")
assert(blocked.current.lanes[1].clips[2].clip_id == "", "every Item gets a fresh identity")

local ready = delivery_review.build({
  current = current,
  previous_snapshot = previous,
  publish_anyway = true,
}, fs)
assert(ready.blocker_count == 0, "FX override permits the complete snapshot")
assert(ready.current.lanes[1].clips[1].media_hash == "hash-one", "media hash captured")
assert(ready.current.lanes[1].clips[2].media_size == 20, "media size captured")

current.lanes[1].track_fx_count = 0
current.lanes[1].clips[2].blockers = {
  "Take FX will not be included; use Publish Unprocessed Media to continue",
}
current.lanes[1].clips[2].take_fx_count = 1
local take_fx = delivery_review.build({ current = current, previous_snapshot = previous }, fs)
assert(take_fx.lanes[1].clips[2].status == "Blocked", "Take FX blocks by default")
local overridden = delivery_review.build({
  current = current,
  previous_snapshot = previous,
  publish_anyway = true,
}, fs)
assert(overridden.lanes[1].clips[2].status == "Included", "Take FX override includes the Item")

current.lanes[1].clips[2].media_path = "missing.wav"
current.lanes[1].clips[2].blockers = {}
current.lanes[1].clips[2].take_fx_count = 0
local missing = delivery_review.build({ current = current, previous_snapshot = previous }, fs)
assert(missing.lanes[1].clips[2].status == "Blocked", "missing media blocks Publish")

return 4
