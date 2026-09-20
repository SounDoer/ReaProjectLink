local source = debug.getinfo(1, "S").source:sub(2)
local tests_dir = assert(source:match("^(.*)[/\\]"))
local root = assert(tests_dir:match("^(.*)[/\\]tests$"))
local mode = os.getenv("REAPROJECTLINK_UI_SMOKE_TYPE") or ""

reaper.SetProjExtState(0, "ReaProjectLink", "project_type", mode)
dofile(root .. "/scripts/ReaProjectLink.lua")
