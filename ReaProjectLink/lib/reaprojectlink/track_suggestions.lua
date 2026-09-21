local M = {}

-- A Master Track is only suggested for a Lane when one display name contains the
-- other, so "Vocal A" matches both "Vocal" and "Vocal A Print" while unrelated
-- or unnamed Tracks stay out of the mapping table.
local function related(track_name, lane_name)
  if track_name == "" or lane_name == "" then return false end
  return track_name:find(lane_name, 1, true) ~= nil or
    lane_name:find(track_name, 1, true) ~= nil
end

function M.for_lane(adapter, tracks, lane_display_name)
  local lane_name = (lane_display_name or ""):lower()
  local suggestions = {}
  for _, track in ipairs(tracks) do
    local display_name = adapter.track_name(track)
    if related(display_name:lower(), lane_name) then
      table.insert(suggestions, {
        track_ref = track,
        track_guid = adapter.track_guid(track),
        display_name = display_name,
      })
    end
  end
  table.sort(suggestions, function(left, right)
    return left.display_name < right.display_name
  end)
  return suggestions
end

return M
