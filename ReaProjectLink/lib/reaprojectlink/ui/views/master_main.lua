local view_models = require("reaprojectlink.ui.view_models")
local workflow = require("reaprojectlink.ui.workflow")
local checks = require("reaprojectlink.ui.checks")
local card = require("reaprojectlink.ui.views.card")
local header = require("reaprojectlink.ui.views.header")
local reference_publish_review = require("reaprojectlink.ui.views.reference_publish_review")
local delivery_sync_review = require("reaprojectlink.ui.views.delivery_sync_review")

local M = {}

local REFERENCE_MENU = {
  { id = "set_start", label = "Set Selected Marker as Reference Start" },
  { separator = true },
  { id = "reset_items", label = "Treat Selected Items as New..." },
  { id = "reset_tracks", label = "Treat Selected Tracks as New..." },
}

local ROW_MENU = {
  { id = "sync_other", label = "Sync to Another Revision..." },
  { id = "remove", label = "Remove Subscription..." },
}

local function input(env, state)
  local services, adapter, app = env.services, env.adapter, env.app
  local tracks = services.reference_publish.reference_tracks(adapter)
  local timeline_entries, marker_error = services.reference_publish.timeline_entries(adapter)
  local markers, regions = 0, 0
  for _, entry in ipairs(timeline_entries or {}) do
    if entry.registered then
      if entry.kind == "region" then regions = regions + 1
      else markers = markers + 1 end
    end
  end
  local rows = {}
  for _, entry in ipairs(checks.subscriptions(adapter)) do
    local unmapped = 0
    for _, binding in ipairs(entry.lanes or {}) do
      if binding.unmapped then unmapped = unmapped + 1 end
    end
    table.insert(rows, {
      id = entry.sourceProjectId,
      name = view_models.subscription_name(entry),
      accepted = entry.acceptedDeliveryRevision or 0,
      unmapped_count = unmapped,
      check = app.checks.deliveries[entry.sourceProjectId],
    })
  end
  return {
    track_count = #tracks,
    marker_count = markers,
    region_count = regions,
    marker_error = marker_error,
    reference_revision = state.reference_revision,
    package_check = app.checks.reference,
    selection_counts = services.reference_publish.selection_counts(adapter),
    rows = rows,
  }
end

-- Moving a managed Item away from its bound Track prompts once (D083). The
-- app shell calls this once per frame for every Master view (main panel,
-- Reviews, Settings).
function M.confirm_moved_items(env)
  local adapter, app = env.adapter, env.app
  local change_count = adapter.project_change_count()
  if change_count == app.moved_items_change_count then return end
  app.moved_items_change_count = change_count
  local moved = env.services.delivery_update.moved_instances(adapter)
  if #moved == 0 then return end
  local confirmed = env.reaper.ShowMessageBox(
    string.format(
      "%d synchronized Item(s) were moved out of their mapped Track.\n\n" ..
      "Keep them as local Master content? They will no longer be updated from the Source.\n\n" ..
      "Choose No to keep them Source-managed; the next synchronization will replace them.",
      #moved
    ),
    "Keep Moved Items as Local",
    4
  ) == 6
  if confirmed then
    local result, err = env.services.delivery_update.detach_many(adapter, moved)
    workflow.report(env, result, err, function(value)
      return string.format("Kept %s as local content.", view_models.count(value.detached, "moved item"))
    end)
    app.moved_items_change_count = adapter.project_change_count()
  end
end

local function handle_reference(env, action)
  local publish, adapter = env.services.reference_publish, env.adapter
  if action == "review_publish" then
    reference_publish_review.open(env)
  elseif action == "register_selected" then
    local result, err = publish.register_selected(adapter)
    workflow.apply(env, result, err)
  elseif action == "unregister_selected" then
    local result, err = publish.unregister_selected(adapter)
    workflow.apply(env, result, err)
  elseif action == "set_start" then
    local result, err = publish.set_selected_reference_start(adapter)
    workflow.apply(env, result, err)
  elseif action == "reset_items" then
    if workflow.confirm(env.reaper, "Treat Reference Items as New",
        "Assign new identities? Source projects will see these as new Reference items.") then
      local result, err = publish.reset_selected_reference_items(adapter)
      workflow.apply(env, result, err)
    end
  elseif action == "reset_tracks" then
    if workflow.confirm(env.reaper, "Treat Reference Tracks as New",
        "Assign new identities? Source projects will see these as new Reference tracks.") then
      local result, err = publish.reset_selected_reference_tracks(adapter)
      workflow.apply(env, result, err)
    end
  end
end

local function handle_delivery(env, action)
  local app = env.app
  if action.id == "add_delivery" then
    delivery_sync_review.open_import(env)
  elseif action.id == "sync" or action.id == "map_lanes" or action.id == "sync_other" then
    delivery_sync_review.open_update(env, action.row.id)
  elseif action.id == "retry" then
    app:request_check()
  elseif action.id == "remove" then
    if workflow.confirm(env.reaper, "Remove Subscription",
        string.format("Stop following %s? Its tracks and items stay in this project.", action.row.name)) then
      local result, err = env.services.delivery_import.remove_subscription(env.adapter, action.row.id)
      workflow.apply(env, result, err)
      app:request_check()
    end
  end
end

local function draw_row(env, row, primary)
  local ImGui, ctx, c = env.ImGui, env.ctx, env.c
  local chosen
  ImGui.Separator(ctx)
  ImGui.AlignTextToFramePadding(ctx)
  ImGui.Text(ctx, row.name)
  local width = c.status_width(row.status) + 8 + ImGui.GetFrameHeight(ctx)
  if row.action then width = width + c.button_width(row.action.label) + 8 end
  c.same_line_right(width)
  c.inline_status(row.status, row.level)
  if row.action then
    ImGui.SameLine(ctx, 0, 8)
    if c.button(row.action.label .. "##" .. row.id, primary and "primary" or nil) then
      chosen = { id = row.action.id, row = row }
    end
  end
  ImGui.SameLine(ctx, 0, 8)
  local menu = c.menu("row-menu-" .. row.id, ROW_MENU, false)
  if menu then chosen = { id = menu, row = row } end
  if row.note then env.c.small(row.note) end
  return chosen
end

local function draw_deliveries(env, cards, width)
  local ImGui, ctx, c = env.ImGui, env.ctx, env.c
  local highlighted = cards.highlight == "deliveries"
  local chosen
  if c.begin_card("master-deliveries", width, highlighted) then
    c.card_header("download", "Deliveries")
    c.same_line_right(ImGui.GetFrameHeight(ctx))
    if c.icon_button("add-delivery", "plus", "Add Delivery") then chosen = { id = "add_delivery" } end
    if #cards.rows == 0 then
      local empty = cards.deliveries_empty
      c.status(empty.status, empty.level)
      c.small(empty.note)
      if c.button(empty.action.label, highlighted and "primary" or nil) then
        chosen = { id = empty.action.id }
      end
    end
    local primary_used = false
    for _, row in ipairs(cards.rows) do
      local primary = highlighted and row.attention and not primary_used
      primary_used = primary_used or primary
      chosen = draw_row(env, row, primary) or chosen
    end
  end
  c.end_card()
  return chosen
end

function M.draw(env, state)
  local ImGui, ctx, c = env.ImGui, env.ctx, env.c
  local values = input(env, state)
  local cards = view_models.master_cards(values)
  if cards.reference and values.marker_error then cards.reference.note = values.marker_error end
  header.draw(env, state, "Master", cards.all_current and "All Up to Date" or nil)
  local width, side_by_side = c.card_width()
  local reference_action = card.draw(env, "master-reference", "film", "Reference", cards.reference,
    cards.highlight == "reference", width, REFERENCE_MENU)
  if side_by_side then ImGui.SameLine(ctx, 0, 12) end
  local delivery_action = draw_deliveries(env, cards, width)
  if reference_action then handle_reference(env, reference_action) end
  if delivery_action then handle_delivery(env, delivery_action) end
end

return M
