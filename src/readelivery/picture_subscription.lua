local constants = require("readelivery.constants")
local json = require("readelivery.json")

local M = {}

local function read_json(fs, path, label)
  local bytes, read_error = fs.read_file(path)
  if not bytes then return nil, read_error or ("Could not read " .. label .. ".") end
  local ok, value = pcall(json.decode, bytes)
  if not ok then return nil, label .. " is invalid JSON: " .. tostring(value) end
  if value.schemaVersion ~= 1 then
    return nil, label .. " uses an unsupported schema version."
  end
  return value
end

local function load(fs, pointer_path)
  local pointer, pointer_error = read_json(fs, pointer_path, "picture.json")
  if not pointer then return nil, pointer_error end
  local directory = pointer_path:match("^(.*)[/\\][^/\\]+$")
  if not directory then return nil, "Picture pointer path has no parent directory." end
  local snapshot, snapshot_error = read_json(
    fs,
    fs.join(directory, pointer.manifest),
    "Picture Manifest"
  )
  if not snapshot then return nil, snapshot_error end
  if snapshot.pictureId ~= pointer.pictureId or
      snapshot.pictureRevision ~= pointer.latestPictureRevision then
    return nil, "Picture pointer and snapshot identities do not match."
  end
  return { pointer = pointer, snapshot = snapshot }
end

function M.subscribe(adapter, fs, pointer_path)
  if adapter.get_project_value(constants.PROJECT_KEYS.project_mode) ~=
      constants.PROJECT_MODES.source then
    return nil, "Only a Source project can subscribe to Picture."
  end
  local loaded, load_error = load(fs, pointer_path)
  if not loaded then return nil, load_error end

  local existing = adapter.get_project_value(constants.PROJECT_KEYS.picture_id)
  if existing and existing ~= "" and existing ~= loaded.pointer.pictureId then
    return nil, "This Source project is already bound to a different Picture ID."
  end
  adapter.set_project_value(constants.PROJECT_KEYS.picture_manifest_path, pointer_path)
  adapter.set_project_value(constants.PROJECT_KEYS.picture_id, loaded.pointer.pictureId)
  adapter.mark_project_dirty()
  return loaded
end

function M.check(adapter, fs)
  local pointer_path = adapter.get_project_value(constants.PROJECT_KEYS.picture_manifest_path)
  if not pointer_path or pointer_path == "" then
    return nil, "Select picture.json to create a Picture subscription."
  end
  local loaded, load_error = load(fs, pointer_path)
  if not loaded then return nil, load_error end
  local expected_id = adapter.get_project_value(constants.PROJECT_KEYS.picture_id)
  if expected_id and expected_id ~= "" and loaded.pointer.pictureId ~= expected_id then
    return nil, "Subscribed Picture ID changed unexpectedly."
  end

  local actual_hash = fs.hash_file(loaded.snapshot.videoFile)
  local expected_hash = loaded.snapshot.videoHash:gsub("^sha256:", "")
  local available = actual_hash ~= nil and actual_hash == expected_hash
  local video_error
  if not actual_hash then
    video_error = "Picture video is missing or unreadable."
  elseif actual_hash ~= expected_hash then
    video_error = "Picture video hash does not match its published revision."
  end
  return {
    pointer_path = pointer_path,
    picture_id = loaded.pointer.pictureId,
    latest_revision = loaded.pointer.latestPictureRevision,
    synchronized_revision = tonumber(adapter.get_project_value(
      constants.PROJECT_KEYS.synchronized_picture_revision
    )) or 0,
    reviewed_revision = tonumber(adapter.get_project_value(
      constants.PROJECT_KEYS.reviewed_picture_revision
    )) or 0,
    available = available,
    video_error = video_error,
    snapshot = loaded.snapshot,
  }
end

function M.synchronize(adapter, status)
  if not status.available then return nil, status.video_error end
  adapter.begin_undo("Synchronize ReaDelivery Picture")
  local result, sync_error = adapter.sync_picture(status.snapshot)
  if not result then
    adapter.end_undo("Synchronize ReaDelivery Picture")
    return nil, sync_error
  end
  adapter.set_project_value(
    constants.PROJECT_KEYS.synchronized_picture_revision,
    tostring(status.latest_revision)
  )
  adapter.set_project_value(
    constants.PROJECT_KEYS.picture_start_samples,
    tostring(status.snapshot.pictureStartSamples)
  )
  adapter.mark_project_dirty()
  adapter.end_undo("Synchronize ReaDelivery Picture")
  return result
end

function M.mark_reviewed(adapter, status)
  local synchronized = tonumber(adapter.get_project_value(
    constants.PROJECT_KEYS.synchronized_picture_revision
  )) or 0
  if synchronized ~= status.latest_revision then
    return nil, "Synchronize the latest Picture revision before marking it reviewed."
  end
  adapter.set_project_value(
    constants.PROJECT_KEYS.reviewed_picture_revision,
    tostring(status.latest_revision)
  )
  adapter.mark_project_dirty()
  return { reviewed_revision = status.latest_revision }
end

return M
