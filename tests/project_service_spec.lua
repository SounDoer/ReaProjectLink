local project_service = require("reaprojectlink.project_service")

local function equal(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
  end
end

local function fake_adapter(options)
  options = options or {}
  local project_values = options.project_values or {}
  local selected = options.selected or {}
  local tracks = options.tracks or selected
  local dirty = 0
  local undo_depth = 0

  local adapter = {}
  function adapter.project_path() return options.path or "C:/project/source.rpp" end
  function adapter.new_id() return "generated-id" end
  function adapter.get_project_value(key) return project_values[key] end
  function adapter.set_project_value(key, value) project_values[key] = value end
  function adapter.selected_tracks() return selected end
  function adapter.all_tracks() return tracks end
  function adapter.get_track_lane_id(track) return track.lane_id end
  function adapter.set_track_lane_id(track, value) track.lane_id = value end
  function adapter.get_item_clip_id(item) return item.clip_id end
  function adapter.track_name(track) return track.name end
  function adapter.track_items(track) return track.items or {} end
  function adapter.track_fx_count(track) return track.fx or 0 end
  function adapter.item_display_name(item) return item.name end
  function adapter.active_take_media(item) return item.media end
  function adapter.item_presentation(item) return item.presentation end
  function adapter.project_sample_rate() return options.sample_rate or 48000 end
  function adapter.file_exists(path) return path ~= "missing.wav" end
  function adapter.begin_undo() undo_depth = undo_depth + 1 end
  function adapter.end_undo() undo_depth = undo_depth - 1 end
  function adapter.mark_project_dirty() dirty = dirty + 1 end
  function adapter.dirty_count() return dirty end
  function adapter.undo_depth() return undo_depth end
  return adapter
end

local tests = {}

function tests.initializes_a_saved_source_project()
  local adapter = fake_adapter()
  local result = assert(project_service.initialize_source(adapter))
  equal(result.project_type, "source", "Project Type")
  equal(result.project_id, "generated-id", "Project ID")
  equal(adapter.dirty_count(), 1, "dirty count")
  equal(adapter.undo_depth(), 0, "balanced undo")
end

function tests.initializes_a_master_project_with_identity()
  local adapter = fake_adapter()
  local result = assert(project_service.initialize_master(adapter))
  equal(result.project_type, "master", "Project Type")
  equal(result.project_id, "generated-id", "Project ID")
  equal(adapter.dirty_count(), 1, "dirty count")
end

function tests.reports_persisted_reference_state_without_reading_files()
  local adapter = fake_adapter({
    project_values = {
      project_type = "source",
      reference_id = "reference-1",
      reference_manifest_path = "C:/mix/_ReaProjectLink/Mix/reference.json",
      synchronized_reference_revision = "2",
      reviewed_reference_revision = "2",
      delivery_revision = "4",
    },
  })
  local state = project_service.project_state(adapter)
  equal(state.delivery_revision, 4, "published Delivery revision")
  equal(state.reference_id, "reference-1", "reference id")
  equal(state.reference_manifest_path, "C:/mix/_ReaProjectLink/Mix/reference.json", "manifest path")
  equal(state.synchronized_reference_revision, 2, "synchronized revision")
  equal(state.reviewed_reference_revision, 2, "reviewed revision")
  equal(state.reference_revision, 0, "unpublished reference revision")
end

function tests.lists_registered_delivery_tracks()
  local adapter = fake_adapter({
    project_values = { project_type = "source" },
    tracks = {
      { name = "DX Print", lane_id = "lane-1", items = { {}, {} } },
      { name = "Working", lane_id = "", items = { {} } },
    },
  })
  local lanes = project_service.delivery_tracks(adapter)
  equal(#lanes, 1, "only registered Tracks are listed")
  equal(lanes[1].display_name, "DX Print", "Track name")
  equal(lanes[1].item_count, 2, "Item count")
end

function tests.rejects_initializing_an_unsaved_project()
  local adapter = fake_adapter({ path = "" })
  local result, err = project_service.initialize_source(adapter)
  equal(result, nil, "result")
  equal(type(err), "string", "error")
  equal(adapter.dirty_count(), 0, "dirty count")
end

function tests.registers_only_unregistered_selected_tracks()
  local registered = { lane_id = "existing" }
  local unregistered = { lane_id = "" }
  local adapter = fake_adapter({
    project_values = { project_type = "source" },
    selected = { registered, unregistered },
  })
  local result = assert(project_service.register_selected_tracks(adapter))
  equal(result.added, 1, "added")
  equal(unregistered.lane_id, "generated-id", "new lane id")
  equal(registered.lane_id, "existing", "existing lane id")
  equal(adapter.undo_depth(), 0, "balanced undo")
end

function tests.scans_registered_tracks_and_reports_blockers()
  local adapter = fake_adapter({
    project_values = { project_type = "source" },
    tracks = {
      {
        name = "DX Print",
        lane_id = "lane-1",
        fx = 1,
        items = {
          { name = "Line A", clip_id = "", media = { path = "ok.wav", take_fx_count = 0 } },
          { name = "Line B", clip_id = "clip-2", media = { path = "missing.wav", take_fx_count = 1 } },
        },
      },
      { name = "Working", lane_id = "", items = { { name = "Ignored" } } },
    },
  })

  local result = assert(project_service.scan(adapter))
  equal(#result.lanes, 1, "lane count")
  equal(result.clip_count, 2, "clip count")
  equal(result.untagged_count, 1, "untagged count")
  equal(result.blocker_count, 3, "blocker count")
end

function tests.scans_manifest_ready_clip_state()
  local presentation = {
    start_offset_samples = 96000,
    source_offset_samples = 2400,
    length_samples = 48000,
    item_gain = 0.5,
    fade_in_samples = 240,
    fade_out_samples = 480,
    take = {
      volume = 0.8,
      pan = -0.25,
      playback_rate = 1.1,
      pitch = 2,
      channel_mode = 1,
      polarity_inverted = true,
    },
  }
  local adapter = fake_adapter({
    sample_rate = 48000,
    project_values = { project_type = "source" },
    tracks = {
      {
        name = "DX Print",
        lane_id = "lane-1",
        items = {
          {
            name = "Line A",
            clip_id = "clip-1",
            presentation = presentation,
            media = {
              path = "ok.wav",
              sample_rate = 96000,
              channel_count = 2,
              take_fx_count = 0,
            },
          },
        },
      },
    },
  })

  local result = assert(project_service.scan(adapter))
  local lane = result.lanes[1]
  local clip = lane.clips[1]
  equal(result.sample_rate, 48000, "project sample rate")
  equal(lane.order, 0, "lane order")
  equal(clip.item_ref, adapter.all_tracks()[1].items[1], "item reference")
  equal(clip.media_sample_rate, 96000, "media sample rate")
  equal(clip.channel_count, 2, "channel count")
  equal(clip.start_offset_samples, 96000, "timeline position")
  equal(clip.source_offset_samples, 2400, "source offset")
  equal(clip.length_samples, 48000, "item length")
  equal(clip.item_gain, 0.5, "item gain")
  equal(clip.fade_out_samples, 480, "fade out")
  equal(clip.take.playback_rate, 1.1, "take playback rate")
  equal(clip.take.polarity_inverted, true, "take polarity")
end

function tests.rejects_non_wav_delivery_media()
  local adapter = fake_adapter({
    project_values = { project_type = "source" },
    tracks = {
      {
        name = "DX Print",
        lane_id = "lane-1",
        items = {
          {
            name = "Compressed bounce",
            clip_id = "clip-1",
            presentation = {},
            media = { path = "bounce.mp3", take_fx_count = 0 },
          },
        },
      },
    },
  })
  local result = assert(project_service.scan(adapter))
  equal(result.blocker_count, 1, "non-WAV blocker")
  equal(result.lanes[1].clips[1].blockers[1], "Only file-backed WAV media can be published", "non-WAV message")
end

local passed = 0
for name, test in pairs(tests) do
  local ok, err = pcall(test)
  if not ok then
    error(name .. ": " .. tostring(err))
  end
  passed = passed + 1
end

return passed
