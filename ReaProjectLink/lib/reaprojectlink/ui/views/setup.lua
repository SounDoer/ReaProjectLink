local workflow = require("reaprojectlink.ui.workflow")

local M = {}

local function choice(env, id, width, icon, title, text, label)
  local c = env.c
  local clicked = false
  if c.begin_card(id, width, false) then
    c.card_header(icon, title)
    c.muted(text)
    env.ImGui.Dummy(env.ctx, 0, 4)
    clicked = c.button(label .. "##" .. id)
  end
  c.end_card()
  return clicked
end

function M.draw(env, state)
  local ImGui, ctx, c, app = env.ImGui, env.ctx, env.c, env.app
  local service = env.services.project_service
  local source, master = false, false
  workflow.draw_notices(env, state)
  if c.begin_page("setup", false) then
    c.title("Set Up ReaProjectLink")
    c.muted("Choose the type for this project.")
    ImGui.Dummy(ctx, 0, 8)
    local width, side_by_side = c.card_width()
    source = choice(env, "setup-source", width, "upload", "Source Project",
      "An editing project that publishes Deliveries to the Master Project.",
      "Initialize Source Project")
    if side_by_side then ImGui.SameLine(ctx, 0, 12) end
    master = choice(env, "setup-master", width, "download", "Master Project",
      "An integration project that publishes the Reference and receives Deliveries.",
      "Initialize Master Project")
  end
  c.end_page()
  if source then
    local result, err = service.initialize_source(env.adapter)
    workflow.report(env, result, err, "Source Project initialized.")
  elseif master then
    local result, err = service.initialize_master(env.adapter)
    workflow.report(env, result, err, "Master Project initialized.")
  end
  if source or master then app:request_check() end
end

return M
