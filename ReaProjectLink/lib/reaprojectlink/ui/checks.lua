local constants = require("reaprojectlink.constants")
local json = require("reaprojectlink.json")

local M = {}

function M.subscriptions(adapter)
  local stored = adapter.get_project_value(constants.PROJECT_KEYS.delivery_subscriptions)
  if not stored or stored == "" then return {} end
  local ok, value = pcall(json.decode, stored)
  return ok and value or {}
end

function M.run_source(env)
  local status, err, kind = env.services.reference_subscription.peek(env.adapter, env.fs)
  if status then
    env.app.checks.reference = { state = "done", latest = status.latest_revision }
    -- A successful peek means the media is reachable again; the next Review
    -- open re-runs the full media check.
    env.app.media_error = nil
  elseif kind == "unsubscribed" then
    env.app.checks.reference = { state = "idle" }
  else
    env.app.checks.reference = { state = kind, error = err }
  end
end

function M.run_master(env)
  local results = {}
  for _, entry in ipairs(M.subscriptions(env.adapter)) do
    local status, err, kind = env.services.delivery_update.peek(env.fs, entry)
    if status then
      results[entry.sourceProjectId] = {
        state = "done",
        latest = status.latest_revision,
        reviewed_reference = status.reviewed_reference_revision,
      }
    else
      results[entry.sourceProjectId] = { state = kind or "invalid", error = err }
    end
  end
  env.app.checks.deliveries = results

  local revision = tonumber(env.adapter.get_project_value(
    constants.PROJECT_KEYS.reference_revision
  )) or 0
  if revision <= 0 then
    env.app.checks.reference = { state = "idle" }
  else
    local root = env.adapter.get_project_value(constants.PROJECT_KEYS.package_root)
    if root and root ~= "" then
      local present = env.fs.exists(env.fs.join(root, "reference.json"))
      env.app.checks.reference = { state = present and "done" or "missing" }
    end
  end
end

return M
