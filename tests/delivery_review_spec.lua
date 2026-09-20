local delivery_review = require("reaprojectlink.delivery_review")

local files = {
  ["new.wav"] = { hash = "new-hash", size = 20 },
  ["same.wav"] = { hash = "same-hash", size = 10 },
}
local fs = {}
function fs.hash_file(path) return files[path] and files[path].hash end
function fs.file_size(path) return files[path] and files[path].size end

local previous = {
  deliveryRevision = 4,
  lanes = {
    {
      laneId = "lane-1",
      displayName = "DX",
      clips = {
        {
          clipId = "clip-1",
          displayName = "Old line",
          mediaRevision = 2,
          mediaFile = "../media/clip-1/Old_line_r0002.wav",
          mediaHash = "sha256:same-hash",
          startOffsetSamples = 0,
          sourceOffsetSamples = 0,
          lengthSamples = 100,
          itemGain = 1,
          fadeInSamples = 0,
          fadeOutSamples = 0,
          take = { volume = 1, pan = 0, playbackRate = 1, pitch = 0, channelMode = 0, polarityInverted = false },
        },
        {
          clipId = "retired-1",
          displayName = "Removed line",
          mediaRevision = 1,
          mediaFile = "../media/retired-1/Removed_line_r0001.wav",
          mediaHash = "sha256:old-hash",
          startOffsetSamples = 200,
          sourceOffsetSamples = 0,
          lengthSamples = 100,
          take = {},
        },
      },
    },
  },
}

local current = {
  sample_rate = 48000,
  lanes = {
    {
      lane_id = "lane-1",
      display_name = "DX",
      order = 0,
      track_fx_count = 1,
      clips = {
        {
          item_ref = "item-1",
          clip_id = "clip-1",
          display_name = "Renamed line",
          media_path = "same.wav",
          blockers = {},
          start_offset_samples = 0,
          source_offset_samples = 0,
          length_samples = 100,
          item_gain = 1,
          fade_in_samples = 0,
          fade_out_samples = 0,
          take = { volume = 1, pan = 0, playback_rate = 1, pitch = 0, channel_mode = 0, polarity_inverted = false },
        },
        {
          item_ref = "item-2",
          clip_id = "",
          display_name = "New line",
          media_path = "new.wav",
          blockers = {},
          start_offset_samples = 200,
          source_offset_samples = 0,
          length_samples = 100,
          take = {},
        },
      },
    },
  },
}

local review = delivery_review.build({
  current = current,
  previous_snapshot = previous,
}, fs)

local function has_reason(suggestion, expected)
  for _, reason in ipairs(suggestion.reasons) do
    if reason == expected then return true end
  end
  return false
end

assert(review.delivery_revision == 5, "next Publish revision")
assert(review.lanes[1].clips[1].status == "Metadata Changed", "metadata comparison")
assert(review.lanes[1].clips[2].status == "Needs Decision", "untagged Item decision")
assert(review.lanes[1].clips[2].suggestions[1].clip_id == "retired-1", "same-Lane candidate")
assert(has_reason(review.lanes[1].clips[2].suggestions[1], "same timeline position"), "timeline reason")
assert(has_reason(review.lanes[1].clips[2].suggestions[1], "same duration"), "duration reason")
assert(review.retired[1].clip_id == "retired-1", "retired Clip")
assert(review.needs_decision_count == 1, "decision count")
assert(review.blocker_count == 2, "FX and unresolved identity block")

local resolved = delivery_review.build({
  current = current,
  previous_snapshot = previous,
  publish_anyway = true,
  identity_decisions = {
    ["item-2"] = { kind = "new" },
  },
}, fs)

assert(resolved.lanes[1].clips[2].status == "Added", "explicit new Clip")
assert(resolved.current.lanes[1].clips[2].confirmed_new, "publish-plan decision")
assert(resolved.blocker_count == 0, "explicit FX override")
assert(resolved.current.lanes[1].clips[1].media_hash == "same-hash", "current media hash")
assert(resolved.current.lanes[1].clips[1].media_size == 10, "current media size")

current.lanes[1].clips[2].blockers = {
  "Take FX will not be included; use Publish Unprocessed Media to continue",
}
local take_fx_blocked = delivery_review.build({
  current = current,
  previous_snapshot = previous,
  identity_decisions = { ["item-2"] = { kind = "new" } },
}, fs)
assert(take_fx_blocked.lanes[1].clips[2].status == "Blocked", "Take FX blocks by default")
local take_fx_overridden = delivery_review.build({
  current = current,
  previous_snapshot = previous,
  publish_anyway = true,
  identity_decisions = { ["item-2"] = { kind = "new" } },
}, fs)
assert(take_fx_overridden.lanes[1].clips[2].status == "Added", "Take FX override")
current.lanes[1].clips[2].blockers = {}

current.lanes[1].clips[1].display_name = "Old line"
local unchanged = delivery_review.build({
  current = current,
  previous_snapshot = previous,
  publish_anyway = true,
  identity_decisions = { ["item-2"] = { kind = "new" } },
}, fs)
assert(unchanged.lanes[1].clips[1].status == "Unchanged", "unchanged comparison")

current.lanes[1].clips[1].start_offset_samples = 1
local moved = delivery_review.build({
  current = current,
  previous_snapshot = previous,
  publish_anyway = true,
  identity_decisions = { ["item-2"] = { kind = "new" } },
}, fs)
assert(moved.lanes[1].clips[1].status == "Placement Changed", "placement comparison")

current.lanes[1].clips[1].start_offset_samples = 0
current.lanes[1].clips[1].media_path = "new.wav"
local changed = delivery_review.build({
  current = current,
  previous_snapshot = previous,
  publish_anyway = true,
  identity_decisions = { ["item-2"] = { kind = "link", clip_id = "retired-1" } },
}, fs)
assert(changed.lanes[1].clips[1].status == "Audio Changed", "audio comparison")
assert(changed.lanes[1].clips[2].clip_id == "retired-1", "explicit identity link")
assert(changed.lanes[1].clips[2].status == "Audio Changed", "linked revision comparison")
assert(#changed.retired == 0, "linked Clip is not retired")

current.lanes[1].clips[2].clip_id = "clip-1"
local duplicated = delivery_review.build({
  current = current,
  previous_snapshot = previous,
  publish_anyway = true,
}, fs)
assert(duplicated.blocker_count == 2, "each duplicate identity blocks")
assert(duplicated.lanes[1].clips[1].status == "Needs Decision", "first duplicate is resolvable")
assert(duplicated.lanes[1].clips[2].status == "Needs Decision", "second duplicate is resolvable")
assert(duplicated.lanes[1].clips[1].duplicate, "duplicate rows offer the keep decision")

local duplicate_resolved = delivery_review.build({
  current = current,
  previous_snapshot = previous,
  publish_anyway = true,
  identity_decisions = {
    ["item-1"] = { kind = "keep" },
    ["item-2"] = { kind = "new" },
  },
}, fs)
assert(duplicate_resolved.blocker_count == 0, "resolved duplicates stop blocking")
assert(duplicate_resolved.lanes[1].clips[1].clip_id == "clip-1", "the kept Item continues the lineage")
assert(duplicate_resolved.lanes[1].clips[2].status == "Added", "the other Item becomes a new Clip")
assert(
  duplicate_resolved.lanes[1].clips[2].clip.confirmed_new,
  "the new Clip is assigned an identity on Publish"
)

local contested = delivery_review.build({
  current = current,
  previous_snapshot = previous,
  publish_anyway = true,
  identity_decisions = {
    ["item-1"] = { kind = "keep" },
    ["item-2"] = { kind = "keep" },
  },
}, fs)
assert(contested.blocker_count == 2, "two Items cannot keep one Clip ID")
assert(contested.lanes[1].clips[1].status == "Blocked", "contested lineage blocks")
assert(contested.lanes[1].clips[1].duplicate, "a contested Item can still be decided again")
assert(
  duplicate_resolved.lanes[1].clips[1].duplicate,
  "a resolved Item can still be decided again"
)

return 7
