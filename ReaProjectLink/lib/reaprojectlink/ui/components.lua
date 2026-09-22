local icons = require("reaprojectlink.ui.icons")

-- Shared widgets. They standardize spacing and color and never contain domain
-- or REAPER mutation logic.
local M = {}

-- ReaImGui's 0.9 compatibility table predates the named ChildFlags constants;
-- BeginChild accepts the Dear ImGui bit values directly.
local CHILD_BORDER = 1
local CHILD_ALWAYS_USE_PADDING = 2
local CHILD_AUTO_RESIZE_Y = 32
local CARD_FLAGS = CHILD_BORDER | CHILD_ALWAYS_USE_PADDING | CHILD_AUTO_RESIZE_Y
local PAGE_MAX_WIDTH = 720
local FOOTER_HEIGHT = 48
local STACK_BELOW = 560
local VALUE_COLUMN = 130
local LEVEL_COLOR = { neutral = "muted", ready = "ready", warning = "warning", blocked = "blocked" }
local NOTICE_STYLE = {
  blocked = { "blocked_bg", "blocked", "cross" },
  warning = { "warning_bg", "warning", "warning" },
  ready = { "accent_bg", "text", "check" },
}

function M.create(ImGui, ctx, theme)
  local c = {}
  local cards, pages = {}, {}

  local function colors() return theme.colors end
  local function level_color(level) return colors()[LEVEL_COLOR[level] or "muted"] end
  local function visible_label(label) return (label:gsub("##.*$", "")) end

  local function styled_button(label, fill, hover, active, text, border)
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, fill)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, hover)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, active)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, text)
    ImGui.PushStyleColor(ctx, ImGui.Col_Border, border)
    local clicked = ImGui.Button(ctx, label)
    ImGui.PopStyleColor(ctx, 5)
    return clicked
  end

  -- Text ----------------------------------------------------------------------

  function c.title(text)
    ImGui.PushFont(ctx, theme.fonts.title)
    ImGui.Text(ctx, text)
    ImGui.PopFont(ctx)
  end

  function c.heading(text)
    ImGui.PushFont(ctx, theme.fonts.heading)
    ImGui.Text(ctx, text)
    ImGui.PopFont(ctx)
  end

  function c.colored(text, color)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, color)
    ImGui.TextWrapped(ctx, text)
    ImGui.PopStyleColor(ctx)
  end

  function c.muted(text) c.colored(text, colors().muted) end

  function c.small(text)
    ImGui.PushFont(ctx, theme.fonts.small)
    c.muted(text)
    ImGui.PopFont(ctx)
  end

  function c.inline_muted(text) ImGui.TextColored(ctx, colors().muted, text) end

  function c.section(text)
    ImGui.Dummy(ctx, 0, 4)
    c.small(text)
  end

  function c.key_value(label, value)
    ImGui.TextColored(ctx, colors().muted, label)
    ImGui.SameLine(ctx, VALUE_COLUMN)
    ImGui.TextWrapped(ctx, tostring(value))
  end

  function c.copy_value(id, label, value)
    ImGui.AlignTextToFramePadding(ctx)
    ImGui.TextColored(ctx, colors().muted, label)
    ImGui.SameLine(ctx, VALUE_COLUMN)
    if ImGui.SmallButton(ctx, "Copy##" .. id) then ImGui.SetClipboardText(ctx, tostring(value)) end
    ImGui.SameLine(ctx)
    ImGui.TextWrapped(ctx, tostring(value))
  end

  -- Icons and status ------------------------------------------------------------

  function c.icon(name, color, size)
    size = size or ImGui.GetTextLineHeight(ctx)
    local x, y = ImGui.GetCursorScreenPos(ctx)
    icons.draw(ImGui, ImGui.GetWindowDrawList(ctx), name, x, y, size, color or colors().text)
    ImGui.Dummy(ctx, size, size)
  end

  function c.status(text, level)
    local color = level_color(level)
    c.icon("dot", color)
    ImGui.SameLine(ctx, 0, 6)
    c.colored(text, color)
  end

  function c.inline_status(text, level)
    local color = level_color(level)
    c.icon("dot", color)
    ImGui.SameLine(ctx, 0, 6)
    ImGui.TextColored(ctx, color, text)
  end

  function c.status_width(text)
    return ImGui.GetTextLineHeight(ctx) + 6 + ImGui.CalcTextSize(ctx, text)
  end

  function c.badge(text)
    local k = colors()
    ImGui.PushFont(ctx, theme.fonts.small)
    local width, height = ImGui.CalcTextSize(ctx, text)
    local x, y = ImGui.GetCursorScreenPos(ctx)
    local draw_list = ImGui.GetWindowDrawList(ctx)
    ImGui.DrawList_AddRectFilled(draw_list, x, y, x + width + 12, y + height + 4, k.accent_bg, 4)
    ImGui.DrawList_AddText(draw_list, x + 6, y + 2, k.accent, text)
    ImGui.Dummy(ctx, width + 12, height + 4)
    ImGui.PopFont(ctx)
  end

  -- Buttons and layout helpers ---------------------------------------------------

  function c.button(label, kind)
    local k = colors()
    if kind == "primary" then
      return styled_button(label, k.accent, k.accent_hover, k.accent_active, k.on_accent, k.accent)
    elseif kind == "danger" then
      return styled_button(label, k.surface, k.blocked_bg, k.blocked_bg, k.blocked, k.blocked)
    end
    return ImGui.Button(ctx, label)
  end

  function c.disabled_button(label)
    ImGui.BeginDisabled(ctx, true)
    ImGui.Button(ctx, label)
    ImGui.EndDisabled(ctx)
  end

  function c.button_width(label)
    local padding = ImGui.GetStyleVar(ctx, ImGui.StyleVar_FramePadding)
    return ImGui.CalcTextSize(ctx, visible_label(label)) + padding * 2
  end

  function c.icon_button(id, name, tooltip)
    local size = ImGui.GetFrameHeight(ctx)
    local x, y = ImGui.GetCursorScreenPos(ctx)
    local clicked = ImGui.InvisibleButton(ctx, id, size, size)
    local hovered = ImGui.IsItemHovered(ctx)
    local draw_list = ImGui.GetWindowDrawList(ctx)
    if hovered then
      ImGui.DrawList_AddRectFilled(draw_list, x, y, x + size, y + size, colors().surface_hover, 6)
    end
    local pad = size * 0.2
    icons.draw(ImGui, draw_list, name, x + pad, y + pad, size - pad * 2,
      hovered and colors().text or colors().muted)
    if hovered and tooltip then ImGui.SetTooltip(ctx, tooltip) end
    return clicked
  end

  -- Continues the current line and moves the cursor so that `width` pixels end
  -- at the right edge; wraps to a new line when there is not enough room.
  function c.same_line_right(width)
    ImGui.SameLine(ctx)
    local available = ImGui.GetContentRegionAvail(ctx)
    if available < width then
      ImGui.NewLine(ctx)
      available = ImGui.GetContentRegionAvail(ctx)
    end
    ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx) + math.max(0, available - width))
  end

  -- Returns the card width and whether two cards fit side by side.
  function c.card_width()
    local available = ImGui.GetContentRegionAvail(ctx)
    if available < STACK_BELOW then return 0, false end
    return (available - 12) / 2, true
  end

  -- Cards ----------------------------------------------------------------------

  function c.begin_card(id, width, highlighted)
    local k = colors()
    ImGui.PushStyleColor(ctx, ImGui.Col_Border, highlighted and k.accent or k.border)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_ChildBorderSize, highlighted and 2 or 1)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 12, 12)
    local visible = ImGui.BeginChild(ctx, id, width or 0, 0, CARD_FLAGS, ImGui.WindowFlags_NoScrollbar)
    ImGui.PopStyleVar(ctx, 2)
    ImGui.PopStyleColor(ctx)
    table.insert(cards, visible)
    return visible
  end

  function c.end_card()
    if table.remove(cards) then ImGui.EndChild(ctx) end
  end

  function c.card_header(icon, title)
    c.icon(icon, colors().muted)
    ImGui.SameLine(ctx, 0, 6)
    c.heading(title)
  end

  -- Draws a "more" icon button with a popup menu. Entries are
  -- { id = ..., label = ... } or { separator = true }. Returns the chosen id.
  function c.menu(id, entries, align_right)
    if align_right ~= false then c.same_line_right(ImGui.GetFrameHeight(ctx)) end
    if c.icon_button(id .. "-open", "more", "More actions") then ImGui.OpenPopup(ctx, id) end
    local chosen
    if ImGui.BeginPopup(ctx, id) then
      for _, entry in ipairs(entries) do
        if entry.separator then
          ImGui.Separator(ctx)
        elseif ImGui.MenuItem(ctx, entry.label) then
          chosen = entry.id
        end
      end
      ImGui.EndPopup(ctx)
    end
    return chosen
  end

  -- Notices --------------------------------------------------------------------

  -- A tinted, full-width message with optional buttons. Returns the index of
  -- the clicked action.
  function c.notice(id, level, text, actions)
    local style = NOTICE_STYLE[level] or NOTICE_STYLE.ready
    local k = colors()
    ImGui.PushStyleColor(ctx, ImGui.Col_ChildBg, k[style[1]])
    ImGui.PushStyleColor(ctx, ImGui.Col_Border, k[style[1]])
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 10, 8)
    local visible = ImGui.BeginChild(ctx, id, 0, 0, CARD_FLAGS, ImGui.WindowFlags_NoScrollbar)
    ImGui.PopStyleVar(ctx)
    ImGui.PopStyleColor(ctx, 2)
    local chosen
    if visible then
      c.icon(style[3], k[style[2]])
      ImGui.SameLine(ctx, 0, 6)
      c.colored(text, k[style[2]])
      for index, label in ipairs(actions or {}) do
        if index > 1 then ImGui.SameLine(ctx) end
        if ImGui.Button(ctx, label .. "##" .. id .. "-" .. index) then chosen = index end
      end
      ImGui.EndChild(ctx)
    end
    return chosen
  end

  function c.toast(toast)
    local chosen = c.notice("toast", toast.is_error and "blocked" or "ready", toast.text,
      toast.is_error and { "Dismiss" } or nil)
    return chosen == 1
  end

  -- Selection ------------------------------------------------------------------

  -- Options are { label = ... } (returned when chosen), { header = ... }, or
  -- { separator = true }. Returns the chosen option table.
  function c.dropdown(id, preview, options)
    local chosen
    ImGui.SetNextItemWidth(ctx, -1)
    if ImGui.BeginCombo(ctx, "##" .. id, preview) then
      for index, option in ipairs(options) do
        if option.separator then
          ImGui.Separator(ctx)
        elseif option.header then
          ImGui.TextColored(ctx, colors().muted, option.header)
        elseif ImGui.Selectable(ctx, option.label .. "##" .. id .. "-" .. index, false) then
          chosen = option
        end
      end
      ImGui.EndCombo(ctx)
    end
    return chosen
  end

  -- Options are { id = ..., label = ... }. Returns the selected id.
  function c.segmented(id, options, selected)
    local chosen = selected
    local k = colors()
    for index, option in ipairs(options) do
      if index > 1 then ImGui.SameLine(ctx, 0, 4) end
      local label = option.label .. "##" .. id .. "-" .. index
      local clicked
      if option.id == selected then
        clicked = styled_button(label, k.accent_bg, k.accent_bg, k.accent_bg, k.accent, k.accent)
      else
        clicked = ImGui.Button(ctx, label)
      end
      if clicked then chosen = option.id end
    end
    return chosen
  end

  -- Review details ---------------------------------------------------------------

  function c.begin_group(id, label, detail, level, default_open)
    local flags = ImGui.TreeNodeFlags_SpanAvailWidth
    if default_open then flags = flags | ImGui.TreeNodeFlags_DefaultOpen end
    local open = ImGui.TreeNodeEx(ctx, id, label, flags)
    if detail then
      c.same_line_right(ImGui.CalcTextSize(ctx, detail))
      ImGui.TextColored(ctx, level_color(level), detail)
    end
    return open
  end

  function c.end_group() ImGui.TreePop(ctx) end

  -- Draws only visible rows; every row must be one text line high.
  function c.clipped(count, draw_row)
    local clipper = ImGui.CreateListClipper(ctx)
    ImGui.ListClipper_Begin(clipper, count)
    while ImGui.ListClipper_Step(clipper) do
      local first, last = ImGui.ListClipper_GetDisplayRange(clipper)
      for index = first + 1, last do draw_row(index) end
    end
  end

  -- Pages ----------------------------------------------------------------------

  -- A centered, width-capped scrolling region. With a footer it leaves room
  -- for c.footer below it.
  function c.begin_page(id, has_footer)
    local available = ImGui.GetContentRegionAvail(ctx)
    local width = math.min(available, PAGE_MAX_WIDTH)
    local indent = math.max(0, (available - width) / 2)
    ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx) + indent)
    ImGui.PushStyleColor(ctx, ImGui.Col_ChildBg, colors().bg)
    local visible = ImGui.BeginChild(ctx, id, width, has_footer and -FOOTER_HEIGHT or 0)
    ImGui.PopStyleColor(ctx)
    table.insert(pages, { visible = visible, indent = indent, width = width, id = id })
    return visible
  end

  function c.end_page()
    local page = table.remove(pages)
    if page.visible then ImGui.EndChild(ctx) end
    return page
  end

  function c.review_header(title, summary)
    local back = c.icon_button("page-back", "back", "Back")
    ImGui.SameLine(ctx, 0, 6)
    c.title(title)
    if summary then c.muted(summary) end
    ImGui.Dummy(ctx, 0, 4)
    return back
  end

  function c.footer(page, summary, level, label, enabled)
    ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx) + page.indent)
    ImGui.PushStyleColor(ctx, ImGui.Col_ChildBg, colors().bg)
    local visible = ImGui.BeginChild(ctx, page.id .. "-footer", page.width, 0, 0,
      ImGui.WindowFlags_NoScrollbar)
    ImGui.PopStyleColor(ctx)
    local clicked = false
    if visible then
      ImGui.Separator(ctx)
      ImGui.AlignTextToFramePadding(ctx)
      ImGui.TextColored(ctx, level_color(level), summary)
      c.same_line_right(c.button_width(label))
      if enabled then clicked = c.button(label, "primary") else c.disabled_button(label) end
      ImGui.EndChild(ctx)
    end
    return clicked
  end

  function c.stale(title, text, label)
    ImGui.Dummy(ctx, 0, 24)
    c.icon("warning", colors().warning)
    c.heading(title)
    c.muted(text)
    return c.button(label, "primary")
  end

  return c
end

return M
