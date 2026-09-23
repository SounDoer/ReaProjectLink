local view_models = require("reaprojectlink.ui.view_models")
local workflow = require("reaprojectlink.ui.workflow")

local M = {}

local function build(env, options)
  return env.services.reference_publish.review(env.adapter, env.fs, options)
end

function M.open(env)
  local options = { publish_anyway = false }
  local review, err = build(env, options)
  if not review then
    env.app:notify(err, true)
    return
  end
  env.app:open_review("reference_publish", { data = review, options = options })
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

local function draw_issues(env, data, options)
  local c = env.c
  local changed = false
  if data.save_as_blocker then
    local choice = c.notice("save-as", "blocked",
      "This project was moved or saved under a new name. Is this the same Reference?",
      { "Continue Existing", "Start New" })
    if choice then
      options.save_as_decision = choice == 1 and "continue" or "new"
      changed = true
    end
  end
  if data.removed_blocker and not options.allow_removals then
    local choice = c.notice("removed", "blocked", data.removed_blocker, { "Publish Without Them..." })
    if choice == 1 and workflow.confirm(env.reaper, "Publish Without Them",
        "Source Projects will see them as removed, and registering again gives them new identities. Continue?") then
      options.allow_removals = true
      changed = true
    end
  elseif data.removed and data.removed.total > 0 then
    c.notice("removed-accepted", "warning", "Removed content won't be part of this Reference.")
  end
  for index, blocker in ipairs(data.blockers or {}) do
    if blocker ~= data.save_as_blocker and blocker ~= data.removed_blocker then
      c.notice("blocker-" .. index, "blocked", blocker)
    end
  end
  if data.unchanged and not options.publish_anyway then
    local choice = c.notice("unchanged", "warning",
      string.format("This Reference is identical to Reference r%d.", data.base_revision),
      { "Publish Anyway..." })
    if choice == 1 and workflow.confirm(env.reaper, "Publish Unchanged Reference",
        "Publish a new unchanged Reference revision? Source projects will still need to synchronize it.") then
      options.publish_anyway = true
      changed = true
    end
  end
  return changed
end

local function draw_details(env, data)
  local c = env.c
  c.section("Contents")
  if c.begin_group("reference-tracks", "Tracks", view_models.count(#data.lanes, "track"), "neutral", false) then
    for _, lane in ipairs(data.lanes) do
      c.key_value(lane.displayName, view_models.count(#(lane.items or {}), "item"))
    end
    c.end_group()
  end
  if c.begin_group("reference-markers", "Markers", view_models.count(#data.markers, "marker"), "neutral", false) then
    for _, marker in ipairs(data.markers) do c.muted(marker.name ~= "" and marker.name or "Unnamed Marker") end
    c.end_group()
  end
  if c.begin_group("reference-regions", "Regions", view_models.count(#data.regions, "region"), "neutral", false) then
    for _, region in ipairs(data.regions) do c.muted(region.name ~= "" and region.name or "Unnamed Region") end
    c.end_group()
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
  workflow.draw_notices(env)
  if c.begin_page("reference-publish", true) then
    back = c.review_header(string.format("Publish Reference r%d", data.reference_revision),
      view_models.count(#data.lanes, "track") .. " · " ..
        view_models.count(#data.markers + #data.regions, "marker"))
    if stale then
      refresh_clicked = c.stale("Review Out of Date",
        "The project was edited after this review was made.", "Refresh Review")
    else
      changed = draw_issues(env, data, options)
      draw_details(env, data)
    end
  end
  local page = c.end_page()

  local issues = data.blocker_count + (data.unchanged_blocker and 1 or 0)
  local summary, level = string.format("Publishes Reference r%d", data.reference_revision), "neutral"
  if stale then
    summary = "Refresh the review to continue"
  elseif issues > 0 then
    summary, level = view_models.blocked_summary(issues, "publish"), "blocked"
  end
  local publish = c.footer(page, summary, level, "Publish", not stale and issues == 0)

  if back then
    app:back()
  elseif refresh_clicked then
    refresh(env, review.options)
  elseif changed then
    refresh(env, options)
  elseif publish then
    local result, err = env.services.reference_publish.publish(data, env.adapter, env.fs, workflow.metadata())
    if result then
      local message, is_error = workflow.publish_message("Reference", result.reference_revision, result)
      app:back()
      app:notify(message, is_error)
      app:request_check()
    else
      app:notify(err, true)
      workflow.inspect_lock(env, data.package_root)
    end
  end
end

return M
