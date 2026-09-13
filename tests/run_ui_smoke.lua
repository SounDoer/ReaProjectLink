local source = debug.getinfo(1, "S").source:sub(2)
local tests_dir = assert(source:match("^(.*)[/\\]"))
local root = assert(tests_dir:match("^(.*)[/\\]tests$"))
local mode = os.getenv("READELIVERY_UI_SMOKE_MODE") or ""

reaper.SetProjExtState(0, "ReaDelivery", "project_mode", mode)
dofile(root .. "/scripts/ReaDelivery.lua")
