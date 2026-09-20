local M = {}

M.EXTENSION_NAME = "ReaDelivery"
M.PROJECT_SCHEMA_VERSION = "1"

M.PROJECT_KEYS = {
  schema_version = "schema_version",
  project_mode = "project_mode",
  source_project_id = "source_project_id",
  source_identity_project_path = "source_identity_project_path",
  source_package_root = "source_package_root",
  delivery_set_id = "delivery_set_id",
  publish_revision = "publish_revision",
  picture_id = "picture_id",
  picture_revision = "picture_revision",
  picture_manifest_path = "picture_manifest_path",
  synchronized_picture_revision = "synchronized_picture_revision",
  reviewed_picture_revision = "reviewed_picture_revision",
  picture_start_samples = "picture_start_samples",
  picture_start_sample_rate = "picture_start_sample_rate",
  picture_alignment_mode = "picture_alignment_mode",
  picture_timeline_entries = "picture_timeline_entries",
  source_subscriptions = "source_subscriptions",
}

M.TRACK_KEYS = {
  lane_id = "P_EXT:ReaDelivery_lane_id",
  bound_lane_id = "P_EXT:ReaDelivery_bound_lane_id",
  picture_lane_id = "P_EXT:ReaDelivery_picture_lane_id",
  picture_set_id = "P_EXT:ReaDelivery_picture_set_id",
}

M.ITEM_KEYS = {
  clip_id = "P_EXT:ReaDelivery_clip_id",
  picture_id = "P_EXT:ReaDelivery_picture_id",
  picture_item_id = "P_EXT:ReaDelivery_picture_item_id",
  source_project_id = "P_EXT:ReaDelivery_source_project_id",
  instance_id = "P_EXT:ReaDelivery_instance_id",
  accepted_media_revision = "P_EXT:ReaDelivery_accepted_media_revision",
  handled_publish_revision = "P_EXT:ReaDelivery_handled_publish_revision",
  picture_revision = "P_EXT:ReaDelivery_picture_revision",
}

M.PROJECT_MODES = {
  source = "source",
  mix = "mix",
}

return M
