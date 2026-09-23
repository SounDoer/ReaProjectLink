local view_models = require("reaprojectlink.ui.view_models")
local workflow = require("reaprojectlink.ui.workflow")
local card = require("reaprojectlink.ui.views.card")
local header = require("reaprojectlink.ui.views.header")
local reference_update_review = require("reaprojectlink.ui.views.reference_update_review")
local delivery_publish_review = require("reaprojectlink.ui.views.delivery_publish_review")

local M = {}

local REFERENCE_MENU = {
  { id = "detach_items", label = "Detach Selected Items..." },
  { id = "detach_tracks", label = "Detach Selected Tracks..." },
}

local function input(env, state)
  local lanes = env.services.project_service.delivery_tracks(env.adapter)
  local items = 0
  for _, lane in ipairs(lanes) do items = items + lane.item_count end
  return {
    subscribed = state.reference_manifest_path ~= nil and state.reference_manifest_path ~= "",
    synchronized = state.synchronized_reference_revision,
    check = env.app.checks.reference,
    media_error = env.app.media_error,
    track_count = #lanes,
    item_count = items,
    delivery_revision = state.delivery_revision,
  }
end

local function handle(env, action)
  local services, adapter, app = env.services, env.adapter, env.app
  if action == "choose_reference" then
    workflow.choose_reference(env)
  elseif action == "retry" then
    app:request_check()
  elseif action == "review_update" then
    reference_update_review.open(env)
  elseif action == "review_publish" then
    delivery_publish_review.open(env)
  elseif action == "register_tracks" then
    local result, err = services.project_service.register_selected_tracks(adapter)
    workflow.apply(env, result, err)
  elseif action == "unregister_tracks" then
    if workflow.confirm(env.reaper, "Unregister Delivery Tracks",
        "Stop publishing the selected tracks? Their items stay in the project.") then
      local result, err = services.project_service.unregister_selected_tracks(adapter)
      workflow.apply(env, result, err)
    end
  elseif action == "detach_items" then
    if workflow.confirm(env.reaper, "Detach Reference Items",
        "Detach the selected Reference items? Later Reference updates won't change them.") then
      local result, err = services.reference_subscription.detach_selected_reference_items(adapter)
      workflow.apply(env, result, err)
    end
  elseif action == "detach_tracks" then
    if workflow.confirm(env.reaper, "Detach Reference Tracks",
        "Detach the selected Reference tracks? Later Reference updates won't change them.") then
      local result, err = services.reference_subscription.detach_selected_reference_tracks(adapter)
      workflow.apply(env, result, err)
    end
  end
end

function M.draw(env, state)
  local ImGui, ctx, c = env.ImGui, env.ctx, env.c
  local values = input(env, state)
  local cards = view_models.source_cards(values)
  header.draw(env, state, "Source")
  local width, side_by_side = c.card_width()
  local reference_action = card.draw(env, "source-reference", "film", "Reference", cards.reference,
    cards.highlight == "reference", width, values.subscribed and REFERENCE_MENU or nil)
  if side_by_side then ImGui.SameLine(ctx, 0, 12) end
  local delivery_action = card.draw(env, "source-delivery", "upload", "Delivery", cards.delivery,
    cards.highlight == "delivery", width, nil)
  local action = reference_action or delivery_action
  if action then handle(env, action) end
end

return M
