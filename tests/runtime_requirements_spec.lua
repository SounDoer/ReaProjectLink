local requirements = require("reaprojectlink.runtime_requirements")

assert(requirements.version_at_least("7.74/x64", "7.74"), "minimum REAPER version")
assert(requirements.version_at_least("7.80", "7.74"), "newer REAPER version")
assert(not requirements.version_at_least("7.73", "7.74"), "older REAPER version")
assert(not requirements.version_at_least("unknown", "7.74"), "unparseable REAPER version")

local function api(version)
  local value = { GetAppVersion = function() return version end }
  for _, name in ipairs({
    "GetNumRegionsOrMarkers",
    "GetRegionOrMarker",
    "GetRegionOrMarkerInfo_Value",
    "GetSetRegionOrMarkerInfo_String",
    "set_config_var_string",
  }) do
    value[name] = function() end
  end
  return value
end

assert(requirements.check_reaper(api("7.74/x64")), "supported REAPER runtime")
local unsupported, unsupported_error = requirements.check_reaper(api("7.73/x64"))
assert(not unsupported and unsupported_error:find("7.74", 1, true), "old REAPER is rejected")
local incomplete = api("7.80/x64")
incomplete.set_config_var_string = nil
local missing, missing_error = requirements.check_reaper(incomplete)
assert(not missing and missing_error:find("set_config_var_string", 1, true), "missing API is named")

return 3
