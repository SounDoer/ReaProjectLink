local constants = require("readelivery.constants")
local delivery_manifest = require("readelivery.delivery_manifest")
local json = require("readelivery.json")
local default_package_writer = require("readelivery.package_writer")
local publish_plan = require("readelivery.publish_plan")
local source_review = require("readelivery.source_review")
local source_service = require("readelivery.source_service")

local M = {}

local function project_parts(path)
  local directory, filename = path:match("^(.*)[/\\]([^/\\]+)$")
  if not directory then return nil, nil end
  return directory, filename:gsub("%.[Rr][Pp][Pp]$", "")
end

local function same_path(left, right)
  if not left or not right then return false end
  return left:gsub("\\", "/"):lower() == right:gsub("\\", "/"):lower()
end

local function read_json(fs, path, label)
  local bytes, read_error = fs.read_file(path)
  if not bytes then return nil, read_error or ("Could not read " .. label .. ".") end
  local ok, value = pcall(json.decode, bytes)
  if not ok then return nil, label .. " is invalid JSON: " .. tostring(value) end
  if value.schemaVersion ~= 1 then
    return nil, label .. " uses an unsupported schema version."
  end
  return value
end

local function load_previous(fs, package_root)
  local pointer_path = fs.join(package_root, "delivery.json")
  if not fs.exists(pointer_path) then return nil, nil, nil end

  local pointer, pointer_error = read_json(fs, pointer_path, "delivery.json")
  if not pointer then return nil, nil, pointer_error end
  local snapshot, snapshot_error = read_json(
    fs,
    fs.join(package_root, pointer.manifest),
    "published Delivery Manifest"
  )
  if not snapshot then return nil, nil, snapshot_error end
  if snapshot.sourceProjectId ~= pointer.sourceProjectId or
      snapshot.deliverySetId ~= pointer.deliverySetId or
      snapshot.publishRevision ~= pointer.latestPublishRevision then
    return nil, nil, "Published Delivery pointer and snapshot identities do not match."
  end
  return pointer, snapshot
end

function M.create(dependencies)
  dependencies = dependencies or {}
  local writer = dependencies.package_writer or default_package_writer
  local service = {}

  function service.review(adapter, fs, options)
    options = options or {}
    local path = adapter.project_path()
    local directory, project_name = project_parts(path)
    if not directory then return nil, "Save the REAPER project before Publish Review." end

    local derived_package_root = fs.join(directory, "_Delivery", project_name)
    local stored_source_id = adapter.get_project_value(constants.PROJECT_KEYS.source_project_id)
    local stored_identity_path = adapter.get_project_value(
      constants.PROJECT_KEYS.source_identity_project_path
    )
    local stored_package_root = adapter.get_project_value(
      constants.PROJECT_KEYS.source_package_root
    )
    local path_changed = stored_source_id and stored_source_id ~= "" and
      stored_identity_path and stored_identity_path ~= "" and
      not same_path(stored_identity_path, path)
    local starts_new = path_changed and options.save_as_decision == "new"
    local package_root = path_changed and not starts_new and
      stored_package_root and stored_package_root ~= "" and stored_package_root or
      derived_package_root
    local pointer, previous, load_error = load_previous(fs, package_root)
    if load_error then return nil, load_error end

    if starts_new and pointer then
      return nil, "The new Source package destination already contains a published delivery."
    end

    local stored_set_id = adapter.get_project_value(constants.PROJECT_KEYS.delivery_set_id)
    if pointer and stored_source_id and stored_source_id ~= "" and
        pointer.sourceProjectId ~= stored_source_id then
      return nil, "Published package belongs to a different Source Project ID."
    end
    if pointer and stored_set_id and stored_set_id ~= "" and
        pointer.deliverySetId ~= stored_set_id then
      return nil, "Published package belongs to a different Delivery Set ID."
    end

    local current, scan_error = source_service.scan(adapter)
    if not current then return nil, scan_error end
    if starts_new then
      for _, lane in ipairs(current.lanes) do
        for _, clip in ipairs(lane.clips) do clip.clip_id = "" end
      end
      pointer, previous = nil, nil
    end
    local picture_start_samples = tonumber(adapter.get_project_value(
      constants.PROJECT_KEYS.picture_start_samples
    ))
    if picture_start_samples then
      for _, lane in ipairs(current.lanes) do
        for _, clip in ipairs(lane.clips) do
          if clip.start_offset_samples then
            clip.start_offset_samples = clip.start_offset_samples - picture_start_samples
          end
        end
      end
    end
    local review = source_review.build({
      current = current,
      previous_snapshot = previous,
      identity_decisions = options.identity_decisions,
      publish_anyway = options.publish_anyway,
    }, fs)

    review.package_root = package_root
    review.project_name = project_name
    review.project_file = path
    review.base_revision = pointer and pointer.latestPublishRevision or 0
    review.previous_snapshot = previous
    review.source_project_id = not starts_new and
      (stored_source_id or (pointer and pointer.sourceProjectId)) or nil
    review.delivery_set_id = not starts_new and
      (stored_set_id or (pointer and pointer.deliverySetId)) or nil
    review.save_as_decision = options.save_as_decision
    review.path_changed = path_changed
    if path_changed and not options.save_as_decision then
      review.save_as_blocker = "This project path changed. Choose Continue Logical Source or Start New Source."
      review.blocker_count = review.blocker_count + 1
    end
    review.picture_id = adapter.get_project_value(constants.PROJECT_KEYS.picture_id)
    review.reviewed_picture_revision = tonumber(adapter.get_project_value(
      constants.PROJECT_KEYS.reviewed_picture_revision
    ))
    if not review.picture_id or review.picture_id == "" or
        not review.reviewed_picture_revision or not picture_start_samples then
      review.blocker_count = review.blocker_count + 1
      review.picture_blocker = "Subscribe to and review a Picture revision before audio Publish."
    end
    return review
  end

  function service.publish(review, adapter, fs, metadata)
    metadata = metadata or {}
    if review.blocker_count ~= 0 then
      return nil, "Publish Review still has blockers or unresolved decisions."
    end

    local plan = publish_plan.build({
      source_project_id = review.source_project_id,
      delivery_set_id = review.delivery_set_id,
      source_project_name = review.project_name,
      source_project_file = review.project_file,
      published_at = metadata.published_at,
      published_by = metadata.published_by,
      picture_id = review.picture_id,
      reviewed_picture_revision = review.reviewed_picture_revision,
      sample_rate = review.current.sample_rate,
      previous_snapshot = review.previous_snapshot,
      current = review.current,
    }, adapter.new_id)

    adapter.begin_undo("Assign ReaDelivery Publish identities")
    adapter.set_project_value(constants.PROJECT_KEYS.source_project_id, plan.source_project_id)
    adapter.set_project_value(constants.PROJECT_KEYS.delivery_set_id, plan.delivery_set_id)
    adapter.set_project_value(
      constants.PROJECT_KEYS.source_identity_project_path,
      review.project_file
    )
    adapter.set_project_value(
      constants.PROJECT_KEYS.source_package_root,
      review.package_root
    )
    for _, assignment in ipairs(plan.assignments) do
      adapter.set_item_clip_id(assignment.item_ref, assignment.clip_id)
    end
    adapter.mark_project_dirty()
    adapter.end_undo("Assign ReaDelivery Publish identities")
    local saved, save_error = adapter.save_project()
    if not saved then return nil, save_error or "Could not save the Source project." end

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
      constants.PROJECT_KEYS.publish_revision,
      tostring(result.publish_revision)
    )
    adapter.mark_project_dirty()
    adapter.save_project()
    return result
  end

  return service
end

return M
