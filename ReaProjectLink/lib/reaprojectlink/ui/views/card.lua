-- Draws one card view model from ui/view_models.lua. Returns the id of the
-- chosen card action or menu entry.
local M = {}

-- Rows may be a plain { label, value } pair, or a table with named fields
-- carrying `register`/`unregister` action ids and tooltips (ui/view_models.lua).
local function draw_row(c, id, index, row)
  local label = row.label or row[1]
  local value = row.value or row[2]
  local actions
  if row.register or row.unregister then
    actions = {}
    if row.register then
      table.insert(actions, { id = row.register, icon = "plus", tooltip = row.register_tooltip })
    end
    if row.unregister then
      table.insert(actions, { id = row.unregister, icon = "minus", tooltip = row.unregister_tooltip })
    end
  end
  return c.value_row(id .. "-row-" .. index, label, value, actions)
end

function M.draw(env, id, icon, title, card, highlighted, width, menu_entries)
  local c = env.c
  local chosen
  if c.begin_card(id, width, highlighted) then
    c.card_header(icon, title)
    if menu_entries then chosen = c.menu(id .. "-menu", menu_entries) end
    c.status(card.status, card.level)
    for index, row in ipairs(card.rows or {}) do
      chosen = draw_row(c, id, index, row) or chosen
    end
    if card.note then c.small(card.note) end
    if card.action and c.button(card.action.label .. "##" .. id, highlighted and "primary" or nil) then
      chosen = card.action.id
    end
  end
  c.end_card()
  return chosen
end

return M
