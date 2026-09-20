local M = {}

function M.bind(value, adapter, track_project_changes)
  if adapter.project_token then value.project_token = adapter.project_token() end
  if track_project_changes and adapter.project_change_count then
    value.project_change_count = adapter.project_change_count()
  end
  return value
end

function M.check(value, adapter, label)
  label = label or "Review"
  if value.project_token and adapter.project_token and
      value.project_token ~= adapter.project_token() then
    return nil, label .. " belongs to a different REAPER project. Refresh it first."
  end
  if value.project_change_count and adapter.project_change_count and
      value.project_change_count ~= adapter.project_change_count() then
    return nil, label .. " is stale because the REAPER project changed. Refresh it first."
  end
  return true
end

return M
