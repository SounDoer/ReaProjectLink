local source = debug.getinfo(1, "S").source:sub(2)
local tests_dir = source:match("^(.*)[/\\]")
local root = tests_dir and tests_dir:match("^(.*)[/\\]tests$")

if not root then
  return
end

package.path = root .. "/src/?.lua;" .. root .. "/src/?/init.lua;" .. package.path

assert(require("reaprojectlink.runtime_requirements").check_reaper(reaper))

local ok, result = xpcall(function()
  local entry, entry_error = loadfile(root .. "/scripts/ReaProjectLink.lua")
  assert(entry, entry_error)

  local adapter = require("reaprojectlink.reaper_adapter")
  assert(type(adapter.project_path()) == "string")
  assert(type(adapter.all_tracks()) == "table")

  assert(reaper.ImGui_GetBuiltinPath, "ReaImGui is not installed")
  package.path = reaper.ImGui_GetBuiltinPath() .. "/?.lua;" .. package.path
  local ImGui = require("imgui")("0.9")
  local context = ImGui.CreateContext("ReaProjectLink smoke test")
  assert(context, "ReaImGui context creation failed")
  if reaper.ImGui_DestroyContext then
    reaper.ImGui_DestroyContext(context)
  end

  local passed = dofile(root .. "/tests/project_service_spec.lua")
  passed = passed + dofile(root .. "/tests/runtime_requirements_spec.lua")
  passed = passed + dofile(root .. "/tests/reaper_adapter_spec.lua")
  passed = passed + dofile(root .. "/tests/workflow_rollback_spec.lua")
  passed = passed + dofile(root .. "/tests/manifest_spec.lua")
  passed = passed + dofile(root .. "/tests/hash_spec.lua")
  passed = passed + dofile(root .. "/tests/delivery_manifest_spec.lua")
  passed = passed + dofile(root .. "/tests/delivery_writer_spec.lua")
  passed = passed + dofile(root .. "/tests/filesystem_spec.lua")
  passed = passed + dofile(root .. "/tests/delivery_publish_plan_spec.lua")
  passed = passed + dofile(root .. "/tests/delivery_review_spec.lua")
  passed = passed + dofile(root .. "/tests/delivery_publish_spec.lua")
  passed = passed + dofile(root .. "/tests/reference_manifest_spec.lua")
  passed = passed + dofile(root .. "/tests/reference_writer_spec.lua")
  passed = passed + dofile(root .. "/tests/reference_publish_spec.lua")
  passed = passed + dofile(root .. "/tests/reference_subscription_spec.lua")
  passed = passed + dofile(root .. "/tests/delivery_import_spec.lua")
  passed = passed + dofile(root .. "/tests/delivery_update_spec.lua")
  return passed
end, debug.traceback)

local result_path = root .. "/tests/.last-result"
local file = io.open(result_path, "w")
if file then
  if ok then
    file:write(string.format("PASS %d core tests + REAPER/ReaImGui smoke\n", result))
  else
    file:write("FAIL\n", tostring(result), "\n")
  end
  file:close()
end

reaper.atexit(function()
  os.remove(root .. "/tests/.adapter-fixture.wav")
  os.remove(root .. "/tests/.rollback-fixture.wav")
  os.remove(root .. "/tests/.runner-project.rpp")
end)
reaper.Main_SaveProjectEx(0, root .. "/tests/.runner-project.rpp", 8)
reaper.Main_OnCommand(40004, 0)
