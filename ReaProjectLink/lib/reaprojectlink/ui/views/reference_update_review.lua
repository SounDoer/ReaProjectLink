local view_models = require("reaprojectlink.ui.view_models")
local workflow = require("reaprojectlink.ui.workflow")

local M = {}

-- The full check hashes Reference media, so it only runs when the user opens
-- this Review.
function M.open(env)
  local status, err = env.services.reference_subscription.check(env.adapter, env.fs)
  if not status then
    env.app:notify(err, true)
    return
  end
  env.app.checks.reference = { state = "done", latest = status.latest_revision }
  env.app.media_error = not status.available and status.video_error or nil
  env.app:open_review("reference_update", { status = status, shift_entire_project = false })
end

function M.draw(env)
  local ImGui, ctx, c, app = env.ImGui, env.ctx, env.c, env.app
  local review = app.review
  local status = review.status
  local snapshot = status.snapshot or {}
  local back = false
  if c.begin_page("reference-update", true) then
    back = c.review_header(string.format("Update Reference to r%d", status.latest_revision),
      string.format("Synchronized r%d", status.synchronized_revision))
    workflow.draw_notices(env)
    if not status.available then c.notice("reference-media", "blocked", status.video_error) end
    if status.can_shift_entire_project then
      c.section("Decision")
      local changed, value = ImGui.Checkbox(ctx,
        string.format("Shift the entire project by %.3f seconds", status.shift_seconds),
        review.shift_entire_project)
      if changed then review.shift_entire_project = value end
      c.small("The whole Reference moved. Shift your project with it to stay in sync.")
    end
    c.section("In this revision")
    c.key_value("Tracks", #(snapshot.lanes or {}))
    c.key_value("Markers", #(snapshot.markers or {}))
    c.key_value("Regions", #(snapshot.regions or {}))
    c.key_value("Alignment", status.alignment_mode == "relative" and
      "Relative to Reference Start" or "Mirror Master timeline")
  end
  local page = c.end_page()

  local pending = status.latest_revision ~= status.synchronized_revision
  local ready = status.available and pending
  local summary
  if not status.available then
    summary = view_models.blocked_summary(1, "synchronize")
  elseif pending then
    summary = string.format("Brings Reference r%d into this project", status.latest_revision)
  else
    summary = "Already up to date"
  end
  local synchronize = c.footer(page, summary, status.available and "neutral" or "blocked",
    "Synchronize", ready)

  if back then
    app:back()
  elseif synchronize then
    local result, err = env.services.reference_subscription.synchronize(env.adapter, status, {
      shift_entire_project = review.shift_entire_project,
    })
    if result then
      app:back()
      app:notify(string.format("Synchronized Reference r%d.", status.latest_revision))
      app:request_check()
    else
      app:notify(err, true)
    end
  end
end

return M
