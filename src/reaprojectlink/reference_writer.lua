local json = require("reaprojectlink.json")
local manifest_validation = require("reaprojectlink.manifest_validation")

local M = {}

local function assert_ok(ok, err)
  if not ok then error(err or "filesystem operation failed", 3) end
end

local function decode_file(fs, path, label)
  local bytes, read_error = fs.read_file(path)
  if not bytes then error(read_error or ("could not read " .. label), 3) end
  local ok, value = pcall(json.decode, bytes)
  if not ok then error(label .. " failed JSON validation: " .. tostring(value), 3) end
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

local function current_revision(input, fs)
  local path = fs.join(input.package_root, "reference.json")
  if not fs.exists(path) then return 0 end
  local bytes, read_error = fs.read_file(path)
  if not bytes then error(read_error or "could not read reference.json", 3) end
  local pointer = json.decode(bytes)
  local valid, validation_error = manifest_validation.reference_pointer(pointer)
  if not valid then error(validation_error, 3) end
  if pointer.masterProjectId ~= input.snapshot.masterProjectId or
      pointer.referenceId ~= input.snapshot.referenceId then
    error("current reference.json belongs to a different Reference", 3)
  end
  return pointer.latestReferenceRevision
end

local function perform_publish(input, fs)
  if input.pointer.schemaVersion ~= 2 or input.snapshot.schemaVersion ~= 2 then
    error("Reference Publish only supports Reference schema version 2", 2)
  end
  local found_revision = current_revision(input, fs)
  if found_revision ~= input.expected_revision then
    error(string.format(
      "Reference Publish base changed: reviewed revision %d, current revision %d",
      input.expected_revision,
      found_revision
    ), 2)
  end

  local staging_root = fs.join(input.package_root, ".staging", input.transaction_id)
  assert_ok(fs.make_directory(staging_root))
  local staged_snapshot = fs.join(staging_root, input.pointer.manifest)
  local snapshot_parent = staged_snapshot:match("^(.*)[/\\][^/\\]+$")
  assert_ok(fs.make_directory(snapshot_parent))
  local snapshot_bytes = json.encode(input.snapshot) .. "\n"
  assert_ok(fs.write_file(staged_snapshot, snapshot_bytes))
  local verified = json.decode(assert(fs.read_file(staged_snapshot)))
  if verified.referenceId ~= input.pointer.referenceId or
      verified.referenceRevision ~= input.pointer.latestReferenceRevision then
    error("staged Reference snapshot identity validation failed", 2)
  end

  local final_snapshot = fs.join(input.package_root, input.pointer.manifest)
  local final_parent = final_snapshot:match("^(.*)[/\\][^/\\]+$")
  assert_ok(fs.make_directory(final_parent))
  if fs.exists(final_snapshot) then
    local existing_snapshot = decode_file(fs, final_snapshot, "existing Reference snapshot")
    if not retry_equivalent(existing_snapshot, input.snapshot) then
      error("immutable Reference snapshot collision: " .. input.pointer.manifest, 2)
    end
  else
    assert_ok(fs.move_file(staged_snapshot, final_snapshot))
  end

  local pointer_temp = fs.join(
    input.package_root,
    ".reference.json." .. input.transaction_id .. ".tmp"
  )
  assert_ok(fs.write_file(pointer_temp, json.encode(input.pointer) .. "\n"))
  local verified_pointer = json.decode(assert(fs.read_file(pointer_temp)))
  if verified_pointer.referenceId ~= input.pointer.referenceId or
      verified_pointer.latestReferenceRevision ~= input.pointer.latestReferenceRevision then
    error("staged Reference pointer identity validation failed", 2)
  end
  assert_ok(fs.atomic_replace(pointer_temp, fs.join(input.package_root, "reference.json")))
  fs.remove_tree(staging_root)
  return {
    reference_revision = input.pointer.latestReferenceRevision,
    manifest_path = final_snapshot,
  }
end

function M.publish(input, fs)
  local token, lock_error = fs.acquire_lock(input.package_root, input.lock_metadata or {})
  if not token then return nil, lock_error or "Reference Publish is locked." end
  local ok, result = xpcall(function() return perform_publish(input, fs) end, debug.traceback)
  fs.remove_tree(fs.join(input.package_root, ".staging", input.transaction_id))
  local released, release_error = fs.release_lock(input.package_root, token)
  if not ok then
    if not released then
      result = result .. "\nReference Publish also failed to release its lock: " ..
        tostring(release_error)
    end
    return nil, result
  end
  if not released then result.lock_release_error = release_error end
  return result
end

return M
