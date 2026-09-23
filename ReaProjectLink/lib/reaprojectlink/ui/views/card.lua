-- Draws one card view model from ui/view_models.lua. Returns the id of the
-- chosen card action or menu entry.
local M = {}

-- Draws `card.register_actions` (if any) as secondary buttons on one line
-- when they all fit, or stacked one per line otherwise.
local function draw_register_actions(env, id, actions)
  local ImGui, ctx, c = env.ImGui, env.ctx, env.c
  local chosen
  local total = 0
  for index, action in ipairs(actions) do
    total = total + c.button_width(action.label)
    if index > 1 then total = total + 8 end
  end
  local fits = total <= ImGui.GetContentRegionAvail(ctx)
  for index, action in ipairs(actions) do
    if index > 1 and fits then ImGui.SameLine(ctx, 0, 8) end
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
    for _, row in ipairs(card.rows or {}) do c.key_value(row[1], row[2]) end
    if card.note then c.small(card.note) end
    if card.register_actions and #card.register_actions > 0 then
      chosen = draw_register_actions(env, id, card.register_actions) or chosen
    end
    if card.action and c.button(card.action.label .. "##" .. id, highlighted and "primary" or nil) then
      chosen = card.action.id
    end
  end
  c.end_card()
  return chosen
end

return M
