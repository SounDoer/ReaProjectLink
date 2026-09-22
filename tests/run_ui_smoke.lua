local source = debug.getinfo(1, "S").source:sub(2)
local tests_dir = assert(source:match("^(.*)[/\\]"))
local root = assert(tests_dir:match("^(.*)[/\\]tests$"))

-- Read by ReaProjectLink.lua only when REAPROJECTLINK_UI_SMOKE_RESULT is set.
REAPROJECTLINK_SMOKE_SCENARIOS = dofile(root .. "/tests/ui_smoke_scenarios.lua")
dofile(root .. "/ReaProjectLink/ReaProjectLink.lua")
