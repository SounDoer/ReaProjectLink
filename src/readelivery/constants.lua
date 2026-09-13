local M = {}

M.EXTENSION_NAME = "ReaDelivery"
M.PROJECT_SCHEMA_VERSION = "1"

M.PROJECT_KEYS = {
  schema_version = "schema_version",
  project_mode = "project_mode",
  source_project_id = "source_project_id",
}

M.TRACK_KEYS = {
  lane_id = "P_EXT:ReaDelivery_lane_id",
}

M.ITEM_KEYS = {
  clip_id = "P_EXT:ReaDelivery_clip_id",
}

M.PROJECT_MODES = {
  source = "source",
  mix = "mix",
}

return M
