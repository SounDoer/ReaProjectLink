local json = require("readelivery.json")
local mix_update = require("readelivery.mix_update")

local root = "C:/source/_Delivery/DX"
local pointer_path = root .. "/delivery.json"
local pointer = {
  schemaVersion = 1,
  sourceProjectId = "source-1",
  deliverySetId = "set-1",
  latestPublishRevision = 2,
  manifest = "history/publish-0002.json",
}
local function snapshot(revision, media_revision, position)
  return {
    schemaVersion = 1,
    sourceProjectId = "source-1",
    deliverySetId = "set-1",
    sourceProjectName = "DX",
    publishRevision = revision,
    sampleRate = 48000,
    picture = { pictureId = "picture-1", reviewedRevision = 7 },
    lanes = {
      {
        laneId = "lane-1",
        clips = {
          {
            clipId = "clip-1",
            displayName = "Line",
            mediaRevision = media_revision,
            mediaFile = "../media/clip-1/Line_r000" .. media_revision .. ".wav",
            mediaHash = "sha256:hash-" .. media_revision,
            startOffsetSamples = position,
            sourceOffsetSamples = 0,
            lengthSamples = 48000,
            itemGain = 1,
            fadeInSamples = 0,
            fadeOutSamples = 0,
            take = { volume = 1, pan = 0, playbackRate = 1, pitch = 0, channelMode = 0, polarityInverted = false },
          },
        },
      },
    },
  }
end
local baseline = snapshot(1, 1, 0)
local latest = snapshot(2, 2, 24000)
table.insert(latest.lanes[1].clips, {
  clipId = "clip-2",
  displayName = "New Line",
  mediaRevision = 1,
  mediaFile = "../media/clip-2/New_Line_r0001.wav",
  mediaHash = "sha256:hash-new",
  startOffsetSamples = 96000,
  sourceOffsetSamples = 0,
  lengthSamples = 24000,
  take = {},
})
table.insert(latest.lanes, {
  laneId = "lane-2",
  displayName = "New Lane",
  order = 1,
  clips = {},
})
local media_path = root .. "/media/clip-1/Line_r0002.wav"
local old_media_path = root .. "/media/clip-1/Line_r0001.wav"
local new_media_path = root .. "/media/clip-2/New_Line_r0001.wav"
local files = {
  [pointer_path] = json.encode(pointer),
  [root .. "/history/publish-0001.json"] = json.encode(baseline),
  [root .. "/history/publish-0002.json"] = json.encode(latest),
  [media_path] = "media-2",
  [old_media_path] = "media-1",
  [new_media_path] = "media-new",
}
local fs = {}
function fs.read_file(path) return files[path] end
function fs.hash_file(path)
  if path == media_path then return "hash-2" end
  if path == old_media_path then return "hash-1" end
  if path == new_media_path then return "hash-new" end
end
function fs.join(...) return table.concat({ ... }, "/"):gsub("/+", "/") end

local subscriptions = {
  {
    pointerPath = pointer_path,
    sourceProjectId = "source-1",
    deliverySetId = "set-1",
    acceptedPublishRevision = 1,
    lanes = { { laneId = "lane-1", trackGuid = "track-1" } },
  },
}
local values = {
  project_mode = "mix",
  picture_id = "picture-1",
  picture_revision = "7",
  picture_start_samples = "96000",
  source_subscriptions = json.encode(subscriptions),
}
local first_item, second_item = {}, {}
local events = {}
local duplicate_instances = false
local stale_instance_state = false
local adapter = {}
function adapter.get_project_value(key) return values[key] end
function adapter.set_project_value(key, value) values[key] = value end
function adapter.project_sample_rate() return 48000 end
function adapter.all_tracks() return { { guid = "existing-track", name = "New Lane Target" } } end
function adapter.track_guid(track) return track.guid end
function adapter.track_name(track) return track.name end
function adapter.delivery_instances()
  return {
    {
      item_ref = first_item,
      track_ref = { guid = "moved-track", name = "DX A Alt" },
      clip_id = "clip-1",
      instance_id = "instance-1",
      accepted_media_revision = 1,
      handled_publish_revision = 1,
      state = { position_seconds = 0, length_seconds = 1, source_offset_seconds = 0, item_gain = 1, fade_in_seconds = 0, fade_out_seconds = 0, take_volume = 1, take_pan = 0, take_playback_rate = 1, take_pitch = 0, take_channel_mode = 0, take_polarity_inverted = false },
    },
    {
      item_ref = second_item,
      track_ref = { guid = "track-1", name = "DX A" },
      clip_id = "clip-1",
      instance_id = duplicate_instances and "instance-1" or "instance-2",
      accepted_media_revision = 1,
      handled_publish_revision = 1,
      state = { position_seconds = 0.25, length_seconds = 1, source_offset_seconds = 0, item_gain = 1, fade_in_seconds = 0, fade_out_seconds = 0, take_volume = 1, take_pan = 0, take_playback_rate = 1, take_pitch = 0, take_channel_mode = 0, take_polarity_inverted = false },
    },
  }
end
function adapter.valid_item() return true end
function adapter.delivery_instance_state(item)
  for _, instance in ipairs(adapter.delivery_instances()) do
    if instance.item_ref == item then
      local state = {}
      for key, value in pairs(instance.state) do state[key] = value end
      if stale_instance_state and item == first_item then
        state.position_seconds = state.position_seconds + 1
      end
      return state
    end
  end
end
function adapter.begin_undo() table.insert(events, "begin") end
function adapter.end_undo() table.insert(events, "end") end
function adapter.add_delivery_take(item, clip, path) table.insert(events, { "take", item, path }); return true end
function adapter.apply_delivery_fields(item, fields) table.insert(events, { "fields", item, fields }); return true end
function adapter.set_instance_revisions(item, media_revision, publish_revision)
  table.insert(events, { "revisions", item, media_revision, publish_revision })
end
function adapter.new_id() return "instance-repaired" end
function adapter.set_instance_id(item, instance_id)
  table.insert(events, { "instance", item, instance_id })
end
function adapter.detach_instance(item)
  table.insert(events, { "detach", item })
  return true
end
function adapter.mark_project_dirty() table.insert(events, "dirty") end
function adapter.track_by_guid(guid)
  if guid == "track-1" then return { guid = guid, name = "DX A" } end
end
function adapter.create_delivery_item(track, clip, context)
  table.insert(events, { "new item", track, clip, context })
  return { track = track, clip = clip, context = context }
end

local review, review_error = mix_update.review(adapter, fs, "source-1")
assert(review, review_error)
assert(review.latest_revision == 2, "latest revision")
assert(#review.instances == 2, "every linked Instance reviewed")
assert(review.instances[1].plan.media.pending, "media update pending")
assert(review.instances[1].plan.fields.position_seconds.choice == "use_source", "Source-only placement")
assert(review.instances[2].plan.fields.position_seconds.kind == "conflict", "local placement conflict")
assert(review.additions[1].clip.clipId == "clip-2", "new Clip detected")
assert(review.unmapped_lanes[1].lane_id == "lane-2", "new Lane requires mapping")
assert(review.unmapped_lanes[1].suggestions[1].track_guid == "existing-track", "new Lane offers existing Tracks")
assert(review.pending_count > 0, "a real update reports pending work")
assert(
  review.bound_lanes[1].lane_id == "lane-1" and review.bound_lanes[1].track_name == "DX A",
  "a mapped Lane reports where its new Clips land"
)
assert(review.instances[1].display_name == "Line", "Instances are labelled by Clip name")
assert(
  review.instances[2].clip_instance_index == 2 and review.instances[2].clip_instance_total == 2,
  "Instances sharing one Clip are numbered"
)

local idle, idle_error = mix_update.apply({ pending_count = 0 }, adapter, {})
assert(not idle and idle_error == "Nothing to update.", "an up-to-date Source is not applied")

local apply_options = {
  instances = {
    ["instance-1"] = { media_choice = "accept_new_take" },
    ["instance-2"] = { media_choice = "skip" },
  },
  additions = { ["clip-2"] = "import" },
  lane_mappings = { ["lane-2"] = { kind = "skip" } },
}
stale_instance_state = true
local stale, stale_error = mix_update.apply(review, adapter, apply_options)
assert(not stale and stale_error:find("changed after Update Review", 1, true),
  "a locally edited Item makes Update Review stale")
stale_instance_state = false

values.picture_start_samples = "144000"
local stale_picture, stale_picture_error = mix_update.apply(review, adapter, apply_options)
assert(
  not stale_picture and stale_picture_error:find("Picture state changed", 1, true),
  "a changed Picture anchor makes Update Review stale"
)
values.picture_start_samples = "96000"

local result, apply_error = mix_update.apply(review, adapter, {
  instances = {
    ["instance-1"] = { media_choice = "accept_new_take" },
    ["instance-2"] = { media_choice = "skip" },
  },
  additions = { ["clip-2"] = "import" },
  lane_mappings = { ["lane-2"] = { kind = "skip" } },
})
assert(result, apply_error)
assert(result.new_takes == 1, "only included Instance gets a Take")
assert(result.new_items == 1, "new Clip imported to bound Lane")
assert(events[1] == "begin" and events[#events] == "end", "one update undo point")
local stored = json.decode(values.source_subscriptions)
assert(stored[1].acceptedPublishRevision == 2, "subscription revision advances")
assert(stored[1].lanes[2].skipped, "new Lane mapping decision persisted")

duplicate_instances = true
local duplicate_review = assert(mix_update.review(adapter, fs, "source-1"))
assert(duplicate_review.instances[2].needs_new_instance_id, "copied Instance identity detected")
assert(duplicate_review.instances[2].decision_key == "instance-1#2", "duplicate has unique review key")
local repaired = assert(mix_update.apply(duplicate_review, adapter, {
  instances = {
    ["instance-1"] = { media_choice = "skip" },
    ["instance-1#2"] = { media_choice = "skip" },
  },
  additions = { ["clip-2"] = "skip" },
  lane_mappings = { ["lane-2"] = { kind = "skip" } },
}))
assert(repaired.reassigned_instances == 1, "copied Instance receives a new identity")

local detached = assert(mix_update.detach(adapter, first_item))
assert(detached.item_ref == first_item, "explicit detach result")

duplicate_instances = false
local orphaned_subscriptions = json.decode(values.source_subscriptions)
orphaned_subscriptions[1].lanes[1].trackGuid = "deleted-track"
orphaned_subscriptions[1].declinedClips = nil
values.source_subscriptions = json.encode(orphaned_subscriptions)
local orphaned = assert(mix_update.review(adapter, fs, "source-1"))
local orphaned_lane
for _, lane in ipairs(orphaned.unmapped_lanes) do
  if lane.lane_id == "lane-1" then orphaned_lane = lane end
end
assert(orphaned_lane, "a Lane whose Mix Track was deleted can be mapped again")
assert(orphaned_lane.orphaned, "the Lane reports why it lost its mapping")
assert(#orphaned_lane.clips == 1, "Clips that still have an Instance are not imported twice")
assert(orphaned_lane.clips[1].clipId == "clip-2", "only the Clip without an Instance is restored")
assert(
  orphaned_lane.present_clips[1].clip_id == "clip-1" and
    orphaned_lane.present_clips[1].track_name == "DX A Alt",
  "a Clip that already has an Instance is reported with the Track holding it"
)
assert(
  orphaned_lane.suggestions[1].track_guid == "moved-track",
  "the Track already holding the Clips is suggested first"
)

values.source_subscriptions = json.encode(subscriptions)
local rebind_review = assert(mix_update.review(adapter, fs, "source-1"))
local rebound = assert(mix_update.apply(rebind_review, adapter, {
  instances = {
    ["instance-1"] = { media_choice = "skip" },
    ["instance-2"] = { media_choice = "skip" },
  },
  additions = { ["clip-2"] = "skip" },
  lane_mappings = { ["lane-2"] = { kind = "skip" } },
  lane_rebindings = { ["lane-1"] = { guid = "track-9" } },
}))
assert(rebound.rebound_lanes == 1, "a mapped Lane can be pointed at another Track")
assert(
  json.decode(values.source_subscriptions)[1].lanes[1].trackGuid == "track-9",
  "rebinding is stored with the subscription"
)

-- Deleting every Item must not hide the Clips behind an accepted revision.
values.source_subscriptions = json.encode(subscriptions)
local linked_instances = adapter.delivery_instances
adapter.delivery_instances = function() return {} end
local emptied = assert(mix_update.review(adapter, fs, "source-1"))
assert(#emptied.instances == 0, "deleted Items leave no Instances")
local offered = {}
for _, addition in ipairs(emptied.additions) do offered[addition.clip.clipId] = true end
assert(offered["clip-1"] and offered["clip-2"], "a Clip without an Item is offered again")

local declined_apply = assert(mix_update.apply(emptied, adapter, {
  additions = { ["clip-1"] = "skip", ["clip-2"] = "import" },
  lane_mappings = { ["lane-2"] = { kind = "skip" } },
}))
assert(declined_apply.new_items == 1, "only the imported Clip creates an Item")
assert(
  json.decode(values.source_subscriptions)[1].declinedClips[1] == "clip-1",
  "declining a Clip outlives the revision that offered it"
)
local declined_review = assert(mix_update.review(adapter, fs, "source-1"))
assert(
  #declined_review.additions == 1 and declined_review.additions[1].clip.clipId == "clip-2",
  "a declined Clip is not offered again"
)
assert(
  declined_review.declined_clips[1].clip_id == "clip-1",
  "a declined Clip stays visible in the review"
)
assert(mix_update.undecline(adapter, "source-1", "clip-1"), "a decline can be undone")
assert(#mix_update.review(adapter, fs, "source-1").additions == 2, "an undeclined Clip returns")

local rolled_back = assert(mix_update.review(adapter, fs, "source-1", 1))
assert(
  rolled_back.target_revision == 1 and rolled_back.latest_revision == 2,
  "any published revision can be targeted"
)
assert(rolled_back.blocker_count == 0, "an older target uses its own media")
assert(
  #rolled_back.additions == 1 and rolled_back.additions[1].clip.clipId == "clip-1",
  "an older target only offers the Clips it published"
)
local unpublished, revision_error = mix_update.review(adapter, fs, "source-1", 3)
assert(
  not unpublished and revision_error == "Requested Delivery revision was never published.",
  "an unpublished revision cannot be targeted"
)
adapter.delivery_instances = linked_instances

latest.sourceProjectId = "other-source"
files[root .. "/history/publish-0002.json"] = json.encode(latest)
local wrong_identity, wrong_identity_error = mix_update.review(adapter, fs, "source-1")
assert(
  not wrong_identity and wrong_identity_error:find("sourceProjectId", 1, true),
  "a target snapshot from another Source is rejected"
)
latest.sourceProjectId = "source-1"
files[root .. "/history/publish-0002.json"] = json.encode(latest)

return 11
