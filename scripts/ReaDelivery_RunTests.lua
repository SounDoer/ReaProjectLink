-- @description ReaDelivery - Run Tests
-- @version 0.1.0-dev
-- @author ReaDelivery contributors

local source = debug.getinfo(1, "S").source:sub(2)
local scripts_dir = source:match("^(.*)[/\\]")
local root = scripts_dir and scripts_dir:match("^(.*)[/\\]scripts$")

if not root then
  reaper.ShowMessageBox("Could not resolve the ReaDelivery repository path.", "ReaDelivery tests", 0)
  return
end

package.path = root .. "/src/?.lua;" .. root .. "/src/?/init.lua;" .. package.path

local temporary_project = root .. "/tests/.manual-runner-project.rpp"
os.remove(temporary_project)
reaper.Main_OnCommand(40859, 0)

local ok, result = xpcall(function()
  local passed = dofile(root .. "/tests/source_service_spec.lua")
  passed = passed + dofile(root .. "/tests/reaper_adapter_spec.lua")
  passed = passed + dofile(root .. "/tests/manifest_spec.lua")
  passed = passed + dofile(root .. "/tests/hash_spec.lua")
  passed = passed + dofile(root .. "/tests/delivery_manifest_spec.lua")
  passed = passed + dofile(root .. "/tests/package_writer_spec.lua")
  passed = passed + dofile(root .. "/tests/filesystem_spec.lua")
  passed = passed + dofile(root .. "/tests/publish_plan_spec.lua")
  passed = passed + dofile(root .. "/tests/source_review_spec.lua")
  passed = passed + dofile(root .. "/tests/source_publish_spec.lua")
  passed = passed + dofile(root .. "/tests/picture_manifest_spec.lua")
  passed = passed + dofile(root .. "/tests/picture_writer_spec.lua")
  passed = passed + dofile(root .. "/tests/picture_publish_spec.lua")
  passed = passed + dofile(root .. "/tests/picture_subscription_spec.lua")
  passed = passed + dofile(root .. "/tests/mix_import_spec.lua")
  passed = passed + dofile(root .. "/tests/mix_update_plan_spec.lua")
  passed = passed + dofile(root .. "/tests/mix_update_spec.lua")
  return passed
end, debug.traceback)

reaper.Main_SaveProjectEx(0, temporary_project, 8)
reaper.Main_OnCommand(40860, 0)
os.remove(temporary_project)

if ok then
  local message = string.format("All %d ReaDelivery tests passed.", result)
  reaper.ShowConsoleMsg(message .. "\n")
  reaper.ShowMessageBox(message, "ReaDelivery tests", 0)
else
  reaper.ShowConsoleMsg("ReaDelivery tests failed:\n" .. tostring(result) .. "\n")
  reaper.ShowMessageBox(tostring(result), "ReaDelivery tests failed", 0)
end
