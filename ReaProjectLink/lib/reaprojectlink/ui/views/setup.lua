local workflow = require("reaprojectlink.ui.workflow")

local M = {}

local function choice(env, id, width, title, text, label)
  local c = env.c
  local clicked = false
  if c.begin_card(id, width, false) then
    c.heading(title)
    c.muted(text)
    clicked = c.button(label .. "##" .. id)
  end
  c.end_card()
  return clicked
end

function M.draw(env, state)
  local ImGui, ctx, c, app = env.ImGui, env.ctx, env.c, env.app
  local service = env.services.project_service
  c.title("Set Up ReaProjectLink")
  c.muted("Choose what this REAPER project is.")
  workflow.draw_notices(env, state)
  local width, side_by_side = c.card_width()
  local source = choice(env, "setup-source", width, "This Is a Department Project",
    "Dialogue, music, or sound design. You publish bounced audio for the mix project.",
    "Set Up as Source")
  if side_by_side then ImGui.SameLine(ctx, 0, 12) end
  local master = choice(env, "setup-master", width, "This Is the Mix Project",
    "You publish the Reference and bring in deliveries from each department.",
    "Set Up as Master")
  if source then
    local result, err = service.initialize_source(env.adapter)
    workflow.report(env, result, err, "Source project set up.")
  elseif master then
    local result, err = service.initialize_master(env.adapter)
    workflow.report(env, result, err, "Master project set up.")
  end
  if source or master then app:request_check() end
end

return M
