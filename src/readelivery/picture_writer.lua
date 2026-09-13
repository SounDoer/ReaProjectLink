local json = require("readelivery.json")

local M = {}

local function assert_ok(ok, err)
  if not ok then error(err or "filesystem operation failed", 3) end
end

local function current_revision(input, fs)
  local path = fs.join(input.package_root, "picture.json")
  if not fs.exists(path) then return 0 end
  local bytes, read_error = fs.read_file(path)
  if not bytes then error(read_error or "could not read picture.json", 3) end
  local pointer = json.decode(bytes)
  if pointer.schemaVersion ~= 1 then error("unsupported Picture schema version", 3) end
  return pointer.latestPictureRevision
end

local function perform_publish(input, fs)
  local found_revision = current_revision(input, fs)
  if found_revision ~= input.expected_revision then
    error(string.format(
      "Picture Publish base changed: reviewed revision %d, current revision %d",
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
  if verified.pictureId ~= input.pointer.pictureId or
      verified.pictureRevision ~= input.pointer.latestPictureRevision then
    error("staged Picture snapshot identity validation failed", 2)
  end

  local final_snapshot = fs.join(input.package_root, input.pointer.manifest)
  local final_parent = final_snapshot:match("^(.*)[/\\][^/\\]+$")
  assert_ok(fs.make_directory(final_parent))
  if fs.exists(final_snapshot) then
    if fs.read_file(final_snapshot) ~= snapshot_bytes then
      error("immutable Picture snapshot collision: " .. input.pointer.manifest, 2)
    end
  else
    assert_ok(fs.move_file(staged_snapshot, final_snapshot))
  end

  local pointer_temp = fs.join(
    input.package_root,
    ".picture.json." .. input.transaction_id .. ".tmp"
  )
  assert_ok(fs.write_file(pointer_temp, json.encode(input.pointer) .. "\n"))
  local verified_pointer = json.decode(assert(fs.read_file(pointer_temp)))
  if verified_pointer.pictureId ~= input.pointer.pictureId or
      verified_pointer.latestPictureRevision ~= input.pointer.latestPictureRevision then
    error("staged Picture pointer identity validation failed", 2)
  end
  assert_ok(fs.atomic_replace(pointer_temp, fs.join(input.package_root, "picture.json")))
  fs.remove_tree(staging_root)
  return {
    picture_revision = input.pointer.latestPictureRevision,
    manifest_path = final_snapshot,
  }
end

function M.publish(input, fs)
  local token, lock_error = fs.acquire_lock(input.package_root, input.lock_metadata or {})
  if not token then return nil, lock_error or "Picture Publish is locked." end
  local ok, result = xpcall(function() return perform_publish(input, fs) end, debug.traceback)
  fs.remove_tree(fs.join(input.package_root, ".staging", input.transaction_id))
  fs.release_lock(input.package_root, token)
  if not ok then return nil, result end
  return result
end

return M
