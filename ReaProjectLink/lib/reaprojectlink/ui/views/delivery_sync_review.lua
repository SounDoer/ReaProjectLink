local view_models = require("reaprojectlink.ui.view_models")
local workflow = require("reaprojectlink.ui.workflow")

local M = {}

local PARENTS = {
  { id = "top", label = "Top level" },
  { id = "selected", label = "Selected folder track" },
}

function M.open_import(env)
  local path = workflow.choose_json(env.reaper, "Select Source delivery.json")
  if not path then return end
  local review, err = env.services.delivery_import.review(env.adapter, env.fs, path)
  if not review then
    env.app:notify(err, true)
    return
  end
  env.app:open_review("delivery_import", {
    data = review, mappings = {}, row_errors = {}, allow_reference = false,
  })
end

-- On failure the current Review, if any, stays open.
function M.open_update(env, source_project_id, target_revision)
  local review, err = env.services.delivery_update.review(
    env.adapter, env.fs, source_project_id, target_revision
  )
  if not review then
    env.app:notify(err, true)
    return
  end
  env.app:open_review("delivery_update", {
    data = review, mappings = {}, rebindings = {}, row_errors = {},
    allow_reference = false, target_input = review.target_revision,
  })
end

-- Returns "Missing track" instead of crashing/misleading when a mapped or
-- re-bound track was deleted after the Review was built.
local function track_name(env, track_ref)
  if env.adapter.valid_track and not env.adapter.valid_track(track_ref) then
    return "Missing track"
  end
  return env.adapter.track_name(track_ref)
end

local function draw_parent_choice(env, review)
  local ImGui, ctx, c = env.ImGui, env.ctx, env.c
  ImGui.AlignTextToFramePadding(ctx)
  c.inline_muted("New tracks go under")
  ImGui.SameLine(ctx)
  local current = review.parent and "selected" or "top"
  local chosen = c.segmented("parent", PARENTS, current)
  if chosen ~= current then
    if chosen == "selected" then
      local selected = env.adapter.selected_tracks()
      if #selected == 1 then
        review.parent, review.parent_error = selected[1], nil
      else
        review.parent_error = "Select exactly one folder track in REAPER first."
      end
    elseif chosen == "top" then
      review.parent, review.parent_error = nil, nil
    end
  end
  if review.parent_error then c.notice("parent-error", "warning", review.parent_error) end
end

local function draw_mapping_table(env, lanes, review, default_kind)
  local ImGui, ctx, c, colors = env.ImGui, env.ctx, env.c, env.theme.colors
  c.section("Lanes")
  draw_parent_choice(env, review)
  local column = ImGui.GetContentRegionAvail(ctx) * 0.45
  for _, lane in ipairs(lanes) do
    ImGui.Separator(ctx)
    ImGui.AlignTextToFramePadding(ctx)
    ImGui.Text(ctx, lane.display_name)
    ImGui.SameLine(ctx, 0, 6)
    c.inline_muted(tostring(#lane.clips))
    ImGui.SameLine(ctx, column)
    local mapping = review.mappings[lane.lane_id]
    local chosen = c.dropdown("lane-" .. lane.lane_id,
      view_models.lane_mapping_label(mapping, default_kind, function(ref) return track_name(env, ref) end),
      view_models.lane_mapping_options(lane))
    if chosen then
      local next_mapping, err = view_models.mapping_from_option(chosen, env.adapter.selected_tracks())
      if next_mapping then
        review.mappings[lane.lane_id] = next_mapping
        review.row_errors[lane.lane_id] = nil
      else
        review.row_errors[lane.lane_id] = err
      end
    end
    if lane.orphaned then c.small("Its target track was deleted. Map it again to restore its items.") end
    if review.row_errors[lane.lane_id] then c.colored(review.row_errors[lane.lane_id], colors.warning) end
  end
end

local function collect_mappings(lanes, review, default_kind)
  local mappings = {}
  for _, lane in ipairs(lanes) do
    mappings[lane.lane_id] = review.mappings[lane.lane_id] or { kind = default_kind }
  end
  return view_models.with_parent(mappings, review.parent)
end

local function draw_reference_issue(env, data, review, verb)
  local c = env.c
  if data.reference_error then c.notice("reference-error", "blocked", data.reference_error) end
  if not data.reference_warning then return end
  if review.allow_reference then
    c.notice("reference-warning", "warning",
      "Made against a different Reference revision. Continuing anyway.")
  elseif c.notice("reference-warning", "warning",
      "This delivery was made against a different Reference revision.", { verb .. " anyway" }) == 1 then
    review.allow_reference = true
  end
end

local function draw_clip_issue(env, id, lane_name, clip)
  if clip.blocked then
    env.c.notice(id, "blocked", string.format("%s: %s", lane_name, clip.error))
  end
end

local function draw_import(env, review)
  local c, app = env.c, env.app
  local data = review.data
  local back = false
  workflow.draw_notices(env)
  if c.begin_page("delivery-import", true) then
    back = c.review_header("Add " .. data.snapshot.sourceProjectName,
      string.format("Delivery r%d · made against Reference r%d",
        data.pointer.latestDeliveryRevision, data.snapshot.reference.reviewedRevision))
    draw_reference_issue(env, data, review, "Import")
    for lane_index, lane in ipairs(data.lanes) do
      for clip_index, clip in ipairs(lane.clips) do
        draw_clip_issue(env, "clip-" .. lane_index .. "-" .. clip_index, lane.display_name, clip)
      end
    end
    draw_mapping_table(env, data.lanes, review, "create")
  end
  local page = c.end_page()

  local ready = data.blocker_count == 0 and (not data.reference_warning or review.allow_reference)
  local summary, level = view_models.mapping_summary(data.lanes, review.mappings, "create"), "neutral"
  if data.blocker_count > 0 then
    summary, level = view_models.blocked_summary(data.blocker_count, "import"), "blocked"
  end
  local import = c.footer(page, summary, level, "Import", ready)

  if back then
    app:back()
  elseif import then
    local result, err = env.services.delivery_import.apply(data, env.adapter, {
      mappings = collect_mappings(data.lanes, review, "create"),
      allow_reference_revision_mismatch = review.allow_reference,
    })
    if result then
      app:back()
      app:notify(string.format("Imported %s on %s.",
        view_models.count(result.created_items, "item"),
        view_models.count(result.created_tracks, "new track")))
      app:request_check()
    else
      app:notify(err, true)
    end
  end
end

local function draw_target(env, review)
  local ImGui, ctx, c = env.ImGui, env.ctx, env.c
  c.section("Revision")
  ImGui.SetNextItemWidth(ctx, 120)
  local changed, value = ImGui.InputInt(ctx, "##target-revision", review.target_input)
  if changed then review.target_input = value end
  ImGui.SameLine(ctx)
  local load = c.button("Load")
  c.small(string.format("Latest is r%d", review.data.latest_revision))
  return load
end

local function draw_bound_lanes(env, review)
  local ImGui, ctx, c = env.ImGui, env.ctx, env.c
  local lanes = review.data.bound_lanes
  if #lanes == 0 then return end
  c.section("Mapped lanes")
  local column = ImGui.GetContentRegionAvail(ctx) * 0.45
  for _, lane in ipairs(lanes) do
    ImGui.Separator(ctx)
    ImGui.AlignTextToFramePadding(ctx)
    ImGui.Text(ctx, lane.display_name)
    ImGui.SameLine(ctx, column)
    local rebound = review.rebindings[lane.lane_id]
    local preview = rebound and track_name(env, rebound) or lane.track_name
    local chosen = c.dropdown("bound-" .. lane.lane_id, preview, {
      { id = "current", label = "Keep " .. lane.track_name },
      { id = "selected", label = "Selected track" },
    })
    if chosen and chosen.id == "current" then
      review.rebindings[lane.lane_id] = nil
      review.row_errors[lane.lane_id] = nil
    elseif chosen then
      local mapping, err = view_models.mapping_from_option(chosen, env.adapter.selected_tracks())
      review.rebindings[lane.lane_id] = mapping and mapping.track_ref or rebound
      review.row_errors[lane.lane_id] = err
    end
    if review.row_errors[lane.lane_id] then
      c.colored(review.row_errors[lane.lane_id], env.theme.colors.warning)
    end
  end
end

local function draw_update(env, review)
  local c, app = env.c, env.app
  local data = review.data
  local back, load = false, false
  workflow.draw_notices(env)
  if c.begin_page("delivery-update", true) then
    back = c.review_header(string.format("Sync %s to r%d",
      data.target_snapshot.sourceProjectName, data.target_revision),
      string.format("Replaces %s with %s",
        view_models.count(data.replacement_count, "item"),
        view_models.count(data.source_item_count, "item")))
    draw_reference_issue(env, data, review, "Sync")
    for index, clip in ipairs(data.additions) do
      draw_clip_issue(env, "addition-" .. index, clip.lane_display_name, clip)
    end
    for lane_index, lane in ipairs(data.unmapped_lanes) do
      for clip_index, clip in ipairs(lane.clips) do
        draw_clip_issue(env, "unmapped-" .. lane_index .. "-" .. clip_index, lane.display_name, clip)
      end
    end
    load = draw_target(env, review)
    if #data.unmapped_lanes > 0 then draw_mapping_table(env, data.unmapped_lanes, review, "create") end
    draw_bound_lanes(env, review)
  end
  local page = c.end_page()

  local ready = data.blocker_count == 0 and (not data.reference_warning or review.allow_reference) and
    (data.pending_count > 0 or next(review.rebindings) ~= nil)
  local summary, level = string.format("Syncs Delivery r%d", data.target_revision), "neutral"
  if data.blocker_count > 0 then
    summary, level = view_models.blocked_summary(data.blocker_count, "sync"), "blocked"
  elseif data.pending_count == 0 and next(review.rebindings) == nil then
    summary = "Nothing to sync"
  end
  local sync = c.footer(page, summary, level, "Sync", ready)

  if back then
    app:back()
  elseif load then
    M.open_update(env, data.source_project_id, review.target_input)
  elseif sync then
    local result, err = env.services.delivery_update.apply(data, env.adapter, {
      lane_mappings = collect_mappings(data.unmapped_lanes, review, "create"),
      lane_rebindings = review.rebindings,
      allow_reference_revision_mismatch = review.allow_reference,
    })
    if result then
      app:back()
      app:notify(string.format("Synced Delivery r%d: replaced %s with %s.", data.target_revision,
        view_models.count(result.deleted_items, "item"), view_models.count(result.new_items, "item")))
      app:request_check()
    else
      app:notify(err, true)
    end
  end
end

function M.draw(env)
  local review = env.app.review
  if review.kind == "delivery_import" then draw_import(env, review) else draw_update(env, review) end
end

return M
