local source = debug.getinfo(1, "S").source:sub(2)
local tests_dir = source:match("^(.*)[/\\]")
local root = tests_dir and tests_dir:match("^(.*)[/\\]tests$")

if not root then
  reaper.ShowMessageBox("Could not resolve the ReaProjectLink repository path.", "ReaProjectLink tests", 0)
  return
end

package.path = root .. "/ReaProjectLink/lib/?.lua;" .. package.path

local runtime_requirements = require("reaprojectlink.runtime_requirements")
local runtime_ok, runtime_error = runtime_requirements.check_reaper(reaper)
if not runtime_ok then
  reaper.ShowMessageBox(runtime_error, "ReaProjectLink tests", 0)
  return
end

local temporary_project = root .. "/tests/.manual-runner-project.rpp"
os.remove(temporary_project)
reaper.Main_OnCommand(40859, 0)

local ok, result = xpcall(function()
  local passed = 0
  for _, spec in ipairs(dofile(root .. "/tests/specs.lua")) do
    passed = passed + dofile(root .. "/tests/" .. spec)
  end
  return passed
end, debug.traceback)

reaper.Main_SaveProjectEx(0, temporary_project, 8)
reaper.Main_OnCommand(40860, 0)
os.remove(temporary_project)
os.remove(root .. "/tests/.adapter-fixture.wav")
os.remove(root .. "/tests/.rollback-fixture.wav")

local result_path = os.getenv("REAPROJECTLINK_TEST_RESULT")
local message
if ok then
  message = string.format("All %d ReaProjectLink tests passed.", result)
  reaper.ShowConsoleMsg(message .. "\n")
else
  message = "ReaProjectLink tests failed:\n" .. tostring(result)
  reaper.ShowConsoleMsg(message .. "\n")
end

if result_path and result_path ~= "" then
  local file = io.open(result_path, "w")
  if file then
    file:write(ok and "PASS\n" or "FAIL\n", message, "\n")
    file:close()
  end
  reaper.Main_OnCommand(40004, 0)
elseif ok then
  reaper.ShowMessageBox(message, "ReaProjectLink tests", 0)
else
  reaper.ShowMessageBox(tostring(result), "ReaProjectLink tests failed", 0)
end
