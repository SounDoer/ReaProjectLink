-- @description ReaProjectLink
-- @version 0.1.0
-- @author ReaProjectLink contributors
-- @changelog
--   Initial release.
-- @about
--   Source-Master project coordination for REAPER on shared storage.
--
--   Requires REAPER 7.74 or newer and ReaImGui 0.9 or newer (install ReaImGui
--   through ReaPack).
-- @link GitHub https://github.com/SounDoer/ReaProjectLink
-- @provides
--   [nomain] lib/reaprojectlink/*.lua
--   [nomain] lib/reaprojectlink/ui/*.lua
--   [nomain] lib/reaprojectlink/ui/views/*.lua

local source = debug.getinfo(1, "S").source:sub(2)
local script_dir = source:match("^(.*)[/\\]")
if not script_dir then
  reaper.ShowMessageBox("Could not resolve the script path.", "ReaProjectLink", 0)
  return
end
package.path = script_dir .. "/lib/?.lua;" .. package.path
local runtime_requirements = require("reaprojectlink.runtime_requirements")
local runtime_ok, runtime_error = runtime_requirements.check_reaper(reaper)
if not runtime_ok then
  reaper.ShowMessageBox(runtime_error, "ReaProjectLink", 0)
  return
end
if not reaper.ImGui_GetBuiltinPath then
  reaper.ShowMessageBox(
    "Install ReaImGui " .. runtime_requirements.minimum_reaimgui_api ..
      " or newer through ReaPack and restart REAPER.",
    "ReaProjectLink",
    0
  )
  return
end
package.path = reaper.ImGui_GetBuiltinPath() .. "/?.lua;" .. package.path
local ok_imgui, ImGui = pcall(function() return require("imgui")("0.9") end)
if not ok_imgui then
  reaper.ShowMessageBox(
    "Could not load the ReaImGui " .. runtime_requirements.minimum_reaimgui_api ..
      " compatibility API:\n" .. tostring(ImGui),
    "ReaProjectLink",
    0
  )
  return
end

local function script_version()
  local file = io.open(source, "r")
  if not file then return "unknown" end
  local header = file:read(512) or ""
  file:close()
  return header:match("@version%s+(%S+)") or "unknown"
end

local ctx = ImGui.CreateContext("ReaProjectLink")
local shell = require("reaprojectlink.ui.app").create({
  ImGui = ImGui,
  ctx = ctx,
  reaper = reaper,
  adapter = require("reaprojectlink.reaper_adapter"),
  fs = require("reaprojectlink.filesystem").create(reaper),
  version = script_version(),
  services = {
    project_service = require("reaprojectlink.project_service"),
    reference_subscription = require("reaprojectlink.reference_subscription"),
    reference_publish = require("reaprojectlink.reference_publish").create(),
    delivery_publish = require("reaprojectlink.delivery_publish").create(),
    delivery_import = require("reaprojectlink.delivery_import"),
    delivery_update = require("reaprojectlink.delivery_update"),
  },
})

-- tests/run_ui_smoke.lua sets REAPROJECTLINK_SMOKE_SCENARIOS before loading
-- this script; each scenario is rendered for one frame.
local smoke_path = os.getenv("REAPROJECTLINK_UI_SMOKE_RESULT")
local smoke_scenarios = REAPROJECTLINK_SMOKE_SCENARIOS or {}
local smoke_frame = 0

local function finish_smoke(ok, err)
  local file = io.open(smoke_path, "w")
  if file then
    file:write(ok and string.format("PASS ReaProjectLink UI frames (%d scenarios)\n", #smoke_scenarios) or
      ("FAIL\n" .. tostring(err) .. "\n"))
    file:close()
  end
  shell.open = false
  reaper.Main_OnCommand(40004, 0)
end

local function loop()
  if smoke_path then
    smoke_frame = smoke_frame + 1
    local scenario = smoke_scenarios[smoke_frame]
    if scenario then shell.apply_smoke(scenario) end
  end
  local ok, err = xpcall(shell.draw, debug.traceback)
  if smoke_path then
    if not ok or smoke_frame > #smoke_scenarios then
      finish_smoke(ok, err)
      return
    end
  elseif not ok then
    reaper.ShowConsoleMsg("ReaProjectLink error:\n" .. tostring(err) .. "\n")
    reaper.ShowMessageBox(tostring(err), "ReaProjectLink error", 0)
    return
  end
  if shell.open then reaper.defer(loop) end
end

reaper.atexit(function()
  if ctx and reaper.ImGui_DestroyContext then reaper.ImGui_DestroyContext(ctx) end
  ctx = nil
end)
reaper.defer(loop)
