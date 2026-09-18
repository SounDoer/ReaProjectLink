local json = require("readelivery.json")
local sha256 = require("readelivery.sha256")

local M = {}

function M.create(reaper_api)
  local fs = {}
  local separator = package.config:sub(1, 1)

  local function directory_exists(path)
    local normalized = path:gsub("[/\\]+$", "")
    local parent, name = normalized:match("^(.*)[/\\]([^/\\]+)$")
    if not parent then return false end
    reaper_api.EnumerateSubdirectories(parent, -1)
    local index = 0
    while true do
      local candidate = reaper_api.EnumerateSubdirectories(parent, index)
      if not candidate then return false end
      if candidate:lower() == name:lower() then return true end
      index = index + 1
    end
  end

  local function powershell_literal(value)
    return "'" .. value:gsub("'", "''") .. "'"
  end

  local function posix_literal(value)
    return "'" .. value:gsub("'", "'\\''") .. "'"
  end

  -- The pure Lua digest runs at a few MB/s, which stalls the UI thread on
  -- picture and media files. Prefer the platform hashing tool and keep the
  -- Lua implementation as a fallback.
  local function native_hash_file(path)
    local command
    if separator == "\\" then
      command = 'certutil -hashfile "' .. path .. '" SHA256'
    else
      command = "shasum -a 256 " .. posix_literal(path)
    end
    local output = reaper_api.ExecProcess(command, 0)
    if not output then return nil end
    if tonumber(output:match("^(-?%d+)")) ~= 0 then return nil end
    for line in output:gmatch("[^\r\n]+") do
      local compact = line:gsub("%s", "")
      if #compact == 64 and compact:match("^%x+$") then return compact:lower() end
      local token = line:match("^%s*(%x+)%s")
      if token and #token == 64 then return token:lower() end
    end
    return nil
  end

  local function windows_atomic_replace(source, destination)
    local script = table.concat({
      "& {",
      "$source = " .. powershell_literal(source) .. ";",
      "$destination = " .. powershell_literal(destination) .. ";",
      "$backup = $destination + '.replace-backup';",
      "$ErrorActionPreference = 'Stop';",
      "try {",
      "if ([IO.File]::Exists($destination)) {",
      "if ([IO.File]::Exists($backup)) { [IO.File]::Delete($backup) };",
      "[IO.File]::Replace($source, $destination, $backup, $true);",
      "[IO.File]::Delete($backup)",
      "} else {",
      "[IO.File]::Move($source, $destination)",
      "}",
      "} catch { [Console]::Error.WriteLine($_); exit 1 }",
      "}",
    }, " ")
    local command = 'powershell.exe -NoProfile -NonInteractive -Command "' ..
      script .. '"'
    local output = reaper_api.ExecProcess(command, 30000)
    local exit_code = output and tonumber(output:match("^(-?%d+)"))
    if exit_code ~= 0 then
      return nil, output or "PowerShell atomic replacement failed"
    end
    return true
  end

  local function remove_empty_directory(path)
    if separator ~= "\\" then
      return os.remove(path)
    end
    local script = table.concat({
      "& {",
      "$ErrorActionPreference = 'Stop';",
      "try { [IO.Directory]::Delete(" .. powershell_literal(path) .. ") }",
      "catch { [Console]::Error.WriteLine($_); exit 1 }",
      "}",
    }, " ")
    local command = 'powershell.exe -NoProfile -NonInteractive -Command "' ..
      script .. '"'
    local output = reaper_api.ExecProcess(command, 30000)
    local exit_code = output and tonumber(output:match("^(-?%d+)"))
    if exit_code ~= 0 then
      return nil, output or "could not remove directory"
    end
    return true
  end

  function fs.join(...)
    local parts = { ... }
    local result = tostring(parts[1] or "")
    for index = 2, #parts do
      local part = tostring(parts[index])
      result = result:gsub("[/\\]+$", "") .. separator ..
        part:gsub("^[/\\]+", "")
    end
    return result
  end

  function fs.exists(path)
    return reaper_api.file_exists(path) or directory_exists(path)
  end

  function fs.make_directory(path)
    local created = reaper_api.RecursiveCreateDirectory(path, 0)
    if created == 0 and not directory_exists(path) then
      return nil, "could not create directory: " .. path
    end
    return true
  end

  function fs.read_file(path)
    local file, open_error = io.open(path, "rb")
    if not file then
      return nil, open_error
    end
    local bytes = file:read("*a")
    file:close()
    return bytes
  end

  function fs.write_file(path, bytes)
    local file, open_error = io.open(path, "wb")
    if not file then
      return nil, open_error
    end
    local ok, write_error = file:write(bytes)
    local close_ok, close_error = file:close()
    if not ok then
      return nil, write_error
    end
    if not close_ok then
      return nil, close_error
    end
    return true
  end

  function fs.copy_file(source, destination)
    local input, input_error = io.open(source, "rb")
    if not input then
      return nil, input_error
    end
    local output, output_error = io.open(destination, "wb")
    if not output then
      input:close()
      return nil, output_error
    end

    while true do
      local bytes = input:read(1024 * 1024)
      if not bytes then break end
      local ok, write_error = output:write(bytes)
      if not ok then
        input:close()
        output:close()
        return nil, write_error
      end
    end

    input:close()
    local close_ok, close_error = output:close()
    if not close_ok then
      return nil, close_error
    end
    return true
  end

  function fs.file_size(path)
    local file = io.open(path, "rb")
    if not file then return nil end
    local size = file:seek("end")
    file:close()
    return size
  end

  function fs.hash_file(path)
    return native_hash_file(path) or sha256.file(path)
  end

  function fs.move_file(source, destination)
    if fs.exists(destination) then
      return nil, "destination already exists: " .. destination
    end
    local ok, move_error = os.rename(source, destination)
    if not ok then return nil, move_error end
    return true
  end

  function fs.atomic_replace(source, destination)
    if separator == "\\" then
      return windows_atomic_replace(source, destination)
    end
    local ok, move_error = os.rename(source, destination)
    if not ok then return nil, move_error end
    return true
  end

  function fs.remove_tree(path)
    local files = {}
    reaper_api.EnumerateFiles(path, -1)
    local file_index = 0
    while true do
      local name = reaper_api.EnumerateFiles(path, file_index)
      if not name then break end
      table.insert(files, name)
      file_index = file_index + 1
    end
    for _, name in ipairs(files) do
      local ok, remove_error = os.remove(fs.join(path, name))
      if not ok then return nil, remove_error end
    end

    local directories = {}
    reaper_api.EnumerateSubdirectories(path, -1)
    local directory_index = 0
    while true do
      local name = reaper_api.EnumerateSubdirectories(path, directory_index)
      if not name then break end
      table.insert(directories, name)
      directory_index = directory_index + 1
    end
    for _, name in ipairs(directories) do
      local ok, remove_error = fs.remove_tree(fs.join(path, name))
      if not ok then return nil, remove_error end
    end

    local ok, remove_error = remove_empty_directory(path)
    if not ok and fs.exists(path) then return nil, remove_error end
    return true
  end

  function fs.acquire_lock(package_root, metadata)
    local ok, directory_error = fs.make_directory(package_root)
    if not ok then return nil, directory_error end

    local lock_path = fs.join(package_root, ".publish.lock")
    local token = reaper_api.genGuid(""):gsub("[{}]", ""):lower()
    local temporary_path = lock_path .. "." .. token .. ".tmp"
    local file, open_error = io.open(temporary_path, "wb")
    if not file then
      return nil, open_error
    end

    metadata = metadata or {}
    metadata.token = token
    local write_ok, write_error = file:write(json.encode(metadata) .. "\n")
    local close_ok, close_error = file:close()
    if not write_ok or not close_ok then
      os.remove(temporary_path)
      return nil, write_error or close_error
    end

    local moved, move_error = os.rename(temporary_path, lock_path)
    if not moved then
      os.remove(temporary_path)
      local existing = fs.read_file(lock_path)
      return nil, existing or move_error or "Publish is locked."
    end
    return token
  end

  function fs.release_lock(package_root, token)
    local lock_path = fs.join(package_root, ".publish.lock")
    local bytes = fs.read_file(lock_path)
    if not bytes then return true end
    local ok, metadata = pcall(json.decode, bytes)
    if not ok or metadata.token ~= token then
      return nil, "Publish lock ownership changed; lock was not removed."
    end
    local removed, remove_error = os.remove(lock_path)
    if not removed then return nil, remove_error end
    return true
  end

  function fs.read_lock(package_root)
    local lock_path = fs.join(package_root, ".publish.lock")
    local bytes, read_error = fs.read_file(lock_path)
    if not bytes then return nil, read_error or "Publish lock was not found." end
    local ok, metadata = pcall(json.decode, bytes)
    if not ok then return nil, "Publish lock metadata is invalid: " .. tostring(metadata) end
    return metadata
  end

  function fs.remove_lock(package_root, expected_token)
    local metadata, read_error = fs.read_lock(package_root)
    if not metadata then return nil, read_error end
    if not expected_token or metadata.token ~= expected_token then
      return nil, "Publish lock changed; it was not removed."
    end
    local lock_path = fs.join(package_root, ".publish.lock")
    local removed, remove_error = os.remove(lock_path)
    if not removed then return nil, remove_error end
    return true
  end

  return fs
end

return M
