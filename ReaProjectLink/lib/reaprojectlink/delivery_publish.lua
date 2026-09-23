local constants = require("reaprojectlink.constants")
local delivery_manifest = require("reaprojectlink.delivery_manifest")
local manifest_validation = require("reaprojectlink.manifest_validation")
local default_delivery_writer = require("reaprojectlink.delivery_writer")
local delivery_publish_plan = require("reaprojectlink.delivery_publish_plan")
local project_guard = require("reaprojectlink.project_guard")
local delivery_review = require("reaprojectlink.delivery_review")
local project_service = require("reaprojectlink.project_service")
local manifest_file = require("reaprojectlink.manifest_file")
local paths = require("reaprojectlink.paths")

local M = {}

local function count_phrase(n, noun)
  return string.format("%d %s", n, n == 1 and noun or noun .. "s")
end

-- What the last published Delivery revision contained that is no longer
-- registered now (D089). Comparison is by stable Lane identity, so
-- re-registering the same Track under its existing Lane identity is not a
-- removal, and a Save As "new" review (which starts from an empty published
-- baseline) never reports one either.
local function removed_content(previous, current)
  local removed = { lanes = 0, total = 0 }
  if not previous then return removed end
  local current_lane_ids = {}
  for _, lane in ipairs(current.lanes) do current_lane_ids[lane.lane_id] = true end
  for _, lane in ipairs(previous.lanes or {}) do
    if not current_lane_ids[lane.laneId] then removed.lanes = removed.lanes + 1 end
  end
  removed.total = removed.lanes
  return removed
end

local function removed_blocker_text(removed, base_revision)
  return string.format("%s from Delivery r%d %s no longer registered.",
    count_phrase(removed.lanes, "Lane"), base_revision, removed.total == 1 and "is" or "are")
end

local function load_previous(fs, package_root)
  local pointer_path = fs.join(package_root, "delivery.json")
  if not fs.exists(pointer_path) then return nil, nil, nil end

  local pointer, pointer_error = manifest_file.read(fs, pointer_path, "delivery.json", 1)
  if not pointer then return nil, nil, pointer_error end
  local valid, validation_error = manifest_validation.delivery_pointer(pointer)
  if not valid then return nil, nil, validation_error end
  local snapshot, snapshot_error = manifest_file.read(
    fs,
    fs.join(package_root, pointer.manifest),
    "published Delivery Manifest",
    1
  )
  if not snapshot then return nil, nil, snapshot_error end
  valid, validation_error = manifest_validation.delivery_snapshot(snapshot, {
    source_project_id = pointer.sourceProjectId,
    delivery_id = pointer.deliveryId,
    revision = pointer.latestDeliveryRevision,
  })
  if not valid then return nil, nil, validation_error end
  return pointer, snapshot
end

function M.create(dependencies)
  dependencies = dependencies or {}
  local writer = dependencies.delivery_writer or default_delivery_writer
  local service = {}

  function service.review(adapter, fs, options)
    options = options or {}
    local path = adapter.project_path()
    local directory, project_name = paths.project_parts(path)
    if not directory then return nil, "Save the REAPER project before Publish Review." end

    local derived_package_root = fs.join(directory, "_ReaProjectLink", project_name)
    local stored_source_id = adapter.get_project_value(constants.PROJECT_KEYS.project_id)
    local stored_identity_path = adapter.get_project_value(
      constants.PROJECT_KEYS.project_identity_path
    )
    local stored_package_root = adapter.get_project_value(
      constants.PROJECT_KEYS.package_root
    )
    local path_changed = stored_source_id and stored_source_id ~= "" and
      stored_identity_path and stored_identity_path ~= "" and
      not paths.same(stored_identity_path, path)
    local starts_new = path_changed and options.save_as_decision == "new"
    local package_root = path_changed and not starts_new and
      stored_package_root and stored_package_root ~= "" and stored_package_root or
      derived_package_root
    local pointer, previous, load_error = load_previous(fs, package_root)
    if load_error then return nil, load_error end

    if starts_new and pointer then
      return nil, "The new Source package destination already contains a published delivery."
    end

    local stored_set_id = adapter.get_project_value(constants.PROJECT_KEYS.delivery_id)
    if pointer and stored_source_id and stored_source_id ~= "" and
        pointer.sourceProjectId ~= stored_source_id then
      return nil, "Published package belongs to a different Source Project ID."
    end
    if pointer and stored_set_id and stored_set_id ~= "" and
        pointer.deliveryId ~= stored_set_id then
      return nil, "Published package belongs to a different Delivery ID."
    end

    local current, scan_error = project_service.scan(adapter)
    if not current then return nil, scan_error end
    if starts_new then
      for _, lane in ipairs(current.lanes) do
        for _, clip in ipairs(lane.clips) do clip.clip_id = "" end
      end
      pointer, previous = nil, nil
    end
    local reference_start_samples = tonumber(adapter.get_project_value(
      constants.PROJECT_KEYS.reference_start_samples
    ))
    local reference_start_sample_rate = tonumber(adapter.get_project_value(
      constants.PROJECT_KEYS.reference_start_sample_rate
    )) or current.sample_rate
    if reference_start_samples then
      local local_reference_start = math.floor(
        reference_start_samples / reference_start_sample_rate * current.sample_rate + 0.5
      )
      for _, lane in ipairs(current.lanes) do
        for _, clip in ipairs(lane.clips) do
          if clip.start_offset_samples then
            clip.start_offset_samples = clip.start_offset_samples - local_reference_start
          end
        end
      end
    end
    local review = delivery_review.build({
      current = current,
      previous_snapshot = previous,
      publish_anyway = options.publish_anyway,
    }, fs)

    review.package_root = package_root
    review.project_name = project_name
    review.project_file = path
    review.base_revision = pointer and pointer.latestDeliveryRevision or 0
    review.previous_snapshot = previous
    review.removed = removed_content(previous, review.current)
    if review.removed.total > 0 and not options.allow_removals then
      review.removed_blocker = removed_blocker_text(review.removed, review.base_revision)
      review.blocker_count = review.blocker_count + 1
    end
    review.source_project_id = not starts_new and
      (stored_source_id or (pointer and pointer.sourceProjectId)) or nil
    review.delivery_id = not starts_new and
      (stored_set_id or (pointer and pointer.deliveryId)) or nil
    review.save_as_decision = options.save_as_decision
    review.path_changed = path_changed
    if path_changed and not options.save_as_decision then
      review.save_as_blocker =
        "This Source Project path changed. Choose Continue Existing Project or Start New Project."
      review.blocker_count = review.blocker_count + 1
    end
    review.reference_id = adapter.get_project_value(constants.PROJECT_KEYS.reference_id)
    review.synchronized_reference_revision = tonumber(adapter.get_project_value(
      constants.PROJECT_KEYS.synchronized_reference_revision
    )) or 0
    -- The stored "reviewed" value now holds the revision declared at the last
    -- Publish (D086); it seeds the second choice in the Review.
    review.last_declared_reference_revision = tonumber(adapter.get_project_value(
      constants.PROJECT_KEYS.reviewed_reference_revision
    )) or 0
    review.reviewed_reference_revision = options.declared_reference_revision or
      review.synchronized_reference_revision
    if not review.reference_id or review.reference_id == "" or
        review.synchronized_reference_revision == 0 or not reference_start_samples then
      review.blocker_count = review.blocker_count + 1
      review.reference_blocker = "Synchronize a Reference revision before publishing."
    end
    return project_guard.bind(review, adapter, true)
  end

  function service.publish(review, adapter, fs, metadata)
    local current, context_error = project_guard.check(review, adapter, "Publish Review")
    if not current then return nil, context_error end
    metadata = metadata or {}
    if review.blocker_count ~= 0 then
      return nil, "Publish Review still has blockers or unresolved decisions."
    end

    local plan = delivery_publish_plan.build({
      source_project_id = review.source_project_id,
      delivery_id = review.delivery_id,
      source_project_name = review.project_name,
      source_project_file = review.project_file,
      published_at = metadata.published_at,
      published_by = metadata.published_by,
      reference_id = review.reference_id,
      reviewed_reference_revision = review.reviewed_reference_revision,
      sample_rate = review.current.sample_rate,
      previous_snapshot = review.previous_snapshot,
      current = review.current,
    }, adapter.new_id)

    adapter.begin_undo("Assign ReaProjectLink Delivery identities")
    adapter.set_project_value(constants.PROJECT_KEYS.project_id, plan.source_project_id)
    adapter.set_project_value(constants.PROJECT_KEYS.delivery_id, plan.delivery_id)
    adapter.set_project_value(
      constants.PROJECT_KEYS.project_identity_path,
      review.project_file
    )
    adapter.set_project_value(
      constants.PROJECT_KEYS.package_root,
      review.package_root
    )
    for _, assignment in ipairs(plan.assignments) do
      adapter.set_item_clip_id(assignment.item_ref, assignment.clip_id)
    end
    adapter.mark_project_dirty()
    adapter.end_undo("Assign ReaProjectLink Delivery identities")
    local saved, save_error = adapter.save_project()
    if not saved then return nil, save_error or "Could not save the Source Project." end

    local snapshot, pointer = delivery_manifest.build(plan.snapshot_input)
    local result, publish_error = writer.publish({
      package_root = review.package_root,
      expected_revision = review.base_revision,
      transaction_id = adapter.new_id(),
      snapshot = snapshot,
      pointer = pointer,
      media = plan.media,
      lock_metadata = metadata.lock_metadata,
    }, fs)
    if not result then return nil, publish_error end

    adapter.set_project_value(
      constants.PROJECT_KEYS.delivery_revision,
      tostring(result.delivery_revision)
    )
    adapter.set_project_value(
      constants.PROJECT_KEYS.reviewed_reference_revision,
      tostring(review.reviewed_reference_revision)
    )
    adapter.mark_project_dirty()
    local revision_saved, revision_save_error = adapter.save_project()
    if not revision_saved then
      result.project_save_error = revision_save_error or
        "Delivery was published, but its revision could not be saved to the Source Project."
    end
    return result
  end

  return service
end

return M
