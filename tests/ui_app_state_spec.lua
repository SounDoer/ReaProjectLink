local app_state = require("reaprojectlink.ui.app_state")

local function equal(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
  end
end

local now = 100
local function clock() return now end

local tests = {}

function tests.starts_on_the_main_panel()
  local app = app_state.new(clock)
  equal(app.view, "main", "view")
  equal(app.review, nil, "review")
  equal(app.checks.reference.state, "idle", "reference check")
  equal(app.moved_items_change_count, -1, "moved-item tracking")
end

function tests.opens_and_leaves_reviews_and_settings()
  local app = app_state.new(clock)
  app:open_review("delivery_publish", { data = 1 })
  equal(app.view, "review", "review view")
  equal(app.review.kind, "delivery_publish", "review kind")
  equal(app.review.data, 1, "review fields")
  app:back()
  equal(app.view, "main", "back to main")
  equal(app.review, nil, "review cleared")
  app:open_settings()
  equal(app.view, "settings", "settings view")
  app:back()
  equal(app.view, "main", "settings closed")
end

function tests.success_toasts_expire_and_errors_stay()
  now = 100
  local app = app_state.new(clock)
  app:notify("Saved")
  equal(app:visible_toast().text, "Saved", "visible toast")
  now = 104
  equal(app:visible_toast(), nil, "success toast expired")
  app:notify("Broken", true)
  now = 500
  equal(app:visible_toast().is_error, true, "error toast stays")
  app:dismiss_toast()
  equal(app:visible_toast(), nil, "dismissed")
end

function tests.checks_run_one_frame_after_the_request()
  local app = app_state.new(clock)
  app:request_check()
  equal(app.checks.reference.state, "checking", "reference marked checking")
  equal(app:check_due(), false, "first frame shows Checking")
  equal(app:check_due(), true, "second frame runs the check")
  equal(app:check_due(), false, "check runs once")
end

function tests.a_new_check_keeps_the_last_known_results()
  local app = app_state.new(clock)
  app.checks.reference = { state = "done", latest = 5 }
  app.checks.deliveries = { a = { state = "done", latest = 3, reviewed_reference = 8 } }
  app:request_check()
  equal(app.checks.reference.latest, 5, "reference latest kept")
  equal(app.checks.deliveries.a.state, "checking", "delivery marked checking")
  equal(app.checks.deliveries.a.latest, 3, "delivery latest kept")
  equal(app.checks.deliveries.a.reviewed_reference, 8, "reviewed Reference kept")
end

function tests.reports_seconds_since_the_last_check()
  now = 100
  local app = app_state.new(clock)
  equal(app:seconds_since_check(), nil, "never checked")
  app:finish_check()
  now = 130.7
  equal(app:seconds_since_check(), 30, "whole seconds")
end

function tests.reset_clears_transient_state()
  local app = app_state.new(clock)
  app:open_review("reference_update", {})
  app:notify("Broken", true)
  app.lock = { info = {} }
  app.media_error = "Media File Not Found"
  app.moved_items_change_count = 9
  app:request_check()
  app:reset()
  equal(app.view, "main", "view reset")
  equal(app.review, nil, "review reset")
  equal(app.toast, nil, "toast reset")
  equal(app.lock, nil, "lock reset")
  equal(app.media_error, nil, "media error reset")
  equal(app.check_phase, nil, "check phase reset")
  equal(app.moved_items_change_count, -1, "moved-item tracking reset")
end

local passed = 0
for name, test in pairs(tests) do
  local ok, err = pcall(test)
  if not ok then error(name .. ": " .. tostring(err)) end
  passed = passed + 1
end

return passed
