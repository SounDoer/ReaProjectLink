local M = {}

M.PALETTES = {
  light = {
    bg = 0xf3f4f6ff, surface = 0xffffffff, surface_hover = 0xeef0f3ff,
    border = 0xdadde2ff, text = 0x1d2025ff, muted = 0x5f6670ff,
    accent = 0x2f6fe0ff, on_accent = 0xffffffff, accent_bg = 0xe4edfcff,
    ready = 0x1f8a63ff, warning = 0xa86a0cff, warning_bg = 0xfdf1dcff,
    blocked = 0xc93c46ff, blocked_bg = 0xfbe5e6ff,
  },
  dark = {
    bg = 0x16181cff, surface = 0x1f2227ff, surface_hover = 0x272b31ff,
    border = 0x30343cff, text = 0xe6e8ebff, muted = 0x9aa0a8ff,
    accent = 0x4c8dffff, on_accent = 0x0b1220ff, accent_bg = 0x1c2a44ff,
    ready = 0x3fbf8fff, warning = 0xe0a84aff, warning_bg = 0x3a2f1cff,
    blocked = 0xeb5f68ff, blocked_bg = 0x3b2224ff,
  },
}

M.PREFERENCES = { "auto", "light", "dark" }
M.EXT_SECTION = "ReaProjectLink"
M.EXT_KEY = "theme"

local function channels(color)
  return (color >> 24) & 0xff, (color >> 16) & 0xff, (color >> 8) & 0xff, color & 0xff
end

-- Blends RGB toward `b`; alpha always comes from `a`.
function M.mix(a, b, t)
  local ar, ag, ab, aa = channels(a)
  local br, bg, bb = channels(b)
  local function lerp(x, y) return math.floor(x + (y - x) * t + 0.5) end
  return (lerp(ar, br) << 24) | (lerp(ag, bg) << 16) | (lerp(ab, bb) << 8) | aa
end

function M.luminance(r, g, b)
  return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255
end

function M.resolve(preference, background)
  if preference == "light" or preference == "dark" then return preference end
  if background and M.luminance(background[1], background[2], background[3]) >= 0.5 then
    return "light"
  end
  return "dark"
end

function M.colors(mode)
  local base = M.PALETTES[mode] or M.PALETTES.dark
  local colors = {}
  for key, value in pairs(base) do colors[key] = value end
  colors.accent_hover = M.mix(base.accent, base.text, 0.15)
  colors.accent_active = M.mix(base.accent, base.bg, 0.15)
  colors.surface_active = M.mix(base.surface_hover, base.text, 0.08)
  return colors
end

function M.load_preference(reaper_api)
  local value = reaper_api.GetExtState(M.EXT_SECTION, M.EXT_KEY)
  for _, name in ipairs(M.PREFERENCES) do
    if name == value then return value end
  end
  return "auto"
end

function M.save_preference(reaper_api, value)
  reaper_api.SetExtState(M.EXT_SECTION, M.EXT_KEY, value, true)
end

function M.reaper_background(reaper_api)
  if not reaper_api.GetThemeColor then return nil end
  local native = reaper_api.GetThemeColor("col_main_bg2", 0)
  if not native or native < 0 then return nil end
  local r, g, b = reaper_api.ColorFromNative(native)
  return { r, g, b }
end

function M.create(ImGui, ctx, reaper_api)
  local function font(size, bold)
    local value = ImGui.CreateFont("sans-serif", size, bold and ImGui.FontFlags_Bold or nil)
    ImGui.Attach(ctx, value)
    return value
  end

  local self = {
    fonts = {
      title = font(16, true),
      heading = font(14, true),
      body = font(13),
      small = font(12),
    },
    preference = M.load_preference(reaper_api),
    mode = "dark",
  }
  self.colors = M.colors(self.mode)

  function self:refresh()
    local mode = M.resolve(self.preference, M.reaper_background(reaper_api))
    if mode ~= self.mode then
      self.mode = mode
      self.colors = M.colors(mode)
    end
  end

  function self:set_preference(value)
    self.preference = value
    M.save_preference(reaper_api, value)
    self:refresh()
  end

  -- Used by the UI smoke test: changes the mode without touching ExtState.
  function self:use(value)
    self.preference = value
    self:refresh()
  end

  local pushed_colors, pushed_vars = 0, 0

  function self:push()
    local c = self.colors
    local colors = {
      { ImGui.Col_Text, c.text }, { ImGui.Col_TextDisabled, c.muted },
      { ImGui.Col_WindowBg, c.bg }, { ImGui.Col_ChildBg, c.surface },
      { ImGui.Col_PopupBg, c.surface }, { ImGui.Col_Border, c.border },
      { ImGui.Col_Separator, c.border }, { ImGui.Col_FrameBg, c.surface_hover },
      { ImGui.Col_FrameBgHovered, c.surface_active }, { ImGui.Col_FrameBgActive, c.surface_active },
      { ImGui.Col_Button, c.surface }, { ImGui.Col_ButtonHovered, c.surface_hover },
      { ImGui.Col_ButtonActive, c.surface_active }, { ImGui.Col_Header, c.surface_hover },
      { ImGui.Col_HeaderHovered, c.surface_hover }, { ImGui.Col_HeaderActive, c.surface_active },
      { ImGui.Col_CheckMark, c.accent }, { ImGui.Col_TitleBgActive, c.surface },
    }
    for _, pair in ipairs(colors) do ImGui.PushStyleColor(ctx, pair[1], pair[2]) end
    local vars = {
      { ImGui.StyleVar_WindowPadding, 12, 12 }, { ImGui.StyleVar_FramePadding, 10, 5 },
      { ImGui.StyleVar_ItemSpacing, 8, 8 }, { ImGui.StyleVar_ItemInnerSpacing, 6, 4 },
      { ImGui.StyleVar_WindowRounding, 6 }, { ImGui.StyleVar_ChildRounding, 6 },
      { ImGui.StyleVar_FrameRounding, 6 }, { ImGui.StyleVar_PopupRounding, 6 },
      { ImGui.StyleVar_FrameBorderSize, 1 }, { ImGui.StyleVar_ChildBorderSize, 1 },
      { ImGui.StyleVar_PopupBorderSize, 1 },
    }
    for _, var in ipairs(vars) do ImGui.PushStyleVar(ctx, var[1], var[2], var[3]) end
    pushed_colors, pushed_vars = #colors, #vars
  end

  function self:pop()
    ImGui.PopStyleVar(ctx, pushed_vars)
    ImGui.PopStyleColor(ctx, pushed_colors)
  end

  return self
end

return M
