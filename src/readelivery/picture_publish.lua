local constants = require("readelivery.constants")
local json = require("readelivery.json")
local picture_manifest = require("readelivery.picture_manifest")
local default_picture_writer = require("readelivery.picture_writer")

local M = {}

local function project_parts(path)
  local directory, filename = path:match("^(.*)[/\\]([^/\\]+)$")
  if not directory then return nil, nil end
  return directory, filename:gsub("%.[Rr][Pp][Pp]$", "")
end

local function load_pointer(fs, package_root)
  local path = fs.join(package_root, "picture.json")
  if not fs.exists(path) then return nil end
  local bytes, read_error = fs.read_file(path)
  if not bytes then return nil, read_error or "Could not read picture.json." end
  local ok, pointer = pcall(json.decode, bytes)
  if not ok then return nil, "picture.json is invalid JSON: " .. tostring(pointer) end
  if pointer.schemaVersion ~= 1 then
    return nil, "picture.json uses an unsupported schema version."
  end
  return pointer
end

function M.create(dependencies)
  dependencies = dependencies or {}
  local writer = dependencies.picture_writer or default_picture_writer
  local service = {}

  function service.review(adapter, fs)
    if adapter.get_project_value(constants.PROJECT_KEYS.project_mode) ~=
        constants.PROJECT_MODES.mix then
      return nil, "Only a Mix project can Publish Picture."
    end
    local directory, project_name = project_parts(adapter.project_path())
    if not directory then return nil, "Save the Mix project before Picture Publish." end
    local selected = adapter.selected_items()
    if #selected ~= 1 then
      return nil, "Select exactly one authoritative Picture Item."
    end
    local item = selected[1]
    local state = adapter.picture_item_state(item)
    if not state or not state.video_file or state.video_file == "" then
      return nil, "The selected Item has no file-backed video Take."
    end
    if not fs.exists(state.video_file) then
      return nil, "The selected Picture media is missing or offline."
    end

    local package_root = fs.join(directory, "_Delivery", project_name)
    local pointer, pointer_error = load_pointer(fs, package_root)
    if pointer_error then return nil, pointer_error end
    local project_id = adapter.get_project_value(constants.PROJECT_KEYS.picture_id)
    local item_id = adapter.get_item_picture_id(item)
    if project_id and project_id ~= "" and item_id and item_id ~= "" and
        project_id ~= item_id then
      return nil, "Selected Item belongs to a different Picture ID."
    end
    if pointer and project_id and project_id ~= "" and pointer.pictureId ~= project_id then
      return nil, "Published package belongs to a different Picture ID."
    end

    state.item_ref = item
    state.picture_id = (project_id and project_id ~= "" and project_id) or
      (item_id and item_id ~= "" and item_id) or
      (pointer and pointer.pictureId)
    state.picture_revision = (pointer and pointer.latestPictureRevision or 0) + 1
    state.base_revision = pointer and pointer.latestPictureRevision or 0
    state.package_root = package_root
    state.mix_project_name = project_name
    state.video_hash = fs.hash_file(state.video_file)
    if not state.video_hash then return nil, "Could not hash the selected Picture media." end
    return state
  end

  function service.publish(review, adapter, fs, metadata)
    metadata = metadata or {}
    local picture_id = review.picture_id
    if not picture_id or picture_id == "" then picture_id = adapter.new_id() end

    adapter.begin_undo("Assign ReaDelivery Picture identity")
    adapter.set_project_value(constants.PROJECT_KEYS.picture_id, picture_id)
    adapter.set_item_picture_id(review.item_ref, picture_id)
    adapter.mark_project_dirty()
    adapter.end_undo("Assign ReaDelivery Picture identity")
    local saved, save_error = adapter.save_project()
    if not saved then return nil, save_error or "Could not save the Mix project." end

    local snapshot, pointer = picture_manifest.build({
      picture_id = picture_id,
      picture_revision = review.picture_revision,
      mix_project_name = review.mix_project_name,
      published_at = metadata.published_at,
      published_by = metadata.published_by,
      video_file = review.video_file,
      video_hash = review.video_hash,
      sample_rate = review.sample_rate,
      picture_start_samples = review.picture_start_samples,
      source_offset_samples = review.source_offset_samples,
      duration_samples = review.duration_samples,
      playback_rate = review.playback_rate,
      frame_rate = review.frame_rate,
      project_timecode_offset_samples = review.project_timecode_offset_samples,
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

    adapter.set_project_value(
      constants.PROJECT_KEYS.picture_revision,
      tostring(result.picture_revision)
    )
    adapter.mark_project_dirty()
    adapter.save_project()
    return result
  end

  return service
end

return M
