local json = require("readelivery.json")
local mix_import = require("readelivery.mix_import")

local pointer_path = "C:/source/_Delivery/DX/delivery.json"
local snapshot_path = "C:/source/_Delivery/DX/history/publish-0002.json"
local media_path = "C:/source/_Delivery/DX/media/clip-1/Line_r0002.wav"
local pointer = {
  schemaVersion = 1,
  sourceProjectId = "source-1",
  deliverySetId = "set-1",
  latestPublishRevision = 2,
  manifest = "history/publish-0002.json",
}
local snapshot = {
  schemaVersion = 1,
  sourceProjectId = "source-1",
  deliverySetId = "set-1",
  sourceProjectName = "DX",
  publishRevision = 2,
  picture = { pictureId = "picture-1", reviewedRevision = 6 },
  sampleRate = 48000,
  lanes = {
    {
      laneId = "lane-1",
      displayName = "DX Main",
      order = 0,
      clips = {
        {
          clipId = "clip-1",
          displayName = "Line",
          mediaRevision = 2,
          mediaFile = "../media/clip-1/Line_r0002.wav",
          mediaHash = "sha256:media-hash",
          startOffsetSamples = 48000,
          sourceOffsetSamples = 2400,
          lengthSamples = 24000,
          itemGain = 0.5,
          fadeInSamples = 240,
          fadeOutSamples = 480,
          take = { volume = 0.8, pan = -0.2, playbackRate = 1, pitch = 0, channelMode = 0, polarityInverted = false },
        },
      },
    },
    { laneId = "lane-2", displayName = "DX Alt", order = 1, clips = {} },
  },
}
local files = {
  [pointer_path] = json.encode(pointer),
  [snapshot_path] = json.encode(snapshot),
  [media_path] = "audio",
}
local fs = {}
function fs.read_file(path) return files[path] end
function fs.hash_file(path) if path == media_path then return "media-hash" end end
function fs.join(...) return table.concat({ ... }, "/"):gsub("/+", "/") end

local values = {
  project_mode = "mix",
  picture_id = "picture-1",
  picture_revision = "7",
  picture_start_samples = "96000",
}
local existing_track = { guid = "track-existing", name = "DX Main Print" }
local unrelated_track = { guid = "track-unrelated", name = "(unnamed track)" }
local events = {}
local adapter = {}
function adapter.get_project_value(key) return values[key] end
function adapter.set_project_value(key, value) values[key] = value end
function adapter.project_sample_rate() return 48000 end
function adapter.all_tracks() return { existing_track, unrelated_track } end
function adapter.track_name(track) return track.name end
function adapter.track_guid(track) return track.guid end
function adapter.new_id() return "instance-1" end
function adapter.begin_undo() table.insert(events, "begin") end
function adapter.end_undo() table.insert(events, "end") end
function adapter.mark_project_dirty() table.insert(events, "dirty") end
function adapter.create_mix_track(name)
  local track = { guid = "track-new", name = name }
  table.insert(events, "create track")
  return track
end
function adapter.create_delivery_item(track, clip, context)
  table.insert(events, "create item")
  return { track = track, clip = clip, context = context }
end

local review, review_error = mix_import.review(adapter, fs, pointer_path)
assert(review, review_error)
assert(review.blocker_count == 0, "valid delivery is importable")
assert(review.picture_warning, "older reviewed Picture is warned")
assert(review.lanes[1].suggestions[1].track_ref == existing_track, "track-name suggestion")
assert(#review.lanes[1].suggestions == 1, "unrelated Tracks are not suggested")
assert(#review.lanes[2].suggestions == 0, "a Lane without a name match has no suggestion")
assert(review.lanes[1].clips[1].media_path == media_path, "relative media path resolved")

local result, apply_error = mix_import.apply(review, adapter, {
  allow_picture_revision_mismatch = true,
  mappings = {
    ["lane-1"] = { kind = "create" },
    ["lane-2"] = { kind = "skip" },
  },
})
assert(result, apply_error)
assert(result.created_tracks == 1, "mapped Lane creates Track")
assert(result.created_items == 1, "mapped Clip creates Item")
assert(events[1] == "begin" and events[#events] == "end", "single undo point")
assert(result.items[1].context.position_seconds == 3, "Picture-relative position applied")
assert(result.items[1].context.source_project_id == "source-1", "Source binding context")
assert(result.items[1].context.instance_id == "instance-1", "local Instance identity")
local subscriptions = json.decode(values.source_subscriptions)
assert(subscriptions[1].deliverySetId == "set-1", "subscription persisted")
assert(subscriptions[1].sourceProjectName == "DX", "subscription carries a readable Source name")
assert(subscriptions[1].lanes[1].trackGuid == "track-new", "Lane binding persisted")
assert(subscriptions[1].lanes[2].skipped, "skipped Lane persisted")

local duplicate, duplicate_error = mix_import.review(adapter, fs, pointer_path)
assert(not duplicate and duplicate_error:find("already subscribed", 1, true), "duplicate subscription blocked")

local removed = assert(mix_import.remove_subscription(adapter, "source-1"))
assert(removed.source_project_id == "source-1", "subscription removal result")
assert(#json.decode(values.source_subscriptions) == 0, "subscription removed without project content mutation")

function adapter.cancel_undo(label) table.insert(events, "cancel:" .. label) end
function adapter.create_delivery_item() return nil, "simulated media open failure" end
local failed, failed_error = mix_import.apply(review, adapter, {
  allow_picture_revision_mismatch = true,
  mappings = {
    ["lane-1"] = { kind = "create" },
    ["lane-2"] = { kind = "skip" },
  },
})
assert(not failed and failed_error == "simulated media open failure", "runtime import failure is reported")
assert(events[#events] == "cancel:Import ReaDelivery Source", "failed import rolls back its undo block")

return 5
