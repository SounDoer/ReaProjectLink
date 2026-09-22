local constants = require("reaprojectlink.constants")
local theme_module = require("reaprojectlink.ui.theme")
local components = require("reaprojectlink.ui.components")
local app_state = require("reaprojectlink.ui.app_state")
local checks = require("reaprojectlink.ui.checks")
local setup = require("reaprojectlink.ui.views.setup")
local settings = require("reaprojectlink.ui.views.settings")
local source_main = require("reaprojectlink.ui.views.source_main")
local master_main = require("reaprojectlink.ui.views.master_main")

local REVIEWS = {
  reference_update = require("reaprojectlink.ui.views.reference_update_review"),
  delivery_publish = require("reaprojectlink.ui.views.delivery_publish_review"),
  reference_publish = require("reaprojectlink.ui.views.reference_publish_review"),
  delivery_import = require("reaprojectlink.ui.views.delivery_sync_review"),
  delivery_update = require("reaprojectlink.ui.views.delivery_sync_review"),
}

local M = {}

-- deps: ImGui, ctx, reaper, adapter, fs, services, version.
function M.create(deps)
  local ImGui, ctx, adapter = deps.ImGui, deps.ctx, deps.adapter
  local theme = theme_module.create(ImGui, ctx, deps.reaper)
  local env = {
    ImGui = ImGui,
    ctx = ctx,
    reaper = deps.reaper,
    adapter = adapter,
    fs = deps.fs,
    services = deps.services,
    version = deps.version,
    theme = theme,
    c = components.create(ImGui, ctx, theme),
    app = app_state.new(deps.reaper.time_precise),
  }
  local shell = { open = true, env = env }
  local project_token = adapter.project_token()
  local fixed_width
  env.app:request_check()

  local function run_due_check(state)
    if not env.app:check_due() then return end
    if state.project_type == constants.PROJECT_TYPES.source then
      checks.run_source(env)
    elseif state.project_type == constants.PROJECT_TYPES.master then
      checks.run_master(env)
    end
    env.app:finish_check()
  end

  local function draw_body(state)
    local app = env.app
    if not state.project_type or state.project_type == "" then
      setup.draw(env, state)
    elseif app.view == "settings" then
      settings.draw(env, state)
    elseif app.review and REVIEWS[app.review.kind] then
      REVIEWS[app.review.kind].draw(env, state)
    elseif state.project_type == constants.PROJECT_TYPES.source then
      source_main.draw(env, state)
    elseif state.project_type == constants.PROJECT_TYPES.master then
      master_main.draw(env, state)
    else
      ImGui.TextWrapped(ctx, "Unsupported project type: " .. tostring(state.project_type))
    end
  end

  function shell.draw()
    local token = adapter.project_token()
    if token ~= project_token then
      project_token = token
      env.app:reset()
      env.app:request_check()
    end
    theme:refresh()
    if fixed_width then
      ImGui.SetNextWindowSize(ctx, fixed_width, 720, ImGui.Cond_Always)
    else
      ImGui.SetNextWindowSize(ctx, 1040, 720, ImGui.Cond_FirstUseEver)
    end
    theme:push()
    local visible
    visible, shell.open = ImGui.Begin(ctx, "ReaProjectLink", shell.open)
    if visible then
      ImGui.PushFont(ctx, theme.fonts.body)
      local state = deps.services.project_service.project_state(adapter)
      run_due_check(state)
      if state.project_type == constants.PROJECT_TYPES.master then
        master_main.confirm_moved_items(env)
      end
      draw_body(state)
      ImGui.PopFont(ctx)
      -- ReaImGui only accepts End() when Begin() returned true, unlike Dear ImGui.
      ImGui.End(ctx)
    end
    theme:pop()
  end

  -- Prepares one smoke-test frame: project type, theme, width, and view.
  function shell.apply_smoke(scenario)
    deps.reaper.SetProjExtState(0, constants.EXTENSION_NAME,
      constants.PROJECT_KEYS.project_type, scenario.project_type)
    theme:use(scenario.theme)
    fixed_width = scenario.width
    env.app:reset()
    env.app:request_check()
    -- Force the "shown" phase so the pointer check runs during this scenario's
    -- frame, exercising checks.run_source/run_master and the checked states.
    env.app.check_phase = "shown"
    if scenario.view == "settings" then
      env.app:open_settings()
    elseif scenario.review then
      env.app:open_review(scenario.review.kind, scenario.review.fields())
    end
  end

  return shell
end

return M
