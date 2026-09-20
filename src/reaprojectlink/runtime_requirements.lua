local M = {
  minimum_reaper_version = "7.74",
  minimum_reaimgui_api = "0.9",
}

local function version_parts(value)
  local major, minor, patch = tostring(value or ""):match("^(%d+)%.(%d+)%.?(%d*)")
  if not major then return nil end
  return tonumber(major), tonumber(minor), tonumber(patch) or 0
end

local function version_at_least(value, required)
  local major, minor, patch = version_parts(value)
  local required_major, required_minor, required_patch = version_parts(required)
  if not major or not required_major then return false end
  if major ~= required_major then return major > required_major end
  if minor ~= required_minor then return minor > required_minor end
  return patch >= required_patch
end

function M.check_reaper(reaper_api)
  local version = reaper_api.GetAppVersion and reaper_api.GetAppVersion() or "unknown"
  if not version_at_least(version, M.minimum_reaper_version) then
    return nil, string.format(
      "ReaProjectLink requires REAPER %s or newer; current version is %s.",
      M.minimum_reaper_version,
      tostring(version)
    )
  end
  local required_apis = {
    "GetNumRegionsOrMarkers",
    "GetRegionOrMarker",
    "GetRegionOrMarkerInfo_Value",
    "GetSetRegionOrMarkerInfo_String",
    "set_config_var_string",
  }
  for _, name in ipairs(required_apis) do
    if type(reaper_api[name]) ~= "function" then
      return nil, "REAPER is missing the required ReaScript API: " .. name .. "."
    end
  end
  return true
end

M.version_at_least = version_at_least

return M
