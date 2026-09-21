local constants = require("reaprojectlink.constants")
local json = require("reaprojectlink.json")
local delivery_import = require("reaprojectlink.delivery_import")
local delivery_update = require("reaprojectlink.delivery_update")
local reference_subscription = require("reaprojectlink.reference_subscription")
local adapter = require("reaprojectlink.reaper_adapter")

local source = debug.getinfo(1, "S").source:sub(2)
local tests_dir = assert(source:match("^(.*)[/\\]"))
local wav_path = tests_dir .. "/.rollback-fixture.wav"
local sample_bytes = string.rep("\0", 96)
local wav = string.pack(
  "<c4I4c4c4I4I2I2I4I4I2I2c4I4",
  "RIFF", 36 + #sample_bytes, "WAVE", "fmt ", 16, 1, 1,
  48000, 96000, 2, 16, "data", #sample_bytes
) .. sample_bytes
local fixture = assert(io.open(wav_path, "wb"))
fixture:write(wav)
fixture:close()

local function proxy(overrides)
  return setmetatable(overrides or {}, { __index = adapter })
end

local function reference_context()
  return {
    reference_id = adapter.get_project_value(constants.PROJECT_KEYS.reference_id),
    reference_revision = tonumber(adapter.get_project_value(
      constants.PROJECT_KEYS.reference_revision
    )) or 0,
    reference_start_samples = adapter.get_project_value(
      constants.PROJECT_KEYS.reference_start_samples
    ),
    reference_start_sample_rate = adapter.get_project_value(
      constants.PROJECT_KEYS.reference_start_sample_rate
    ),
  }
end

local function clip(id, revision, position)
  return {
    clipId = id,
    displayName = id,
    mediaRevision = revision,
    media_path = wav_path,
    startOffsetSamples = position or 0,
    sourceOffsetSamples = 0,
    lengthSamples = 4800,
    itemGain = 1,
    fadeInSamples = 0,
    fadeOutSamples = 0,
    take = {
      volume = 1,
      pan = 0,
      playbackRate = 1,
      pitch = 0,
      channelMode = 0,
      polarityInverted = false,
    },
  }
end

adapter.set_project_value(constants.PROJECT_KEYS.reference_id, "rollback-reference")
adapter.set_project_value(constants.PROJECT_KEYS.reference_revision, "7")
adapter.set_project_value(constants.PROJECT_KEYS.reference_start_samples, "0")
adapter.set_project_value(constants.PROJECT_KEYS.reference_start_sample_rate, "48000")
adapter.set_project_value(constants.PROJECT_KEYS.delivery_subscriptions, "[]")

-- Import creates a Track and one Item before the injected second-media failure.
-- The real Undo path must remove both and preserve project extension state.
local import_review = {
  project_token = adapter.project_token(),
  blocker_count = 0,
  reference_warning = false,
  reference_context = reference_context(),
  pointer_path = "C:/not-used/delivery.json",
  pointer = {
    sourceProjectId = "rollback-source",
    deliveryId = "rollback-set",
    latestDeliveryRevision = 1,
  },
  snapshot = {
    sourceProjectName = "Rollback Source",
    sampleRate = 48000,
    reference = { reviewedRevision = 7 },
  },
  lanes = {
    {
      lane_id = "rollback-lane",
      display_name = "Rollback Lane",
      clips = { clip("rollback-clip-1", 1), clip("rollback-clip-2", 1) },
    },
  },
}
local import_calls = 0
local failing_import_adapter = proxy({
  create_delivery_item = function(track, value, context)
    import_calls = import_calls + 1
    if import_calls == 2 then return nil, "injected second import failure" end
    return adapter.create_delivery_item(track, value, context)
  end,
})
local tracks_before_import = reaper.CountTracks(0)
local subscriptions_before_import = adapter.get_project_value(
  constants.PROJECT_KEYS.delivery_subscriptions
)
local imported, import_error = delivery_import.apply(import_review, failing_import_adapter, {
  mappings = { ["rollback-lane"] = { kind = "create" } },
})
assert(not imported and import_error == "injected second import failure", "Import failure injected")
assert(reaper.CountTracks(0) == tracks_before_import, "failed Import rolls back created Track and Item")
assert(
  adapter.get_project_value(constants.PROJECT_KEYS.delivery_subscriptions) ==
    subscriptions_before_import,
  "failed Import preserves subscription state"
)

-- Update adds a Take, moves the Item, and writes Instance revisions before a
-- later new-Clip failure. Real Undo must restore all three mutations.
adapter.begin_undo("Prepare rollback Update fixture")
local update_track = adapter.create_master_track("Rollback Update")
local update_item = assert(adapter.create_delivery_item(
  update_track,
  clip("rollback-update-clip", 1),
  {
    source_sample_rate = 48000,
    position_seconds = 0,
    source_project_id = "rollback-update-source",
    lane_id = "rollback-update-lane",
    delivery_revision = 1,
    reference_revision = 7,
  }
))
local retired_item = assert(adapter.create_delivery_item(
  update_track,
  clip("rollback-retired-clip", 1),
  {
    source_sample_rate = 48000,
    position_seconds = 2,
    source_project_id = "rollback-update-source",
    lane_id = "rollback-update-lane",
    delivery_revision = 1,
    reference_revision = 7,
  }
))
adapter.end_undo("Prepare rollback Update fixture")
local current_state = adapter.delivery_instance_state(update_item)
local retired_state = adapter.delivery_instance_state(retired_item)
local source_state = {}
for key, value in pairs(current_state) do source_state[key] = value end
source_state.position_seconds = 1
local update_subscription = {
  pointerPath = "C:/not-used/delivery.json",
  sourceProjectId = "rollback-update-source",
  sourceProjectName = "Rollback Update Source",
  deliveryId = "rollback-update-set",
  acceptedDeliveryRevision = 1,
  lanes = { { laneId = "rollback-update-lane", trackGuid = adapter.track_guid(update_track) } },
}
local update_review = {
  project_token = adapter.project_token(),
  pending_count = 3,
  blocker_count = 0,
  reference_warning = false,
  reference_context = reference_context(),
  source_project_id = "rollback-update-source",
  target_revision = 2,
  target_snapshot = {
    sampleRate = 48000,
    sourceProjectName = "Rollback Update Source",
    reference = { reviewedRevision = 7 },
  },
  subscription_index = 1,
  subscriptions = { update_subscription },
  instances = {
    {
      item_ref = update_item,
      state = current_state,
    },
    {
      item_ref = retired_item,
      state = retired_state,
    },
  },
  additions = {
    {
      track_guid = adapter.track_guid(update_track),
      lane_id = "rollback-update-lane",
      clip = clip("rollback-addition", 1),
      media_path = wav_path,
    },
  },
  unmapped_lanes = {},
}
local failing_update_adapter = proxy({
  create_delivery_item = function()
    return nil, "injected addition failure"
  end,
})
local updated, update_error = delivery_update.apply(update_review, failing_update_adapter, {})
assert(not updated and update_error == "injected addition failure", "Update failure injected")
local restored_update, restored_retired
for _, instance in ipairs(adapter.delivery_instances("rollback-update-source")) do
  if instance.clip_id == "rollback-update-clip" then restored_update = instance end
  if instance.clip_id == "rollback-retired-clip" then restored_retired = instance end
end
assert(restored_update and restored_retired, "failed synchronization restores deleted managed Items")
assert(restored_retired.clip_id == "rollback-retired-clip",
  "failed synchronization restores managed Item metadata")
adapter.begin_undo("Clean rollback Update fixture")
reaper.DeleteTrack(update_track)
adapter.end_undo("Clean rollback Update fixture")

-- Reference synchronization changes timeline state and creates managed Tracks and
-- Items before the injected missing-video failure. Undo must restore both.
local timeline_before = adapter.timeline_state()
local tracks_before_reference = reaper.CountTracks(0)
local reference_status = {
  project_token = adapter.project_token(),
  available = true,
  alignment_mode = "mirror",
  can_shift_entire_project = false,
  shift_seconds = 0,
  latest_revision = 8,
  snapshot = {
    referenceId = "rollback-reference",
    referenceRevision = 8,
    timeline = {
      sampleRate = 48000,
      projectTimecodeOffsetSamples = 48000,
      referenceStartSamples = 0,
      frameRate = { numerator = 30000, denominator = 1001, dropFrame = true },
    },
    lanes = {
      {
        laneId = "rollback-reference-lane-1",
        displayName = "Rollback Reference A",
        items = {
          {
            itemId = "rollback-reference-item-1",
            displayName = "Valid",
            videoFile = wav_path,
            startSamples = 0,
            sourceOffsetSamples = 0,
            durationSamples = 4800,
            playbackRate = 1,
          },
        },
      },
      {
        laneId = "rollback-reference-lane-2",
        displayName = "Rollback Reference B",
        items = {
          {
            itemId = "rollback-reference-item-2",
            displayName = "Injected Failure",
            videoFile = wav_path,
            startSamples = 4800,
            sourceOffsetSamples = 0,
            durationSamples = 4800,
            playbackRate = 1,
          },
        },
      },
    },
    markers = {},
    regions = {},
  },
}
local failing_reference_adapter = proxy({
  sync_reference = function(snapshot, options)
    local result, sync_error = adapter.sync_reference(snapshot, options)
    if not result then return nil, sync_error end
    return nil, "injected post-synchronization failure"
  end,
})
local synchronized, synchronize_error = reference_subscription.synchronize(
  failing_reference_adapter, reference_status
)
assert(
  not synchronized and synchronize_error == "injected post-synchronization failure",
  "Reference synchronization failure injected: " .. tostring(synchronize_error)
)
assert(reaper.CountTracks(0) == tracks_before_reference, "failed Reference sync rolls back Tracks and Items")
local timeline_after = adapter.timeline_state()
assert(
  timeline_after.project_timecode_offset_samples == timeline_before.project_timecode_offset_samples and
    timeline_after.frame_rate.numerator == timeline_before.frame_rate.numerator and
    timeline_after.frame_rate.denominator == timeline_before.frame_rate.denominator and
    timeline_after.frame_rate.drop_frame == timeline_before.frame_rate.drop_frame,
  "failed Reference sync rolls back timeline state"
)

os.remove(wav_path)
return 3
