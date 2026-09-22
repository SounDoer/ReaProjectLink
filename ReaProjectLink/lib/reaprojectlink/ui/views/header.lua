local view_models = require("reaprojectlink.ui.view_models")
local workflow = require("reaprojectlink.ui.workflow")

local M = {}

function M.draw(env, state, badge, status_text)
  local ImGui, ctx, c, app, theme = env.ImGui, env.ctx, env.c, env.app, env.theme
  c.title(view_models.project_name(state.path))
  ImGui.SameLine(ctx, 0, 8)
  c.badge(badge)

  local label = app.check_phase and "Checking..." or
    view_models.checked_text(app:seconds_since_check()) or "Not checked yet"
  if status_text then label = status_text .. "  ·  " .. label end
  ImGui.PushFont(ctx, theme.fonts.small)
  local label_width = ImGui.CalcTextSize(ctx, label)
  ImGui.PopFont(ctx)
  c.same_line_right(label_width + 8 + c.button_width("Check now") + 8 + ImGui.GetFrameHeight(ctx))
  ImGui.AlignTextToFramePadding(ctx)
  ImGui.PushFont(ctx, theme.fonts.small)
  ImGui.TextColored(ctx, theme.colors.muted, label)
  ImGui.PopFont(ctx)
  ImGui.SameLine(ctx, 0, 8)
  if c.button("Check now") then app:request_check() end
  ImGui.SameLine(ctx, 0, 8)
  if c.icon_button("open-settings", "gear", "Settings") then app:open_settings() end

  ImGui.Separator(ctx)
  workflow.draw_notices(env, state)
end

return M
