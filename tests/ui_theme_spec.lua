local theme = require("reaprojectlink.ui.theme")

local function equal(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
  end
end

local tests = {}

function tests.palettes_share_every_token()
  local count = 0
  for key in pairs(theme.PALETTES.light) do
    count = count + 1
    assert(theme.PALETTES.dark[key], "dark palette is missing " .. key)
  end
  for key in pairs(theme.PALETTES.dark) do
    assert(theme.PALETTES.light[key], "light palette is missing " .. key)
  end
  equal(count, 14, "token count")
end

function tests.resolves_explicit_and_automatic_modes()
  equal(theme.resolve("light", nil), "light", "explicit light")
  equal(theme.resolve("dark", { 255, 255, 255 }), "dark", "explicit dark wins")
  equal(theme.resolve("auto", { 240, 240, 240 }), "light", "bright REAPER theme")
  equal(theme.resolve("auto", { 30, 30, 30 }), "dark", "dark REAPER theme")
  equal(theme.resolve("auto", nil), "dark", "unknown REAPER theme")
end

function tests.mixes_channels_and_keeps_alpha()
  equal(theme.mix(0x000000ff, 0xffffffff, 0.5), 0x808080ff, "midpoint")
  equal(theme.mix(0x102030ff, 0x102030ff, 0.3), 0x102030ff, "same color")
  equal(theme.mix(0x00000080, 0xffffffff, 1), 0xffffff80, "first alpha kept")
end

function tests.colors_add_derived_tokens()
  local colors = theme.colors("light")
  equal(colors.accent, theme.PALETTES.light.accent, "base token copied")
  assert(colors.accent_hover and colors.accent_active and colors.surface_active,
    "derived tokens exist")
  equal(theme.colors("unknown").bg, theme.PALETTES.dark.bg, "unknown mode falls back to dark")
end

function tests.stores_the_preference_globally()
  local stored = {}
  local reaper_api = {}
  function reaper_api.GetExtState(section, key) return stored[section .. "/" .. key] or "" end
  function reaper_api.SetExtState(section, key, value, persist)
    assert(persist, "preference persists across sessions")
    stored[section .. "/" .. key] = value
  end
  equal(theme.load_preference(reaper_api), "auto", "default preference")
  stored["ReaProjectLink/theme"] = "purple"
  equal(theme.load_preference(reaper_api), "auto", "invalid preference")
  theme.save_preference(reaper_api, "light")
  equal(theme.load_preference(reaper_api), "light", "saved preference")
end

function tests.reads_the_reaper_background()
  local reaper_api = {}
  function reaper_api.GetThemeColor() return -1 end
  function reaper_api.ColorFromNative() error("not called for a missing color") end
  equal(theme.reaper_background(reaper_api), nil, "missing theme color")
  function reaper_api.GetThemeColor(name)
    equal(name, "col_main_bg2", "theme color name")
    return 1234
  end
  function reaper_api.ColorFromNative(value)
    equal(value, 1234, "native color")
    return 10, 20, 30
  end
  local rgb = theme.reaper_background(reaper_api)
  equal(rgb[1] .. "," .. rgb[2] .. "," .. rgb[3], "10,20,30", "rgb")
end

local passed = 0
for name, test in pairs(tests) do
  local ok, err = pcall(test)
  if not ok then error(name .. ": " .. tostring(err)) end
  passed = passed + 1
end

return passed
