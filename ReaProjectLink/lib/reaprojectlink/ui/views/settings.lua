local constants = require("reaprojectlink.constants")
local view_models = require("reaprojectlink.ui.view_models")
local workflow = require("reaprojectlink.ui.workflow")

local M = {}

local THEMES = {
  { id = "auto", label = "Auto" },
  { id = "light", label = "Light" },
  { id = "dark", label = "Dark" },
}

local function draw_reference(env, state)
  local ImGui, ctx, c, adapter = env.ImGui, env.ctx, env.c, env.adapter
  local connected = state.reference_manifest_path ~= nil and state.reference_manifest_path ~= ""
  c.section("Reference")
  c.copy_value("reference-path", "reference.json", connected and state.reference_manifest_path or "Not Connected")
  if c.button(connected and "Change..." or "Choose...") then workflow.choose_reference(env) end
  local mode = adapter.get_project_value(constants.PROJECT_KEYS.reference_alignment_mode) or "mirror"
  local changed, mirror = ImGui.Checkbox(ctx, "Mirror Master Timeline", mode ~= "relative")
  if changed then
    local result, err = env.services.reference_subscription.set_alignment_mode(
      adapter, mirror and "mirror" or "relative"
    )
    workflow.report(env, result, err, mirror and "Mirroring the Master timeline." or
      "Aligning relative to Reference Start.")
  end
end

function M.draw(env, state)
  local ImGui, ctx, c, theme, adapter = env.ImGui, env.ctx, env.c, env.theme, env.adapter
  local source = state.project_type == constants.PROJECT_TYPES.source
  local back = false
  workflow.draw_notices(env)
  if c.begin_page("settings", false) then
    back = c.review_header("Settings")
    c.section("Project")
    c.copy_value("project-name", "Name", view_models.project_name(state.path))
    c.copy_value("project-path", "Project File", state.path ~= "" and state.path or "Not Saved")
    c.copy_value("project-id", "Project ID", state.project_id or "Not Assigned")
    if source then
      c.copy_value("delivery-id", "Delivery ID",
        adapter.get_project_value(constants.PROJECT_KEYS.delivery_id) or "Not Assigned")
      draw_reference(env, state)
    else
      c.copy_value("reference-id", "Reference ID", state.reference_id or "Not Published")
    end
    c.section("Appearance")
    ImGui.AlignTextToFramePadding(ctx)
    c.inline_muted("Theme")
    ImGui.SameLine(ctx, 130)
    local chosen = c.segmented("theme", THEMES, theme.preference)
    if chosen ~= theme.preference then theme:set_preference(chosen) end
    c.section("About")
    local _, _, reaimgui_version = ImGui.GetVersion()
    c.key_value("ReaProjectLink", env.version)
    c.key_value("REAPER", env.reaper.GetAppVersion())
    c.key_value("ReaImGui", tostring(reaimgui_version))
  end
  c.end_page()
  if back then env.app:back() end
end

return M
