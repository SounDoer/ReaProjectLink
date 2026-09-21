local M = {}

local COLORS = {
  text = 0xe7eaf0ff,
  muted = 0x9299a8ff,
  subtle = 0x687083ff,
  window = 0x0d1017ff,
  sidebar = 0x111620ff,
  surface = 0x151b26ff,
  surface_hover = 0x1c2533ff,
  surface_active = 0x233044ff,
  border = 0x293244ff,
  primary = 0x4f8ef7ff,
  primary_hover = 0x68a0ffff,
  primary_active = 0x3977d8ff,
  ready = 0x48c9a0ff,
  warning = 0xe6b35aff,
  blocked = 0xf06b78ff,
}

local function attach_font(ImGui, ctx, size)
  local font = ImGui.CreateFont("sans-serif", size)
  ImGui.Attach(ctx, font)
  return font
end

function M.create(ImGui, ctx)
  local self = {
    ImGui = ImGui,
    ctx = ctx,
    colors = COLORS,
    font_title = attach_font(ImGui, ctx, 20),
    font_heading = attach_font(ImGui, ctx, 16),
    font_body = attach_font(ImGui, ctx, 14),
    card_visibility = {},
  }

  function self:push_theme()
    local I, c = self.ImGui, self.colors
    I.PushStyleColor(ctx, I.Col_Text, c.text)
    I.PushStyleColor(ctx, I.Col_TextDisabled, c.muted)
    I.PushStyleColor(ctx, I.Col_WindowBg, c.window)
    I.PushStyleColor(ctx, I.Col_ChildBg, c.surface)
    I.PushStyleColor(ctx, I.Col_PopupBg, c.surface)
    I.PushStyleColor(ctx, I.Col_Border, c.border)
    I.PushStyleColor(ctx, I.Col_Separator, c.border)
    I.PushStyleColor(ctx, I.Col_FrameBg, c.surface_hover)
    I.PushStyleColor(ctx, I.Col_FrameBgHovered, c.surface_active)
    I.PushStyleColor(ctx, I.Col_FrameBgActive, c.surface_active)
    I.PushStyleColor(ctx, I.Col_Button, c.surface_hover)
    I.PushStyleColor(ctx, I.Col_ButtonHovered, c.surface_active)
    I.PushStyleColor(ctx, I.Col_ButtonActive, c.primary_active)
    I.PushStyleColor(ctx, I.Col_Header, c.surface_active)
    I.PushStyleColor(ctx, I.Col_HeaderHovered, 0x293750ff)
    I.PushStyleColor(ctx, I.Col_HeaderActive, 0x30415dff)
    I.PushStyleColor(ctx, I.Col_CheckMark, c.primary)
    I.PushStyleVar(ctx, I.StyleVar_WindowPadding, 0, 0)
    I.PushStyleVar(ctx, I.StyleVar_WindowRounding, 8)
    I.PushStyleVar(ctx, I.StyleVar_ChildRounding, 7)
    I.PushStyleVar(ctx, I.StyleVar_FrameRounding, 6)
    I.PushStyleVar(ctx, I.StyleVar_PopupRounding, 7)
    I.PushStyleVar(ctx, I.StyleVar_FramePadding, 10, 7)
    I.PushStyleVar(ctx, I.StyleVar_ItemSpacing, 8, 8)
    I.PushStyleVar(ctx, I.StyleVar_ItemInnerSpacing, 7, 5)
  end

  function self:pop_theme()
    self.ImGui.PopStyleVar(ctx, 8)
    self.ImGui.PopStyleColor(ctx, 17)
  end

  function self:push_font(font)
    self.ImGui.PushFont(ctx, font)
  end

  function self:pop_font()
    self.ImGui.PopFont(ctx)
  end

  function self:title(text)
    self:push_font(self.font_title)
    self.ImGui.Text(ctx, text)
    self:pop_font()
  end

  function self:heading(text)
    self:push_font(self.font_heading)
    self.ImGui.Text(ctx, text)
    self:pop_font()
  end

  function self:muted(text)
    self.ImGui.PushStyleColor(ctx, self.ImGui.Col_Text, self.colors.muted)
    self.ImGui.TextWrapped(ctx, text)
    self.ImGui.PopStyleColor(ctx)
  end

  function self:status(text, level)
    local color = self.colors.muted
    if level == "ready" then color = self.colors.ready
    elseif level == "warning" then color = self.colors.warning
    elseif level == "blocked" then color = self.colors.blocked
    elseif level == "primary" then color = self.colors.primary end
    self.ImGui.PushStyleColor(ctx, self.ImGui.Col_Text, color)
    self.ImGui.Text(ctx, "●  " .. text)
    self.ImGui.PopStyleColor(ctx)
  end

  function self:primary_button(label, width)
    local I, c = self.ImGui, self.colors
    I.PushStyleColor(ctx, I.Col_Button, c.primary)
    I.PushStyleColor(ctx, I.Col_ButtonHovered, c.primary_hover)
    I.PushStyleColor(ctx, I.Col_ButtonActive, c.primary_active)
    local clicked = I.Button(ctx, label, width or 0, 0)
    I.PopStyleColor(ctx, 3)
    return clicked
  end

  function self:nav_item(label, selected)
    local I, c = self.ImGui, self.colors
    if selected then
      I.PushStyleColor(ctx, I.Col_Button, 0x20304aff)
      I.PushStyleColor(ctx, I.Col_ButtonHovered, 0x293b59ff)
      I.PushStyleColor(ctx, I.Col_Text, 0xdce9ffff)
    else
      I.PushStyleColor(ctx, I.Col_Button, c.sidebar)
      I.PushStyleColor(ctx, I.Col_ButtonHovered, c.surface_hover)
      I.PushStyleColor(ctx, I.Col_Text, c.muted)
    end
    local clicked = I.Button(ctx, label, -1, 34)
    I.PopStyleColor(ctx, 3)
    return clicked
  end

  function self:begin_card(id, height, width)
    local I = self.ImGui
    I.PushStyleVar(ctx, I.StyleVar_WindowPadding, 16, 14)
    -- ReaImGui's 0.9 compatibility table predates the named ChildFlags
    -- constants, while BeginChild already accepts the underlying bit field.
    -- Fixed-height summary cards never own scrolling; the page content region
    -- is the single scrolling surface. Full-height workflow cards keep their
    -- own scrolling behavior.
    local window_flags = height and height > 0 and I.WindowFlags_NoScrollbar or 0
    local visible = I.BeginChild(ctx, id, width or 0, height or 0, 1, window_flags)
    I.PopStyleVar(ctx)
    table.insert(self.card_visibility, visible)
    return visible
  end

  function self:end_card()
    local visible = table.remove(self.card_visibility)
    if visible then self.ImGui.EndChild(ctx) end
  end

  function self:label_value(label, value)
    local I = self.ImGui
    I.PushStyleColor(ctx, I.Col_Text, self.colors.muted)
    I.Text(ctx, label)
    I.PopStyleColor(ctx)
    I.SameLine(ctx, 180)
    I.TextWrapped(ctx, tostring(value))
  end

  return self
end

return M
