local constants = require("readelivery.constants")
local json = require("readelivery.json")
local manifest_validation = require("readelivery.manifest_validation")
local picture_manifest = require("readelivery.picture_manifest")
local project_guard = require("readelivery.project_guard")
local default_picture_writer = require("readelivery.picture_writer")

local M = {}

local VIDEO_EXTENSIONS = {
  mov = true, mp4 = true, m4v = true, mxf = true,
  avi = true, mkv = true, webm = true,
}

local function is_video(path)
  local extension = path and path:lower():match("%.([^.\\/]+)$")
  return extension and VIDEO_EXTENSIONS[extension] or false
end

local function project_parts(path)
  local directory, filename = path:match("^(.*)[/\\]([^/\\]+)$")
  if not directory then return nil, nil end
  return directory, filename:gsub("%.[Rr][Pp][Pp]$", "")
end

local function read_json(fs, path, label)
  local bytes, read_error = fs.read_file(path)
  if not bytes then return nil, read_error or ("Could not read " .. label .. ".") end
  local ok, value = pcall(json.decode, bytes)
  if not ok then return nil, label .. " is invalid JSON: " .. tostring(value) end
  return value
end

local function load_published(fs, package_root)
  local path = fs.join(package_root, "picture.json")
  if not fs.exists(path) then return nil, nil end
  local pointer, pointer_error = read_json(fs, path, "picture.json")
  if not pointer then return nil, pointer_error end
  local valid, validation_error = manifest_validation.picture_pointer(pointer)
  if not valid then return nil, validation_error end
  local raw, snapshot_error = read_json(
    fs, fs.join(package_root, pointer.manifest), "Master Reference Manifest"
  )
  if not raw then return nil, snapshot_error end
  valid, validation_error = manifest_validation.picture_snapshot(raw, {
    picture_id = pointer.pictureId,
    revision = pointer.latestPictureRevision,
  })
  if not valid then return nil, validation_error end
  return { pointer = pointer, snapshot = raw }
end

local function registry(adapter)
  local stored = adapter.get_project_value(constants.PROJECT_KEYS.picture_timeline_entries)
  if not stored or stored == "" then return {} end
  local ok, value = pcall(json.decode, stored)
  if not ok or type(value) ~= "table" then
    return nil, "Stored Master Reference Marker/Region registrations are invalid."
  end
  return value
end

local function save_registry(adapter, value)
  adapter.set_project_value(
    constants.PROJECT_KEYS.picture_timeline_entries,
    json.encode(value)
  )
  adapter.mark_project_dirty()
end

local function registered_entry_index(adapter)
  local by_guid = {}
  local entries, registry_error = registry(adapter)
  if not entries then return nil, registry_error end
  for _, entry in ipairs(entries) do by_guid[entry.guid] = entry end
  return by_guid
end

local function copy_without_metadata(snapshot)
  local copy = {}
  for key, value in pairs(snapshot or {}) do
    if key ~= "publishedAt" and key ~= "publishedBy" and
        key ~= "pictureRevision" then copy[key] = value end
  end
  return copy
end

local function equivalent(left, right)
  return json.encode(copy_without_metadata(left)) ==
    json.encode(copy_without_metadata(right))
end

local function add_blocker(result, message)
  result.blocker_count = result.blocker_count + 1
  table.insert(result.blockers, message)
end

function M.create(dependencies)
  dependencies = dependencies or {}
  local writer = dependencies.picture_writer or default_picture_writer
  local service = {}

  function service.picture_tracks(adapter)
    local result = {}
    for _, track in ipairs(adapter.all_tracks()) do
      local lane_id = adapter.get_track_picture_lane_id(track)
      if lane_id and lane_id ~= "" then
        table.insert(result, {
          lane_id = lane_id,
          display_name = adapter.track_name(track),
          item_count = #adapter.track_items(track),
        })
      end
    end
    return result
  end

  function service.register_selected_tracks(adapter)
    if adapter.get_project_value(constants.PROJECT_KEYS.project_mode) ~=
        constants.PROJECT_MODES.mix then
      return nil, "Only a Mix project can register Picture Tracks."
    end
    local selected = adapter.selected_tracks()
    if #selected == 0 then return nil, "Select at least one Picture Track." end
    local added = 0
    adapter.begin_undo("Register ReaDelivery Picture Tracks")
    for _, track in ipairs(selected) do
      local id = adapter.get_track_picture_lane_id(track)
      if not id or id == "" then
        adapter.set_track_picture_lane_id(track, adapter.new_id())
        added = added + 1
      end
    end
    adapter.mark_project_dirty()
    adapter.end_undo("Register ReaDelivery Picture Tracks")
    return { selected = #selected, added = added }
  end

  function service.unregister_selected_tracks(adapter)
    local selected = adapter.selected_tracks()
    if #selected == 0 then return nil, "Select at least one Picture Track." end
    local removed = 0
    adapter.begin_undo("Remove ReaDelivery Picture Tracks")
    for _, track in ipairs(selected) do
      local id = adapter.get_track_picture_lane_id(track)
      if id and id ~= "" then
        adapter.set_track_picture_lane_id(track, "")
        removed = removed + 1
      end
    end
    adapter.mark_project_dirty()
    adapter.end_undo("Remove ReaDelivery Picture Tracks")
    return { selected = #selected, removed = removed }
  end

  function service.reset_selected_picture_tracks(adapter)
    local selected = adapter.selected_tracks()
    if #selected == 0 then return nil, "Select at least one Picture Track." end
    local reset = 0
    adapter.begin_undo("Reset ReaDelivery Picture Track identities")
    for _, track in ipairs(selected) do
      local lane_id = adapter.get_track_picture_lane_id(track)
      if lane_id and lane_id ~= "" then
        adapter.set_track_picture_lane_id(track, adapter.new_id())
        adapter.set_track_picture_set_id(track, "")
        reset = reset + 1
      end
    end
    adapter.mark_project_dirty()
    adapter.end_undo("Reset ReaDelivery Picture Track identities")
    return { reset = reset }
  end

  function service.reset_selected_picture_items(adapter)
    local selected = adapter.selected_items()
    if #selected == 0 then return nil, "Select at least one Picture Item." end
    local reset = 0
    adapter.begin_undo("Reset ReaDelivery Picture Item identities")
    for _, item in ipairs(selected) do
      local id = adapter.get_item_picture_item_id(item)
      if id and id ~= "" then
        adapter.set_item_picture_item_id(item, "")
        adapter.set_item_picture_id(item, "")
        reset = reset + 1
      end
    end
    adapter.mark_project_dirty()
    adapter.end_undo("Reset ReaDelivery Picture Item identities")
    return { selected = #selected, reset = reset }
  end

  function service.timeline_entries(adapter)
    local registered, registry_error = registered_entry_index(adapter)
    if not registered then return nil, registry_error end
    local result = adapter.timeline_entries()
    for _, entry in ipairs(result) do
      local stored = registered[entry.guid]
      entry.registered = stored ~= nil
      entry.entry_id = stored and stored.entryId
      entry.semantic_role = stored and stored.semanticRole
    end
    return result
  end

  function service.register_selected_timeline_entries(adapter)
    local current, current_error = service.timeline_entries(adapter)
    if not current then return nil, current_error end
    local stored, registry_error = registry(adapter)
    if not stored then return nil, registry_error end
    local added = 0
    for _, entry in ipairs(current) do
      if entry.selected and not entry.registered then
        table.insert(stored, {
          guid = entry.guid,
          entryId = adapter.new_id(),
          kind = entry.kind,
        })
        added = added + 1
      end
    end
    if added == 0 then return nil, "Select at least one unregistered Marker or Region." end
    save_registry(adapter, stored)
    return { added = added }
  end

  function service.unregister_selected_timeline_entries(adapter)
    local selected = {}
    for _, entry in ipairs(adapter.timeline_entries()) do
      if entry.selected then selected[entry.guid] = true end
    end
    local stored, registry_error = registry(adapter)
    if not stored then return nil, registry_error end
    local kept, removed = {}, 0
    for _, entry in ipairs(stored) do
      if selected[entry.guid] then removed = removed + 1
      else table.insert(kept, entry) end
    end
    if removed == 0 then return nil, "Select at least one registered Marker or Region." end
    save_registry(adapter, kept)
    return { removed = removed }
  end

  function service.set_selected_ffop(adapter)
    local selected
    local current, current_error = service.timeline_entries(adapter)
    if not current then return nil, current_error end
    for _, entry in ipairs(current) do
      if entry.selected and entry.kind == "marker" and entry.registered then
        if selected then return nil, "Select exactly one registered Marker as FFOP." end
        selected = entry
      end
    end
    if not selected then return nil, "Select exactly one registered Marker as FFOP." end
    local stored, registry_error = registry(adapter)
    if not stored then return nil, registry_error end
    for _, entry in ipairs(stored) do
      entry.semanticRole = entry.guid == selected.guid and "FFOP" or nil
    end
    save_registry(adapter, stored)
    return { entry_id = selected.entry_id }
  end

  function service.review(adapter, fs, options)
    options = options or {}
    if adapter.get_project_value(constants.PROJECT_KEYS.project_mode) ~=
        constants.PROJECT_MODES.mix then
      return nil, "Only a Mix project can Publish Master Reference."
    end
    local directory, project_name = project_parts(adapter.project_path())
    if not directory then return nil, "Save the Mix project before Publish Review." end
    local package_root = fs.join(directory, "_Delivery", project_name)
    local published, published_error = load_published(fs, package_root)
    if published_error then return nil, published_error end
    local project_id = adapter.get_project_value(constants.PROJECT_KEYS.picture_id)
    if published and project_id and project_id ~= "" and
        published.pointer.pictureId ~= project_id then
      return nil, "Published package belongs to a different Master Reference ID."
    end

    local timeline = adapter.timeline_state()
    local result = {
      package_root = package_root,
      mix_project_name = project_name,
      picture_id = (project_id and project_id ~= "" and project_id) or
        (published and published.pointer.pictureId),
      picture_revision = (published and published.pointer.latestPictureRevision or 0) + 1,
      base_revision = published and published.pointer.latestPictureRevision or 0,
      previous_snapshot = published and published.snapshot,
      sample_rate = timeline.sample_rate,
      project_timecode_offset_samples = timeline.project_timecode_offset_samples,
      frame_rate = timeline.frame_rate,
      alignment_mode = "mirror",
      reference_start_samples = 0,
      lanes = {}, markers = {}, regions = {}, assignments = {},
      picture_tracks = {}, picture_items = {},
      blocker_count = 0, blockers = {}, item_count = 0,
    }

    local lane_ids, item_ids = {}, {}
    for _, track in ipairs(adapter.all_tracks()) do
      local lane_id = adapter.get_track_picture_lane_id(track)
      if lane_id and lane_id ~= "" then
        table.insert(result.picture_tracks, track)
        if lane_ids[lane_id] then
          add_blocker(result, "Duplicate Picture Track identity: " .. adapter.track_name(track))
        else lane_ids[lane_id] = true end
        local lane = {
          laneId = lane_id,
          displayName = adapter.track_name(track),
          order = #result.lanes,
          items = {},
        }
        for _, item in ipairs(adapter.track_items(track)) do
          local state = adapter.picture_item_state(item)
          if not state or not is_video(state.video_file) then
            add_blocker(result, "Picture Track contains a non-video Item: " ..
              adapter.track_name(track))
          elseif not fs.exists(state.video_file) then
            add_blocker(result, "Picture video is missing: " .. tostring(state.video_file))
          else
            table.insert(result.picture_items, item)
            local item_id = adapter.get_item_picture_item_id(item)
            if item_id and item_id ~= "" then
              if item_ids[item_id] then
                add_blocker(result, "Duplicate Picture Item identity: " ..
                  adapter.item_display_name(item))
              else item_ids[item_id] = true end
            end
            local hash = fs.hash_file(state.video_file)
            if not hash then
              add_blocker(result, "Picture video could not be hashed: " .. state.video_file)
            end
            table.insert(lane.items, {
              itemId = item_id or "",
              displayName = adapter.item_display_name(item),
              videoFile = state.video_file,
              videoHash = hash and ("sha256:" .. hash) or "",
              startSamples = state.picture_start_samples,
              sourceOffsetSamples = state.source_offset_samples,
              durationSamples = state.duration_samples,
              playbackRate = state.playback_rate,
            })
            if not item_id or item_id == "" then
              table.insert(result.assignments, { item_ref = item, manifest_item = lane.items[#lane.items] })
            end
            result.item_count = result.item_count + 1
          end
        end
        table.insert(result.lanes, lane)
      end
    end

    local registered, registry_error = registered_entry_index(adapter)
    if not registered then return nil, registry_error end
    local seen, entry_ids = {}, {}
    local ffop_count = 0
    for _, entry in ipairs(adapter.timeline_entries()) do
      local identity = registered[entry.guid]
      if identity then
        seen[entry.guid] = true
        if entry_ids[identity.entryId] then
          add_blocker(result, "Duplicate registered Marker/Region identity: " .. entry.name)
        else entry_ids[identity.entryId] = true end
        local target = entry.kind == "region" and result.regions or result.markers
        local manifest_entry = {
          entryId = identity.entryId,
          name = entry.name,
          color = entry.color,
          startSamples = entry.start_samples,
          semanticRole = identity.semanticRole,
        }
        if entry.kind == "region" then manifest_entry.endSamples = entry.end_samples end
        table.insert(target, manifest_entry)
        if identity.semanticRole == "FFOP" then
          ffop_count = ffop_count + 1
          if entry.kind ~= "marker" then
            add_blocker(result, "FFOP must be assigned to a Marker, not a Region.")
          end
          result.reference_start_samples = entry.start_samples
          result.reference_role = "FFOP"
        end
      end
    end
    if ffop_count > 1 then
      add_blocker(result, "Only one registered Marker may have the FFOP role.")
    end
    local stored_registry = assert(registry(adapter))
    local kept_registry = {}
    for _, entry in ipairs(stored_registry) do
      if seen[entry.guid] then table.insert(kept_registry, entry) end
    end
    result.registry_after_publish = kept_registry

    if #result.lanes == 0 and #result.markers == 0 and #result.regions == 0 then
      result.empty_blocker = "Register Picture Tracks, Markers, or Regions before Publish."
      add_blocker(result, result.empty_blocker)
    end

    local candidate = picture_manifest.build({
      picture_id = result.picture_id or "pending",
      picture_revision = result.picture_revision,
      mix_project_name = project_name,
      published_at = "comparison",
      published_by = "comparison",
      alignment_mode = result.alignment_mode,
      sample_rate = result.sample_rate,
      project_timecode_offset_samples = result.project_timecode_offset_samples,
      frame_rate = result.frame_rate,
      reference_start_samples = result.reference_start_samples,
      reference_role = result.reference_role,
      lanes = result.lanes,
      markers = result.markers,
      regions = result.regions,
    })
    result.unchanged = published ~= nil and #result.assignments == 0 and
      equivalent(published.snapshot, candidate)
    if result.unchanged and not options.publish_anyway then
      result.unchanged_blocker = string.format(
        "This Master Reference is identical to published revision r%d.", result.base_revision
      )
    end
    return project_guard.bind(result, adapter, true)
  end

  function service.publish(review, adapter, fs, metadata)
    local current, context_error = project_guard.check(
      review, adapter, "Master Reference Publish Review"
    )
    if not current then return nil, context_error end
    if review.blocker_count > 0 then return nil, "Publish Review has blockers." end
    if review.unchanged_blocker then return nil, review.unchanged_blocker end
    metadata = metadata or {}
    local picture_id = review.picture_id
    if not picture_id or picture_id == "" then picture_id = adapter.new_id() end

    adapter.begin_undo("Assign ReaDelivery Master Reference identities")
    adapter.set_project_value(constants.PROJECT_KEYS.picture_id, picture_id)
    adapter.set_project_value(constants.PROJECT_KEYS.picture_alignment_mode, "mirror")
    adapter.set_project_value(constants.PROJECT_KEYS.picture_start_samples,
      tostring(review.reference_start_samples))
    adapter.set_project_value(constants.PROJECT_KEYS.picture_start_sample_rate,
      tostring(review.sample_rate))
    for _, track in ipairs(review.picture_tracks) do
      adapter.set_track_picture_set_id(track, picture_id)
    end
    for _, item in ipairs(review.picture_items) do
      adapter.set_item_picture_id(item, picture_id)
    end
    for _, assignment in ipairs(review.assignments) do
      local id = adapter.new_id()
      adapter.set_item_picture_item_id(assignment.item_ref, id)
      assignment.manifest_item.itemId = id
    end
    save_registry(adapter, review.registry_after_publish)
    adapter.mark_project_dirty()
    adapter.end_undo("Assign ReaDelivery Master Reference identities")
    local saved, save_error = adapter.save_project()
    if not saved then return nil, save_error or "Could not save the Mix project." end

    local snapshot, pointer = picture_manifest.build({
      picture_id = picture_id,
      picture_revision = review.picture_revision,
      mix_project_name = review.mix_project_name,
      published_at = metadata.published_at,
      published_by = metadata.published_by,
      alignment_mode = "mirror",
      sample_rate = review.sample_rate,
      project_timecode_offset_samples = review.project_timecode_offset_samples,
      frame_rate = review.frame_rate,
      reference_start_samples = review.reference_start_samples,
      reference_role = review.reference_role,
      lanes = review.lanes,
      markers = review.markers,
      regions = review.regions,
    })
    local result, publish_error = writer.publish({
      package_root = review.package_root,
      expected_revision = review.base_revision,
      transaction_id = adapter.new_id(),
      snapshot = snapshot,
      pointer = pointer,
      lock_metadata = metadata.lock_metadata,
    }, fs)
    if not result then return nil, publish_error end
    adapter.set_project_value(constants.PROJECT_KEYS.picture_revision,
      tostring(result.picture_revision))
    adapter.mark_project_dirty()
    local revision_saved, revision_save_error = adapter.save_project()
    if not revision_saved then result.project_save_error = revision_save_error end
    return result
  end

  return service
end

return M
