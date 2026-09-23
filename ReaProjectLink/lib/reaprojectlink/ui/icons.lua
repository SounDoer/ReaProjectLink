-- Icons are drawn with DrawList primitives so the package needs no icon font.
local M = {}

M.NAMES = {
  "more", "gear", "dot", "back", "plus", "minus", "check", "cross", "warning", "film", "upload", "download",
}

-- Line segments in unit coordinates: { x1, y1, x2, y2 }.
local SEGMENTS = {
  back = { { 0.8, 0.5, 0.2, 0.5 }, { 0.2, 0.5, 0.45, 0.25 }, { 0.2, 0.5, 0.45, 0.75 } },
  plus = { { 0.5, 0.2, 0.5, 0.8 }, { 0.2, 0.5, 0.8, 0.5 } },
  minus = { { 0.2, 0.5, 0.8, 0.5 } },
  check = { { 0.2, 0.55, 0.42, 0.75 }, { 0.42, 0.75, 0.8, 0.28 } },
  cross = { { 0.25, 0.25, 0.75, 0.75 }, { 0.75, 0.25, 0.25, 0.75 } },
  warning = {
    { 0.5, 0.12, 0.9, 0.85 }, { 0.9, 0.85, 0.1, 0.85 }, { 0.1, 0.85, 0.5, 0.12 },
    { 0.5, 0.4, 0.5, 0.6 },
  },
  film = {
    { 0.15, 0.25, 0.85, 0.25 }, { 0.85, 0.25, 0.85, 0.75 }, { 0.85, 0.75, 0.15, 0.75 },
    { 0.15, 0.75, 0.15, 0.25 }, { 0.35, 0.25, 0.35, 0.75 }, { 0.65, 0.25, 0.65, 0.75 },
  },
  upload = {
    { 0.5, 0.7, 0.5, 0.15 }, { 0.5, 0.15, 0.28, 0.37 }, { 0.5, 0.15, 0.72, 0.37 },
    { 0.2, 0.85, 0.8, 0.85 },
  },
  download = {
    { 0.5, 0.15, 0.5, 0.7 }, { 0.5, 0.7, 0.28, 0.48 }, { 0.5, 0.7, 0.72, 0.48 },
    { 0.2, 0.85, 0.8, 0.85 },
  },
}

function M.draw(ImGui, draw_list, name, x, y, size, color)
  local thickness = math.max(1, size / 12)
  local segments = SEGMENTS[name]
  if segments then
    for _, s in ipairs(segments) do
      ImGui.DrawList_AddLine(draw_list, x + s[1] * size, y + s[2] * size,
        x + s[3] * size, y + s[4] * size, color, thickness)
    end
    return true
  end
  local cx, cy = x + size / 2, y + size / 2
  if name == "more" then
    for _, offset in ipairs({ 0.2, 0.5, 0.8 }) do
      ImGui.DrawList_AddCircleFilled(draw_list, x + offset * size, cy, math.max(1, size * 0.08), color)
    end
  elseif name == "dot" then
    ImGui.DrawList_AddCircleFilled(draw_list, cx, cy, size * 0.2, color)
  elseif name == "gear" then
    ImGui.DrawList_AddCircle(draw_list, cx, cy, size * 0.28, color, 0, thickness)
    ImGui.DrawList_AddCircle(draw_list, cx, cy, size * 0.1, color, 0, thickness)
    for tooth = 0, 7 do
      local angle = tooth * math.pi / 4
      ImGui.DrawList_AddLine(draw_list,
        cx + math.cos(angle) * size * 0.28, cy + math.sin(angle) * size * 0.28,
        cx + math.cos(angle) * size * 0.42, cy + math.sin(angle) * size * 0.42,
        color, thickness * 1.5)
    end
  else
    return false
  end
  return true
end

return M
