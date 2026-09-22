local function equal(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
  end
end

-- Later tasks append their modules here so that every UI file is at least
-- loaded (syntax and require errors) by the core suite.
local MODULES = {
  "reaprojectlink.ui.theme",
  "reaprojectlink.ui.icons",
  "reaprojectlink.ui.components",
}

local tests = {}

function tests.every_ui_module_loads()
  for _, name in ipairs(MODULES) do
    assert(type(require(name)) == "table", name .. " returns a module table")
  end
end

function tests.every_icon_draws_primitives()
  local icons = require("reaprojectlink.ui.icons")
  local calls = 0
  local ImGui = setmetatable({}, {
    __index = function() return function() calls = calls + 1 end end,
  })
  for _, name in ipairs(icons.NAMES) do
    calls = 0
    equal(icons.draw(ImGui, "draw-list", name, 0, 0, 16, 0xffffffff), true, name .. " is known")
    assert(calls > 0, name .. " draws at least one primitive")
  end
  equal(icons.draw(ImGui, "draw-list", "missing", 0, 0, 16, 0xffffffff), false, "unknown icon")
end

local passed = 0
for name, test in pairs(tests) do
  local ok, err = pcall(test)
  if not ok then error(name .. ": " .. tostring(err)) end
  passed = passed + 1
end

return passed
