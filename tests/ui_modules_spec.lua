local function equal(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
  end
end

-- Later tasks append their modules here so that every UI file is at least
-- loaded (syntax and require errors) by the core suite.
local MODULES = {
  "reaprojectlink.ui.theme",
  "reaprojectlink.ui.icons",
  "reaprojectlink.ui.components",
  "reaprojectlink.ui.workflow",
  "reaprojectlink.ui.checks",
  "reaprojectlink.ui.views.card",
  "reaprojectlink.ui.views.header",
}

local tests = {}

function tests.every_ui_module_loads()
  for _, name in ipairs(MODULES) do
    assert(type(require(name)) == "table", name .. " returns a module table")
  end
end

function tests.every_icon_draws_primitives()
  local icons = require("reaprojectlink.ui.icons")
  local calls = 0
  local ImGui = setmetatable({}, {
    __index = function() return function() calls = calls + 1 end end,
  })
  for _, name in ipairs(icons.NAMES) do
    calls = 0
    equal(icons.draw(ImGui, "draw-list", name, 0, 0, 16, 0xffffffff), true, name .. " is known")
    assert(calls > 0, name .. " draws at least one primitive")
  end
  equal(icons.draw(ImGui, "draw-list", "missing", 0, 0, 16, 0xffffffff), false, "unknown icon")
end

function tests.workflow_formats_publish_results()
  local workflow = require("reaprojectlink.ui.workflow")
  local message, is_error = workflow.publish_message("Delivery", 13, {})
  equal(message, "Published Delivery r13.", "plain message")
  equal(is_error, false, "plain result")
  message, is_error = workflow.publish_message("Reference", 2, {
    project_save_error = "Save failed.", lock_release_error = "Lock stuck.",
  })
  equal(message, "Published Reference r2. Save failed. Publish lock cleanup failed: Lock stuck.",
    "follow-up errors")
  equal(is_error, true, "follow-up errors are errors")
end

function tests.workflow_detects_stale_reviews()
  local workflow = require("reaprojectlink.ui.workflow")
  local env = { adapter = { project_change_count = function() return 5 end } }
  equal(workflow.is_stale(env, { project_change_count = 4 }), true, "changed project")
  equal(workflow.is_stale(env, { project_change_count = 5 }), false, "unchanged project")
  equal(workflow.is_stale(env, {}), false, "untracked review")
end

function tests.checks_store_pointer_results()
  local checks = require("reaprojectlink.ui.checks")
  local app = require("reaprojectlink.ui.app_state").new(function() return 0 end)
  local env = {
    app = app,
    fs = {},
    adapter = {
      get_project_value = function()
        return '[{"sourceProjectId":"a","pointerPath":"A"},{"sourceProjectId":"b","pointerPath":"B"}]'
      end,
    },
    services = {
      reference_subscription = {
        peek = function() return nil, "Couldn't reach shared storage.", "unreachable" end,
      },
      delivery_update = {
        peek = function(_, entry)
          if entry.sourceProjectId == "a" then
            return { latest_revision = 4, reviewed_reference_revision = 8 }
          end
          return nil, "bad", "invalid"
        end,
      },
    },
  }
  checks.run_source(env)
  equal(app.checks.reference.state, "unreachable", "reference failure kind")
  checks.run_master(env)
  equal(app.checks.deliveries.a.latest, 4, "delivery latest")
  equal(app.checks.deliveries.a.reviewed_reference, 8, "delivery reviewed Reference")
  equal(app.checks.deliveries.b.state, "invalid", "delivery failure kind")
  equal(app.checks.deliveries.b.error, "bad", "delivery failure message")
end

local passed = 0
for name, test in pairs(tests) do
  local ok, err = pcall(test)
  if not ok then error(name .. ": " .. tostring(err)) end
  passed = passed + 1
end

return passed
