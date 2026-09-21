local M = {}

M.EXTENSION_NAME = "ReaProjectLink"
M.PROJECT_SCHEMA_VERSION = "1"

M.PROJECT_KEYS = {
  schema_version = "schema_version",
  project_type = "project_type",
  project_id = "project_id",
  project_identity_path = "project_identity_path",
  package_root = "package_root",
  delivery_id = "delivery_id",
  delivery_revision = "delivery_revision",
  reference_id = "reference_id",
  reference_master_project_id = "reference_master_project_id",
  reference_revision = "reference_revision",
  reference_manifest_path = "reference_manifest_path",
  synchronized_reference_revision = "synchronized_reference_revision",
  reviewed_reference_revision = "reviewed_reference_revision",
  reference_start_samples = "reference_start_samples",
  reference_start_sample_rate = "reference_start_sample_rate",
  reference_alignment_mode = "reference_alignment_mode",
  reference_timeline_entries = "reference_timeline_entries",
  delivery_subscriptions = "delivery_subscriptions",
}

M.TRACK_KEYS = {
  lane_id = "P_EXT:ReaProjectLink_lane_id",
  bound_lane_id = "P_EXT:ReaProjectLink_bound_lane_id",
  reference_lane_id = "P_EXT:ReaProjectLink_reference_lane_id",
  reference_id = "P_EXT:ReaProjectLink_reference_id",
}

M.ITEM_KEYS = {
  clip_id = "P_EXT:ReaProjectLink_clip_id",
  reference_id = "P_EXT:ReaProjectLink_reference_id",
  reference_item_id = "P_EXT:ReaProjectLink_reference_item_id",
  source_project_id = "P_EXT:ReaProjectLink_source_project_id",
  lane_id = "P_EXT:ReaProjectLink_lane_id",
  reference_revision = "P_EXT:ReaProjectLink_reference_revision",
}

M.PROJECT_TYPES = {
  source = "source",
  master = "master",
}

return M
