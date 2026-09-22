-- One UI frame is rendered per scenario (see tests/run_ui_smoke.lua). Review
-- fixtures contain only the fields the views read; `fields` builds a fresh
-- table per scenario because views mutate Review state.
local reviews = {
  reference_update = {
    kind = "reference_update",
    fields = function()
      return {
        shift_entire_project = false,
        status = {
          latest_revision = 5, synchronized_revision = 4, available = false,
          video_error = "Media File Not Found", can_shift_entire_project = true,
          shift_seconds = 1.5, alignment_mode = "mirror",
          snapshot = { lanes = { { displayName = "Picture" } }, markers = {}, regions = {} },
        },
      }
    end,
  },
  delivery_publish = {
    kind = "delivery_publish",
    fields = function()
      return {
        options = {},
        data = {
          delivery_revision = 13, blocker_count = 2, has_unprocessed_fx = true,
          synchronized_reference_revision = 5, last_declared_reference_revision = 4,
          reviewed_reference_revision = 5, save_as_blocker = "moved", package_root = "C:/smoke",
          lanes = {
            { lane_id = "lane-1", display_name = "SFX_Impacts", fx_blocked = true, clips = {
              { display_name = "Whoosh_03", status = "Blocked", blockers = { "Media File Not Found" }, clip = {} },
              { display_name = "Hit_01", status = "Included", blockers = {}, clip = {} },
            } },
          },
        },
      }
    end,
  },
  reference_publish = {
    kind = "reference_publish",
    fields = function()
      return {
        options = {},
        data = {
          reference_revision = 9, base_revision = 8, blocker_count = 1,
          blockers = { "Reference video is missing: C:/smoke/picture.mov" },
          unchanged = true, unchanged_blocker = "identical", package_root = "C:/smoke",
          lanes = { { displayName = "Picture", items = { {} } } },
          markers = { { name = "FFOP" } }, regions = { { name = "" } },
        },
      }
    end,
  },
  delivery_import = {
    kind = "delivery_import",
    fields = function()
      return {
        mappings = {}, row_errors = {}, allow_reference = false,
        data = {
          pointer = { latestDeliveryRevision = 15 },
          snapshot = { sourceProjectName = "Dialogue", reference = { reviewedRevision = 8 } },
          blocker_count = 1, reference_warning = true,
          lanes = {
            { lane_id = "a", display_name = "DX_Main", clips = { {}, { blocked = true, error = "Managed WAV hash mismatch." } },
              suggestions = { { display_name = "DX Main", track_ref = false } } },
            { lane_id = "b", display_name = "DX_Walla", clips = { {} }, suggestions = {} },
          },
        },
      }
    end,
  },
  delivery_update = {
    kind = "delivery_update",
    fields = function()
      return {
        mappings = {}, rebindings = {}, row_errors = {}, allow_reference = false, target_input = 15,
        data = {
          source_project_id = "source-1", target_revision = 15, latest_revision = 15,
          target_snapshot = { sourceProjectName = "Dialogue" },
          replacement_count = 12, source_item_count = 14, pending_count = 26,
          blocker_count = 0, reference_warning = false, additions = {},
          unmapped_lanes = {
            { lane_id = "c", display_name = "DX_Radio", orphaned = true, clips = { {} }, suggestions = {} },
          },
          bound_lanes = { { lane_id = "a", display_name = "DX_Main", track_name = "DX Main" } },
        },
      }
    end,
  },
}

local views = {
  { project_type = "" },
  { project_type = "source" },
  { project_type = "source", view = "settings" },
  { project_type = "source", review = reviews.reference_update },
  { project_type = "source", review = reviews.delivery_publish },
  { project_type = "master" },
  { project_type = "master", view = "settings" },
  { project_type = "master", review = reviews.reference_publish },
  { project_type = "master", review = reviews.delivery_import },
  { project_type = "master", review = reviews.delivery_update },
}

local scenarios = {}
for _, theme in ipairs({ "light", "dark" }) do
  for _, width in ipairs({ 320, 1040 }) do
    for _, view in ipairs(views) do
      table.insert(scenarios, {
        theme = theme, width = width,
        project_type = view.project_type, view = view.view, review = view.review,
      })
    end
  end
end

return scenarios
