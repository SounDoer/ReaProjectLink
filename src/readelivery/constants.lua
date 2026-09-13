local M = {}

M.EXTENSION_NAME = "ReaDelivery"
M.PROJECT_SCHEMA_VERSION = "1"

M.PROJECT_KEYS = {
  schema_version = "schema_version",
  project_mode = "project_mode",
  source_project_id = "source_project_id",
  delivery_set_id = "delivery_set_id",
  publish_revision = "publish_revision",
  picture_id = "picture_id",
  picture_revision = "picture_revision",
  picture_manifest_path = "picture_manifest_path",
  synchronized_picture_revision = "synchronized_picture_revision",
  reviewed_picture_revision = "reviewed_picture_revision",
  picture_start_samples = "picture_start_samples",
}

M.TRACK_KEYS = {
  lane_id = "P_EXT:ReaDelivery_lane_id",
}

M.ITEM_KEYS = {
  clip_id = "P_EXT:ReaDelivery_clip_id",
  picture_id = "P_EXT:ReaDelivery_picture_id",
}

M.PROJECT_MODES = {
  source = "source",
  mix = "mix",
}

return M
