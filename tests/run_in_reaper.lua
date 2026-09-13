local source = debug.getinfo(1, "S").source:sub(2)
local tests_dir = source:match("^(.*)[/\\]")
local root = tests_dir and tests_dir:match("^(.*)[/\\]tests$")

if not root then
  return
end

package.path = root .. "/src/?.lua;" .. root .. "/src/?/init.lua;" .. package.path

local ok, result = xpcall(function()
  local entry, entry_error = loadfile(root .. "/scripts/ReaDelivery.lua")
  assert(entry, entry_error)

  local adapter = require("readelivery.reaper_adapter")
  assert(type(adapter.project_path()) == "string")
  assert(type(adapter.all_tracks()) == "table")

  assert(reaper.ImGui_GetBuiltinPath, "ReaImGui is not installed")
  package.path = reaper.ImGui_GetBuiltinPath() .. "/?.lua;" .. package.path
  local ImGui = require("imgui")("0.9")
  local context = ImGui.CreateContext("ReaDelivery smoke test")
  assert(context, "ReaImGui context creation failed")
  if reaper.ImGui_DestroyContext then
    reaper.ImGui_DestroyContext(context)
  end

  local passed = dofile(root .. "/tests/source_service_spec.lua")
  passed = passed + dofile(root .. "/tests/manifest_spec.lua")
  passed = passed + dofile(root .. "/tests/hash_spec.lua")
  passed = passed + dofile(root .. "/tests/delivery_manifest_spec.lua")
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

reaper.Main_OnCommand(40004, 0)
