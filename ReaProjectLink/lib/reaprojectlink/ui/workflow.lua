-- Helpers shared by views. `env` is the table built in ui/app.lua.
local M = {}

function M.metadata()
  local user = os.getenv("USERNAME") or os.getenv("USER") or "unknown"
  local now = os.date("!%Y-%m-%dT%H:%M:%SZ")
  return {
    published_at = now,
    published_by = user,
    lock_metadata = {
      user = user,
      machine = os.getenv("COMPUTERNAME") or "unknown",
      started_at = now,
    },
  }
end

function M.choose_json(reaper_api, title)
  local ok, path = reaper_api.GetUserFileNameForRead("", title, "json")
  return ok and path or nil
end

function M.confirm(reaper_api, title, text)
  return reaper_api.ShowMessageBox(text, title, 1) == 1
end

function M.is_stale(env, data)
  return data.project_change_count ~= nil and
    data.project_change_count ~= env.adapter.project_change_count()
end

-- Shows a toast for a service result. `success` is a string or a function of
-- the result.
function M.report(env, result, err, success)
  if result then
    env.app:notify(type(success) == "function" and success(result) or success)
  else
    env.app:notify(err, true)
  end
  return result
end

-- Like M.report, but silent on success. Used for routine, selection-based
-- operations where a toast would just be noise; errors still notify.
function M.apply(env, result, err)
  if not result then env.app:notify(err, true) end
  return result
end

function M.publish_message(noun, revision, result)
  local message = string.format("Published %s r%d.", noun, revision)
  if result.project_save_error then message = message .. " " .. result.project_save_error end
  if result.lock_release_error then
    message = message .. " Publish lock cleanup failed: " .. result.lock_release_error
  end
  return message, result.project_save_error ~= nil or result.lock_release_error ~= nil
end

function M.inspect_lock(env, package_root)
  local info = env.fs.read_lock(package_root)
  env.app.lock = info and { info = info, package_root = package_root } or nil
end

function M.unlock(env)
  local app = env.app
  if not M.confirm(env.reaper, "Unlock Publishing",
      "Unlock publishing only if no other user or computer is publishing to this package.") then
    return
  end
  local removed, err = env.fs.remove_lock(app.lock.package_root, app.lock.info.token)
  if removed then
    app.lock = nil
    app:notify("Publishing unlocked. Review again before publishing.")
  else
    app:notify(err, true)
  end
end

function M.choose_reference(env)
  local path = M.choose_json(env.reaper, "Select Published reference.json")
  if not path then return end
  local result, err = env.services.reference_subscription.subscribe(env.adapter, env.fs, path)
  if result then
    env.app:notify("Connected to the Reference.")
    env.app:request_check()
  else
    env.app:notify(err, true)
  end
end

-- Unsaved-project and lock banners, then the toast. Views call this directly
-- under their header.
function M.draw_notices(env, state)
  local c, app = env.c, env.app
  if state and state.path == "" then
    c.notice("unsaved", "blocked", "Save this project in REAPER to use ReaProjectLink.")
  end
  if app.lock then
    local lock = app.lock.info
    local text = string.format("Publishing is locked by %s on %s since %s.",
      lock.user or "an unknown user", lock.machine or "an unknown computer",
      lock.started_at or "an unknown time")
    if c.notice("publish-lock", "blocked", text, { "Unlock Publishing..." }) == 1 then
      M.unlock(env)
    end
  end
  local toast = app:visible_toast()
  if toast and c.toast(toast) then app:dismiss_toast() end
end

return M
