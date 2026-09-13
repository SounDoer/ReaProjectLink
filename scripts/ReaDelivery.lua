-- @description ReaDelivery
-- @version 0.1.0-dev
-- @author ReaDelivery contributors
-- @about
--   Local NAS-based delivery and dependency management for REAPER projects.

local function script_root()
  local source = debug.getinfo(1, "S").source:sub(2)
  local scripts_dir = source:match("^(.*)[/\\]")
  return scripts_dir:match("^(.*)[/\\]scripts$")
end

local root = script_root()
if not root then
  reaper.ShowMessageBox("Could not resolve the ReaDelivery repository path.", "ReaDelivery", 0)
  return
end

package.path = root .. "/src/?.lua;" .. root .. "/src/?/init.lua;" .. package.path

if not reaper.ImGui_GetBuiltinPath then
  reaper.ShowMessageBox(
    "ReaImGui is required. Install it through ReaPack and restart REAPER.",
    "ReaDelivery",
    0
  )
  return
end

package.path = reaper.ImGui_GetBuiltinPath() .. "/?.lua;" .. package.path

local ok_imgui, ImGui = pcall(function()
  return require("imgui")("0.9")
end)
if not ok_imgui then
  reaper.ShowMessageBox("Could not load ReaImGui:\n" .. tostring(ImGui), "ReaDelivery", 0)
  return
end

local adapter = require("readelivery.reaper_adapter")
local source_service = require("readelivery.source_service")

local TITLE = "ReaDelivery"
local ctx = ImGui.CreateContext(TITLE)
local smoke_result_path = os.getenv("READELIVERY_UI_SMOKE_RESULT")
local window_open = true
local message = nil
local message_is_error = false
local scan_result = nil

local function set_result(result, err, success_message)
  if result then
    message = success_message
    message_is_error = false
  else
    message = err
    message_is_error = true
  end
end

local function draw_message()
  if not message then
    return
  end
  if message_is_error then
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xff6b6bff)
  end
  ImGui.TextWrapped(ctx, message)
  if message_is_error then
    ImGui.PopStyleColor(ctx)
  end
  ImGui.Separator(ctx)
end

local function draw_uninitialized(state)
  ImGui.TextWrapped(ctx, "Initialize this saved .rpp as one ReaDelivery project mode.")
  ImGui.Spacing(ctx)

  if ImGui.Button(ctx, "Initialize Source Project") then
    local result, err = source_service.initialize_source(adapter)
    set_result(result, err, "Source Project initialized. Save the project to persist its mode.")
  end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Initialize Mix Project") then
    local result, err = source_service.initialize_mix(adapter)
    set_result(result, err, "Mix Project initialized. Save the project to persist its mode.")
  end

  if state.path == "" then
    ImGui.Spacing(ctx)
    ImGui.TextWrapped(ctx, "This project has no file path. Save it before initialization.")
  end
end

local function draw_scan_result()
  if not scan_result then
    return
  end

  ImGui.Separator(ctx)
  ImGui.Text(ctx, string.format(
    "%d Delivery Lane(s), %d Clip(s), %d untagged, %d blocker(s)",
    #scan_result.lanes,
    scan_result.clip_count,
    scan_result.untagged_count,
    scan_result.blocker_count
  ))

  for _, lane in ipairs(scan_result.lanes) do
    local label = string.format("%s (%d Items)##%s", lane.display_name, #lane.clips, lane.lane_id)
    if ImGui.TreeNode(ctx, label) then
      if lane.track_fx_count > 0 then
        ImGui.TextWrapped(ctx, "Blocked by Track FX (Publish Anyway will be available in review).")
      end
      for _, clip in ipairs(lane.clips) do
        local identity = clip.clip_id and clip.clip_id ~= "" and clip.clip_id or "new Clip"
        ImGui.BulletText(ctx, clip.display_name .. " — " .. identity)
        for _, blocker in ipairs(clip.blockers) do
          ImGui.Indent(ctx)
          ImGui.TextWrapped(ctx, blocker)
          ImGui.Unindent(ctx)
        end
      end
      ImGui.TreePop(ctx)
    end
  end
end

local function draw_source(state)
  ImGui.Text(ctx, "Mode: Source")
  ImGui.TextWrapped(
    ctx,
    "Source ID: " .. (state.source_project_id or "assigned on first Publish")
  )
  ImGui.TextWrapped(ctx, "Project: " .. state.path)
  ImGui.Separator(ctx)

  if ImGui.Button(ctx, "Register Selected Track(s)") then
    local result, err = source_service.register_selected_tracks(adapter)
    local success = result and string.format(
      "Registered %d of %d selected Track(s).",
      result.added,
      result.selected
    )
    set_result(result, err, success)
    scan_result = nil
  end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Remove Selected Track(s)") then
    local result, err = source_service.unregister_selected_tracks(adapter)
    local success = result and string.format(
      "Removed %d of %d selected Track(s).",
      result.removed,
      result.selected
    )
    set_result(result, err, success)
    scan_result = nil
  end

  if ImGui.Button(ctx, "Scan Delivery Tracks") then
    local result, err = source_service.scan(adapter)
    if result then
      scan_result = result
      message = "Delivery scan complete."
      message_is_error = false
    else
      set_result(nil, err, nil)
    end
  end

  draw_scan_result()
end

local function draw_mix(state)
  ImGui.Text(ctx, "Mode: Mix")
  ImGui.TextWrapped(ctx, "Project: " .. state.path)
  ImGui.Separator(ctx)
  ImGui.TextWrapped(ctx, "Mix import will be added after the Source Publish vertical slice.")
end

local function draw()
  ImGui.SetNextWindowSize(ctx, 720, 520, ImGui.Cond_FirstUseEver)
  local visible
  visible, window_open = ImGui.Begin(ctx, TITLE, window_open)
  if visible then
    draw_message()
    local state = source_service.project_state(adapter)
    if not state.mode or state.mode == "" then
      draw_uninitialized(state)
    elseif state.mode == "source" then
      draw_source(state)
    elseif state.mode == "mix" then
      draw_mix(state)
    else
      ImGui.TextWrapped(ctx, "Unsupported project mode: " .. tostring(state.mode))
    end
  end
  ImGui.End(ctx)
end

local function loop()
  local ok, err = xpcall(draw, debug.traceback)
  if not ok then
    if smoke_result_path then
      local file = io.open(smoke_result_path, "w")
      if file then
        file:write("FAIL\n", tostring(err), "\n")
        file:close()
      end
      reaper.Main_OnCommand(40004, 0)
      return
    end
    reaper.ShowConsoleMsg("ReaDelivery error:\n" .. tostring(err) .. "\n")
    reaper.ShowMessageBox(tostring(err), "ReaDelivery error", 0)
    return
  end
  if smoke_result_path then
    local file = io.open(smoke_result_path, "w")
    if file then
      file:write("PASS ReaDelivery UI frame\n")
      file:close()
    end
    window_open = false
    reaper.Main_OnCommand(40004, 0)
    return
  end
  if window_open then
    reaper.defer(loop)
  end
end

reaper.atexit(function()
  if ctx and reaper.ImGui_DestroyContext then
    reaper.ImGui_DestroyContext(ctx)
  end
  ctx = nil
end)

reaper.defer(loop)
