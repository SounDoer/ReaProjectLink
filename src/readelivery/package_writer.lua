local json = require("readelivery.json")
local manifest_validation = require("readelivery.manifest_validation")

local M = {}

local function assert_ok(ok, err)
  if not ok then
    error(err or "filesystem operation failed", 3)
  end
end

local function parent_path(path)
  return path:match("^(.*)/[^/]+$")
end

local function current_revision(input, fs)
  local pointer_path = fs.join(input.package_root, "delivery.json")
  if not fs.exists(pointer_path) then
    return 0
  end
  local bytes, read_error = fs.read_file(pointer_path)
  if not bytes then
    error(read_error or "could not read current delivery.json", 3)
  end
  local pointer = json.decode(bytes)
  local valid, validation_error = manifest_validation.delivery_pointer(pointer)
  if not valid then error(validation_error, 3) end
  if pointer.sourceProjectId ~= input.snapshot.sourceProjectId or
      pointer.deliverySetId ~= input.snapshot.deliverySetId then
    error("current delivery.json belongs to a different Source package", 3)
  end
  return pointer.latestPublishRevision
end

local function read_json(fs, path, label)
  local bytes, read_error = fs.read_file(path)
  if not bytes then
    error(read_error or ("could not read " .. label), 3)
  end
  local ok, value = pcall(json.decode, bytes)
  if not ok then
    error(label .. " failed JSON validation: " .. tostring(value), 3)
  end
  return value
end

local function retry_equivalent(left, right)
  local function without_publication_metadata(value)
    local copy = {}
    for key, entry in pairs(value) do
      if key ~= "publishedAt" and key ~= "publishedBy" then copy[key] = entry end
    end
    return copy
  end
  return json.encode(without_publication_metadata(left)) ==
    json.encode(without_publication_metadata(right))
end

local function perform_publish(input, fs)
  local found_revision = current_revision(input, fs)
  if found_revision ~= input.expected_revision then
    error(string.format(
      "Publish base changed: reviewed revision %d, current revision %d",
      input.expected_revision,
      found_revision
    ), 2)
  end

  local staging_root = fs.join(
    input.package_root,
    ".staging",
    input.transaction_id
  )
  assert_ok(fs.make_directory(staging_root))

  local staged_media = {}
  for _, media in ipairs(input.media or {}) do
    local final_path = fs.join(input.package_root, media.destination)
    if fs.exists(final_path) then
      if fs.file_size(final_path) ~= media.size or
          fs.hash_file(final_path) ~= media.hash then
        error("immutable media destination collision: " .. media.destination, 2)
      end
    else
    local staged_path = fs.join(staging_root, media.destination)
    assert_ok(fs.make_directory(parent_path(staged_path)))
    assert_ok(fs.copy_file(media.source_path, staged_path))

    local size = fs.file_size(staged_path)
    if size ~= media.size then
      error("staged media size mismatch: " .. media.destination, 2)
    end
    local digest = fs.hash_file(staged_path)
    if digest ~= media.hash then
      error("staged media hash mismatch: " .. media.destination, 2)
    end
    table.insert(staged_media, {
      staged_path = staged_path,
      final_path = final_path,
    })
    end
  end

  local staged_snapshot = fs.join(staging_root, input.pointer.manifest)
  assert_ok(fs.make_directory(parent_path(staged_snapshot)))
  local snapshot_bytes = json.encode(input.snapshot) .. "\n"
  assert_ok(fs.write_file(staged_snapshot, snapshot_bytes))
  local verified_snapshot = read_json(fs, staged_snapshot, "staged snapshot")
  if verified_snapshot.schemaVersion ~= input.snapshot.schemaVersion or
      verified_snapshot.sourceProjectId ~= input.snapshot.sourceProjectId or
      verified_snapshot.publishRevision ~= input.snapshot.publishRevision then
    error("staged snapshot identity validation failed", 2)
  end

  for _, media in ipairs(staged_media) do
    assert_ok(fs.make_directory(parent_path(media.final_path)))
    assert_ok(fs.move_file(media.staged_path, media.final_path))
  end

  local final_snapshot = fs.join(input.package_root, input.pointer.manifest)
  assert_ok(fs.make_directory(parent_path(final_snapshot)))
  if fs.exists(final_snapshot) then
    local existing_snapshot = read_json(fs, final_snapshot, "existing Publish snapshot")
    if not retry_equivalent(existing_snapshot, input.snapshot) then
      error("immutable Publish snapshot collision: " .. input.pointer.manifest, 2)
    end
  else
    assert_ok(fs.move_file(staged_snapshot, final_snapshot))
  end

  local pointer_temp = fs.join(
    input.package_root,
    ".delivery.json." .. input.transaction_id .. ".tmp"
  )
  assert_ok(fs.write_file(pointer_temp, json.encode(input.pointer) .. "\n"))
  local verified_pointer = read_json(fs, pointer_temp, "staged delivery pointer")
  if verified_pointer.schemaVersion ~= input.pointer.schemaVersion or
      verified_pointer.sourceProjectId ~= input.pointer.sourceProjectId or
      verified_pointer.latestPublishRevision ~= input.pointer.latestPublishRevision or
      verified_pointer.manifest ~= input.pointer.manifest then
    error("staged delivery pointer identity validation failed", 2)
  end
  assert_ok(fs.atomic_replace(
    pointer_temp,
    fs.join(input.package_root, "delivery.json")
  ))

  fs.remove_tree(staging_root)
  return {
    publish_revision = input.pointer.latestPublishRevision,
    manifest_path = final_snapshot,
  }
end

function M.publish(input, fs)
  local lock_token, lock_error = fs.acquire_lock(
    input.package_root,
    input.lock_metadata or {}
  )
  if not lock_token then
    return nil, lock_error or "Publish is locked by another user."
  end

  local ok, result = xpcall(function()
    return perform_publish(input, fs)
  end, debug.traceback)

  local staging_root = fs.join(
    input.package_root,
    ".staging",
    input.transaction_id
  )
  fs.remove_tree(staging_root)
  local released, release_error = fs.release_lock(input.package_root, lock_token)

  if not ok then
    if not released then
      result = result .. "\nPublish also failed to release its lock: " .. tostring(release_error)
    end
    return nil, result
  end
  if not released then result.lock_release_error = release_error end
  return result
end

return M
