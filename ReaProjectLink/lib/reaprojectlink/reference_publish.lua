local constants = require("reaprojectlink.constants")
local json = require("reaprojectlink.json")
local manifest_validation = require("reaprojectlink.manifest_validation")
local reference_manifest = require("reaprojectlink.reference_manifest")
local project_guard = require("reaprojectlink.project_guard")
local default_reference_writer = require("reaprojectlink.reference_writer")
local manifest_file = require("reaprojectlink.manifest_file")
local paths = require("reaprojectlink.paths")

local M = {}

local VIDEO_EXTENSIONS = {
  mov = true, mp4 = true, m4v = true, mxf = true,
  avi = true, mkv = true, webm = true,
}

local function is_video(path)
  local extension = path and path:lower():match("%.([^.\\/]+)$")
  return extension and VIDEO_EXTENSIONS[extension] or false
end

local function load_published(fs, package_root)
  local path = fs.join(package_root, "reference.json")
  if not fs.exists(path) then return nil, nil end
  local pointer, pointer_error = manifest_file.read(fs, path, "reference.json")
  if not pointer then return nil, pointer_error end
  local valid, validation_error = manifest_validation.reference_pointer(pointer)
  if not valid then return nil, validation_error end
  local raw, snapshot_error = manifest_file.read(
    fs, fs.join(package_root, pointer.manifest), "Reference Manifest"
  )
  if not raw then return nil, snapshot_error end
  valid, validation_error = manifest_validation.reference_snapshot(raw, {
    master_project_id = pointer.masterProjectId,
    reference_id = pointer.referenceId,
    revision = pointer.latestReferenceRevision,
  })
  if not valid then return nil, validation_error end
  return { pointer = pointer, snapshot = raw }
end

local function registry(adapter)
  local stored = adapter.get_project_value(constants.PROJECT_KEYS.reference_timeline_entries)
  if not stored or stored == "" then return {} end
  local ok, value = pcall(json.decode, stored)
  if not ok or type(value) ~= "table" then
    return nil, "Stored Reference Marker/Region registrations are invalid."
  end
  return value
end

local function save_registry(adapter, value)
  adapter.set_project_value(
    constants.PROJECT_KEYS.reference_timeline_entries,
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
        key ~= "referenceRevision" then copy[key] = value end
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
  local writer = dependencies.reference_writer or default_reference_writer
  local service = {}

  function service.reference_tracks(adapter)
    local result = {}
    for _, track in ipairs(adapter.all_tracks()) do
      local lane_id = adapter.get_track_reference_lane_id(track)
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
    if adapter.get_project_value(constants.PROJECT_KEYS.project_type) ~=
        constants.PROJECT_TYPES.master then
      return nil, "Only a Master Project can register Reference Tracks."
    end
    local selected = adapter.selected_tracks()
    if #selected == 0 then return nil, "Select at least one Reference Track." end
    local added = 0
    adapter.begin_undo("Register ReaProjectLink Reference Tracks")
    for _, track in ipairs(selected) do
      local id = adapter.get_track_reference_lane_id(track)
      if not id or id == "" then
        adapter.set_track_reference_lane_id(track, adapter.new_id())
        added = added + 1
      end
    end
    adapter.mark_project_dirty()
    adapter.end_undo("Register ReaProjectLink Reference Tracks")
    return { selected = #selected, added = added }
  end

  function service.unregister_selected_tracks(adapter)
    local selected = adapter.selected_tracks()
    if #selected == 0 then return nil, "Select at least one Reference Track." end
    local removed = 0
    adapter.begin_undo("Remove ReaProjectLink Reference Tracks")
    for _, track in ipairs(selected) do
      local id = adapter.get_track_reference_lane_id(track)
      if id and id ~= "" then
        adapter.set_track_reference_lane_id(track, "")
        removed = removed + 1
      end
    end
    adapter.mark_project_dirty()
    adapter.end_undo("Remove ReaProjectLink Reference Tracks")
    return { selected = #selected, removed = removed }
  end

  function service.reset_selected_reference_tracks(adapter)
    local selected = adapter.selected_tracks()
    if #selected == 0 then return nil, "Select at least one Reference Track." end
    local reset = 0
    adapter.begin_undo("Reset ReaProjectLink Reference Track identities")
    for _, track in ipairs(selected) do
      local lane_id = adapter.get_track_reference_lane_id(track)
      if lane_id and lane_id ~= "" then
        adapter.set_track_reference_lane_id(track, adapter.new_id())
        adapter.set_track_reference_id(track, "")
        reset = reset + 1
      end
    end
    adapter.mark_project_dirty()
    adapter.end_undo("Reset ReaProjectLink Reference Track identities")
    return { reset = reset }
  end

  function service.reset_selected_reference_items(adapter)
    local selected = adapter.selected_items()
    if #selected == 0 then return nil, "Select at least one Reference Item." end
    local reset = 0
    adapter.begin_undo("Reset ReaProjectLink Reference Item identities")
    for _, item in ipairs(selected) do
      local id = adapter.get_item_reference_item_id(item)
      if id and id ~= "" then
        adapter.set_item_reference_item_id(item, "")
        adapter.set_item_reference_id(item, "")
        reset = reset + 1
      end
    end
    adapter.mark_project_dirty()
    adapter.end_undo("Reset ReaProjectLink Reference Item identities")
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
      entry.reference_start = stored and stored.referenceStart or false
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

  function service.set_selected_reference_start(adapter)
    local selected
    local current, current_error = service.timeline_entries(adapter)
    if not current then return nil, current_error end
    for _, entry in ipairs(current) do
      if entry.selected and entry.kind == "marker" and entry.registered then
        if selected then return nil, "Select exactly one registered Marker as Reference Start." end
        selected = entry
      end
    end
    if not selected then return nil, "Select exactly one registered Marker as Reference Start." end
    local stored, registry_error = registry(adapter)
    if not stored then return nil, registry_error end
    for _, entry in ipairs(stored) do
      entry.referenceStart = entry.guid == selected.guid or nil
    end
    save_registry(adapter, stored)
    return { entry_id = selected.entry_id }
  end

  function service.review(adapter, fs, options)
    options = options or {}
    if adapter.get_project_value(constants.PROJECT_KEYS.project_type) ~=
        constants.PROJECT_TYPES.master then
      return nil, "Only a Master Project can publish a Reference."
    end
    local directory, project_name = paths.project_parts(adapter.project_path())
    if not directory then return nil, "Save the Master Project before Reference Publish Review." end
    local path = adapter.project_path()
    local derived_package_root = fs.join(directory, "_ReaProjectLink", project_name)
    local stored_master_project_id = adapter.get_project_value(constants.PROJECT_KEYS.project_id)
    local stored_identity_path = adapter.get_project_value(
      constants.PROJECT_KEYS.project_identity_path
    )
    local stored_package_root = adapter.get_project_value(constants.PROJECT_KEYS.package_root)
    local path_changed = stored_master_project_id and stored_master_project_id ~= "" and
      stored_identity_path and stored_identity_path ~= "" and
      not paths.same(stored_identity_path, path)
    local starts_new = path_changed and options.save_as_decision == "new"
    local package_root = path_changed and not starts_new and
      stored_package_root and stored_package_root ~= "" and stored_package_root or
      derived_package_root
    local published, published_error = load_published(fs, package_root)
    if published_error then return nil, published_error end
    if starts_new and published then
      return nil, "The new Master Project package destination already contains a published Reference."
    end
    local master_project_id = not starts_new and stored_master_project_id or nil
    local stored_reference_id = adapter.get_project_value(constants.PROJECT_KEYS.reference_id)
    local reference_id = not starts_new and stored_reference_id or nil
    if published and master_project_id and master_project_id ~= "" and
        published.pointer.masterProjectId ~= master_project_id then
      return nil, "Published package belongs to a different Master Project ID."
    end
    if published and reference_id and reference_id ~= "" and
        published.pointer.referenceId ~= reference_id then
      return nil, "Published package belongs to a different Reference ID."
    end

    local timeline = adapter.timeline_state()
    local result = {
      package_root = package_root,
      master_project_id = master_project_id,
      master_project_name = project_name,
      reference_id = (reference_id and reference_id ~= "" and reference_id) or
        (published and published.pointer.referenceId),
      reference_revision = (published and published.pointer.latestReferenceRevision or 0) + 1,
      base_revision = published and published.pointer.latestReferenceRevision or 0,
      previous_snapshot = published and published.snapshot,
      project_file = path,
      path_changed = path_changed,
      save_as_decision = options.save_as_decision,
      sample_rate = timeline.sample_rate,
      project_timecode_offset_samples = timeline.project_timecode_offset_samples,
      frame_rate = timeline.frame_rate,
      alignment_mode = "mirror",
      reference_start_samples = 0,
      lanes = {}, markers = {}, regions = {}, assignments = {},
      track_assignments = {},
      reference_tracks = {}, reference_items = {},
      blocker_count = 0, blockers = {}, item_count = 0,
    }
    if path_changed and not options.save_as_decision then
      result.save_as_blocker =
        "This Master Project path changed. Choose Continue Existing Project or Start New Project."
      add_blocker(result, result.save_as_blocker)
    end

    local lane_ids, item_ids = {}, {}
    for _, track in ipairs(adapter.all_tracks()) do
      local lane_id = adapter.get_track_reference_lane_id(track)
      if lane_id and lane_id ~= "" then
        if starts_new then
          lane_id = adapter.new_id()
          table.insert(result.track_assignments, { track_ref = track, lane_id = lane_id })
        end
        table.insert(result.reference_tracks, track)
        if lane_ids[lane_id] then
          add_blocker(result, "Duplicate Reference Track identity: " .. adapter.track_name(track))
        else lane_ids[lane_id] = true end
        local lane = {
          laneId = lane_id,
          displayName = adapter.track_name(track),
          order = #result.lanes,
          items = {},
        }
        for _, item in ipairs(adapter.track_items(track)) do
          local state = adapter.reference_item_state(item)
          if not state or not is_video(state.video_file) then
            add_blocker(result, "Reference Track contains a non-video Item: " ..
              adapter.track_name(track))
          elseif not fs.exists(state.video_file) then
            add_blocker(result, "Reference video is missing: " .. tostring(state.video_file))
          else
            table.insert(result.reference_items, item)
            local item_id = adapter.get_item_reference_item_id(item)
            if starts_new then item_id = "" end
            if item_id and item_id ~= "" then
              if item_ids[item_id] then
                add_blocker(result, "Duplicate Reference Item identity: " ..
                  adapter.item_display_name(item))
              else item_ids[item_id] = true end
            end
            local hash = fs.hash_file(state.video_file)
            if not hash then
              add_blocker(result, "Reference video could not be hashed: " .. state.video_file)
            end
            table.insert(lane.items, {
              itemId = item_id or "",
              displayName = adapter.item_display_name(item),
              videoFile = state.video_file,
              videoHash = hash and ("sha256:" .. hash) or "",
              startSamples = state.reference_start_samples,
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
    local seen, entry_ids, effective_registry = {}, {}, {}
    local reference_start_count = 0
    for _, entry in ipairs(adapter.timeline_entries()) do
      local identity = registered[entry.guid]
      if identity then
        if starts_new then
          identity = {
            guid = identity.guid,
            entryId = adapter.new_id(),
            kind = identity.kind,
            referenceStart = identity.referenceStart,
          }
        end
        effective_registry[entry.guid] = identity
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
        }
        if entry.kind == "region" then manifest_entry.endSamples = entry.end_samples end
        table.insert(target, manifest_entry)
        if identity.referenceStart then
          reference_start_count = reference_start_count + 1
          if entry.kind ~= "marker" then
            add_blocker(result, "Reference Start must be assigned to a Marker, not a Region.")
          end
          result.reference_start_samples = entry.start_samples
          result.reference_start_marker_id = identity.entryId
        end
      end
    end
    if reference_start_count > 1 then
      add_blocker(result, "Only one registered Marker may be the Reference Start.")
    end
    local kept_registry = {}
    for guid in pairs(seen) do
      table.insert(kept_registry, effective_registry[guid])
    end
    table.sort(kept_registry, function(left, right) return left.entryId < right.entryId end)
    result.registry_after_publish = kept_registry

    if #result.lanes == 0 and #result.markers == 0 and #result.regions == 0 then
      result.empty_blocker = "Register Reference Tracks, Markers, or Regions before Publish."
      add_blocker(result, result.empty_blocker)
    end

    local candidate = reference_manifest.build({
      reference_id = result.reference_id or "pending",
      reference_revision = result.reference_revision,
      master_project_id = result.master_project_id or "pending",
      master_project_name = project_name,
      published_at = "comparison",
      published_by = "comparison",
      alignment_mode = result.alignment_mode,
      sample_rate = result.sample_rate,
      project_timecode_offset_samples = result.project_timecode_offset_samples,
      frame_rate = result.frame_rate,
      reference_start_samples = result.reference_start_samples,
      reference_start_marker_id = result.reference_start_marker_id,
      lanes = result.lanes,
      markers = result.markers,
      regions = result.regions,
    })
    result.unchanged = published ~= nil and #result.assignments == 0 and
      equivalent(published.snapshot, candidate)
    if result.unchanged and not options.publish_anyway then
      result.unchanged_blocker = string.format(
        "This Reference is identical to Reference r%d.", result.base_revision
      )
    end
    return project_guard.bind(result, adapter, true)
  end

  function service.publish(review, adapter, fs, metadata)
    local current, context_error = project_guard.check(
      review, adapter, "Reference Publish Review"
    )
    if not current then return nil, context_error end
    if review.blocker_count > 0 then return nil, "Publish Review has blockers." end
    if review.unchanged_blocker then return nil, review.unchanged_blocker end
    metadata = metadata or {}
    local reference_id = review.reference_id
    if not reference_id or reference_id == "" then reference_id = adapter.new_id() end
    local master_project_id = review.master_project_id
    if not master_project_id or master_project_id == "" then
      master_project_id = adapter.new_id()
    end

    adapter.begin_undo("Assign ReaProjectLink Reference identities")
    adapter.set_project_value(constants.PROJECT_KEYS.project_id, master_project_id)
    adapter.set_project_value(constants.PROJECT_KEYS.reference_id, reference_id)
    adapter.set_project_value(constants.PROJECT_KEYS.project_identity_path, review.project_file)
    adapter.set_project_value(constants.PROJECT_KEYS.package_root, review.package_root)
    adapter.set_project_value(constants.PROJECT_KEYS.reference_alignment_mode, "mirror")
    adapter.set_project_value(constants.PROJECT_KEYS.reference_start_samples,
      tostring(review.reference_start_samples))
    adapter.set_project_value(constants.PROJECT_KEYS.reference_start_sample_rate,
      tostring(review.sample_rate))
    for _, track in ipairs(review.reference_tracks) do
      adapter.set_track_reference_id(track, reference_id)
    end
    for _, assignment in ipairs(review.track_assignments or {}) do
      adapter.set_track_reference_lane_id(assignment.track_ref, assignment.lane_id)
    end
    for _, item in ipairs(review.reference_items) do
      adapter.set_item_reference_id(item, reference_id)
    end
    for _, assignment in ipairs(review.assignments) do
      local id = adapter.new_id()
      adapter.set_item_reference_item_id(assignment.item_ref, id)
      assignment.manifest_item.itemId = id
    end
    save_registry(adapter, review.registry_after_publish)
    adapter.mark_project_dirty()
    adapter.end_undo("Assign ReaProjectLink Reference identities")
    local saved, save_error = adapter.save_project()
    if not saved then return nil, save_error or "Could not save the Master Project." end

    local snapshot, pointer = reference_manifest.build({
      reference_id = reference_id,
      reference_revision = review.reference_revision,
      master_project_id = master_project_id,
      master_project_name = review.master_project_name,
      published_at = metadata.published_at,
      published_by = metadata.published_by,
      alignment_mode = "mirror",
      sample_rate = review.sample_rate,
      project_timecode_offset_samples = review.project_timecode_offset_samples,
      frame_rate = review.frame_rate,
      reference_start_samples = review.reference_start_samples,
      reference_start_marker_id = review.reference_start_marker_id,
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
    adapter.set_project_value(constants.PROJECT_KEYS.reference_revision,
      tostring(result.reference_revision))
    adapter.mark_project_dirty()
    local revision_saved, revision_save_error = adapter.save_project()
    if not revision_saved then result.project_save_error = revision_save_error end
    return result
  end

  return service
end

return M
