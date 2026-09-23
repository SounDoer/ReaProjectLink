-- Draws one card view model from ui/view_models.lua. Returns the id of the
-- chosen card action or menu entry.
local M = {}

-- Rows are plain { label, value } pairs (ui/view_models.lua).
local function draw_row(c, row)
  local label = row.label or row[1]
  local value = row.value or row[2]
  c.value_row(label, value)
end

-- Draws the two `selection_actions` (Register Selected / Unregister Selected)
-- as secondary buttons on one line, stacking if they don't fit. Returns the
-- chosen action id.
local function draw_selection_actions(env, id, actions)
  local ImGui, ctx, c = env.ImGui, env.ctx, env.c
  local chosen
  local widths = {}
  local total = 0
  for index, action in ipairs(actions) do
    widths[index] = c.button_width(action.label)
    total = total + widths[index]
    if index > 1 then total = total + 8 end
  end
  local available = ImGui.GetContentRegionAvail(ctx)
  local stacked = available < total
  for index, action in ipairs(actions) do
    if index > 1 then
      if stacked then ImGui.NewLine(ctx) else ImGui.SameLine(ctx, 0, 8) end
    end
    if c.button(action.label .. "##" .. id .. "-" .. action.id) then chosen = action.id end
  end
  return chosen
end

function M.draw(env, id, icon, title, card, highlighted, width, menu_entries)
  local c = env.c
  local chosen
  if c.begin_card(id, width, highlighted) then
    c.card_header(icon, title)
    if menu_entries then chosen = c.menu(id .. "-menu", menu_entries) end
    c.status(card.status, card.level)
    for _, row in ipairs(card.rows or {}) do
      draw_row(c, row)
    end
    if card.note then c.small(card.note) end
    if card.selection_note then c.small(card.selection_note) end
    if card.selection_actions then
      chosen = draw_selection_actions(env, id, card.selection_actions) or chosen
    end
    if card.action and c.button(card.action.label .. "##" .. id, highlighted and "primary" or nil) then
      chosen = card.action.id
    end
  end
  c.end_card()
  return chosen
end

return M
