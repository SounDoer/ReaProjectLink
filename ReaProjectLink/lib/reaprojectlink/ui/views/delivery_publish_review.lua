local view_models = require("reaprojectlink.ui.view_models")
local workflow = require("reaprojectlink.ui.workflow")

local M = {}

local function build(env, options)
  return env.services.delivery_publish.review(env.adapter, env.fs, options)
end

function M.open(env)
  local options = { publish_anyway = false }
  local review, err = build(env, options)
  if not review then
    env.app:notify(err, true)
    return
  end
  env.app:open_review("delivery_publish", { data = review, options = options })
end

local function refresh(env, options)
  local review, err = build(env, options)
  if review then
    local current = env.app.review
    current.options = options
    current.data = review
  else
    env.app:notify(err, true)
  end
end

local function item_count(data)
  local count = 0
  for _, lane in ipairs(data.lanes) do count = count + #lane.clips end
  return count
end

-- Returns true when a decision changed and the Review must be rebuilt.
local function draw_issues(env, data, options)
  local c = env.c
  local changed = false
  if data.reference_blocker then c.notice("reference-blocker", "blocked", data.reference_blocker) end
  if data.save_as_blocker then
    local choice = c.notice("save-as", "blocked",
      "This project was moved or saved under a new name. Is this the same delivery?",
      { "Continue existing", "Start new" })
    if choice then
      options.save_as_decision = choice == 1 and "continue" or "new"
      changed = true
    end
  end
  if data.has_unprocessed_fx and not options.publish_anyway then
    local choice = c.notice("unprocessed-fx", "warning",
      "Track or Take FX were found. Published audio won't include them.",
      { "Publish unprocessed media..." })
    if choice == 1 and workflow.confirm(env.reaper, "Publish unprocessed media",
        "Detected Track FX or Take FX will not be included in the published media. Continue?") then
      options.publish_anyway = true
      changed = true
    end
  elseif data.has_unprocessed_fx then
    c.notice("unprocessed-fx-accepted", "warning", "Detected FX won't be included in the published audio.")
  end
  for _, lane in ipairs(data.lanes) do
    if lane.fx_blocked then
      c.notice("lane-fx-" .. lane.lane_id, "blocked", lane.display_name .. " has Track FX.")
    end
    for index, row in ipairs(lane.clips) do
      for blocker_index, blocker in ipairs(row.blockers) do
        local id = string.format("clip-%s-%d-%d", lane.lane_id, index, blocker_index)
        local text = string.format("%s: %s", row.display_name or "Unnamed item", blocker)
        if c.notice(id, "blocked", text, { "Select item" }) == 1 and row.clip.item_ref then
          env.adapter.select_items({ row.clip.item_ref })
        end
      end
    end
  end
  return changed
end

local function draw_declaration(env, data, options)
  if data.synchronized_reference_revision == 0 then return false end
  local c = env.c
  c.section("Checked against Reference")
  local choices = view_models.reference_declaration_options(
    data.synchronized_reference_revision, data.last_declared_reference_revision
  )
  local chosen = c.segmented("declared-reference", choices, data.reviewed_reference_revision)
  if chosen ~= data.reviewed_reference_revision then
    options.declared_reference_revision = chosen
    return true
  end
  return false
end

local function draw_details(env, data)
  local c, ImGui, ctx, colors = env.c, env.ImGui, env.ctx, env.theme.colors
  c.section("Items")
  for _, lane in ipairs(data.lanes) do
    local blocked = 0
    for _, row in ipairs(lane.clips) do
      if #row.blockers > 0 then blocked = blocked + 1 end
    end
    local detail = view_models.count(#lane.clips, "item")
    if blocked > 0 then detail = blocked .. " blocked · " .. detail end
    if c.begin_group("lane-" .. lane.lane_id, lane.display_name, detail,
        blocked > 0 and "blocked" or "neutral", blocked > 0 or lane.fx_blocked) then
      c.clipped(#lane.clips, function(index)
        local row = lane.clips[index]
        ImGui.TextColored(ctx, #row.blockers > 0 and colors.blocked or colors.text,
          row.display_name or "Unnamed item")
      end)
      c.end_group()
    end
  end
end

function M.draw(env)
  local c, app = env.c, env.app
  local review = app.review
  local data = review.data
  local options = {}
  for key, value in pairs(review.options) do options[key] = value end
  local stale = workflow.is_stale(env, data)
  local back, changed, refresh_clicked = false, false, false
  if c.begin_page("delivery-publish", true) then
    back = c.review_header(string.format("Publish Delivery r%d", data.delivery_revision),
      view_models.count(#data.lanes, "track") .. " · " .. view_models.count(item_count(data), "item"))
    workflow.draw_notices(env)
    if stale then
      refresh_clicked = c.stale("Project changed",
        "The project was edited after this review was made.", "Refresh review")
    else
      changed = draw_issues(env, data, options)
      changed = draw_declaration(env, data, options) or changed
      draw_details(env, data)
    end
  end
  local page = c.end_page()

  local summary, level = string.format("Publishes %s as Delivery r%d",
    view_models.count(item_count(data), "item"), data.delivery_revision), "neutral"
  if stale then
    summary = "Refresh the review to continue"
  elseif data.blocker_count > 0 then
    summary, level = view_models.blocked_summary(data.blocker_count, "publish"), "blocked"
  end
  local publish = c.footer(page, summary, level, "Publish", not stale and data.blocker_count == 0)

  if back then
    app:back()
  elseif refresh_clicked then
    refresh(env, review.options)
  elseif changed then
    refresh(env, options)
  elseif publish then
    local result, err = env.services.delivery_publish.publish(data, env.adapter, env.fs, workflow.metadata())
    if result then
      local message, is_error = workflow.publish_message("Delivery", result.delivery_revision, result)
      app:back()
      app:notify(message, is_error)
    else
      app:notify(err, true)
      workflow.inspect_lock(env, data.package_root)
    end
  end
end

return M
