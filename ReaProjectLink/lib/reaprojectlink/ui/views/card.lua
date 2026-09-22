-- Draws one card view model from ui/view_models.lua. Returns the id of the
-- chosen card action or menu entry.
local M = {}

function M.draw(env, id, icon, title, card, highlighted, width, menu_entries)
  local c = env.c
  local chosen
  if c.begin_card(id, width, highlighted) then
    c.card_header(icon, title)
    if menu_entries then chosen = c.menu(id .. "-menu", menu_entries) end
    c.status(card.status, card.level)
    for _, row in ipairs(card.rows or {}) do c.key_value(row[1], row[2]) end
    if card.note then c.small(card.note) end
    if card.action and c.button(card.action.label .. "##" .. id, highlighted and "primary" or nil) then
      chosen = card.action.id
    end
  end
  c.end_card()
  return chosen
end

return M
