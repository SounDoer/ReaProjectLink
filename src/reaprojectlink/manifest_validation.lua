local M = {}

local function fail(label, message)
  return nil, label .. " " .. message
end

local function object(value, label)
  if type(value) ~= "table" then return fail(label, "must be an object.") end
  return true
end

local function array(value, label)
  if type(value) ~= "table" then return fail(label, "must be an array.") end
  for key in pairs(value) do
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0 or key > #value then
      return fail(label, "must be an array.")
    end
  end
  return true
end

local function string_field(value, label)
  if type(value) ~= "string" or value == "" then
    return fail(label, "must be a non-empty string.")
  end
  return true
end

local function number_field(value, label, integer, minimum)
  if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
    return fail(label, "must be a finite number.")
  end
  if integer and value % 1 ~= 0 then return fail(label, "must be an integer.") end
  if minimum and value < minimum then
    return fail(label, "must be at least " .. tostring(minimum) .. ".")
  end
  return true
end

local function optional_number(value, label, integer, minimum)
  if value == nil then return true end
  return number_field(value, label, integer, minimum)
end

local function hash_field(value, label)
  local ok, err = string_field(value, label)
  if not ok then return nil, err end
  if not value:match("^sha256:.+") then return fail(label, "must use the sha256: prefix.") end
  return true
end

local function expect_identity(actual, expected, label)
  if expected ~= nil and actual ~= expected then
    return fail(label, "does not match the subscribed package.")
  end
  return true
end

local function claim(seen, value, label)
  if seen[value] then return fail(label, "is duplicated: " .. value) end
  seen[value] = true
  return true
end

function M.delivery_pointer(value)
  local ok, err = object(value, "delivery.json")
  if not ok then return nil, err end
  if value.schemaVersion ~= 1 then return fail("delivery.json", "uses an unsupported schema version.") end
  for _, field in ipairs({ "sourceProjectId", "deliveryId" }) do
    ok, err = string_field(value[field], "delivery.json." .. field)
    if not ok then return nil, err end
  end
  ok, err = number_field(value.latestDeliveryRevision, "delivery.json.latestDeliveryRevision", true, 1)
  if not ok then return nil, err end
  local expected = string.format("history/delivery-%04d.json", value.latestDeliveryRevision)
  if value.manifest ~= expected then
    return fail("delivery.json.manifest", "must be " .. expected .. ".")
  end
  return true
end

function M.delivery_snapshot(value, expected)
  expected = expected or {}
  local ok, err = object(value, "Delivery Manifest")
  if not ok then return nil, err end
  if value.schemaVersion ~= 1 then return fail("Delivery Manifest", "uses an unsupported schema version.") end
  for _, field in ipairs({ "sourceProjectId", "deliveryId", "sourceProjectName" }) do
    ok, err = string_field(value[field], "Delivery Manifest." .. field)
    if not ok then return nil, err end
  end
  ok, err = expect_identity(value.sourceProjectId, expected.source_project_id, "Delivery Manifest sourceProjectId")
  if not ok then return nil, err end
  ok, err = expect_identity(value.deliveryId, expected.delivery_id, "Delivery Manifest deliveryId")
  if not ok then return nil, err end
  ok, err = number_field(value.deliveryRevision, "Delivery Manifest.deliveryRevision", true, 1)
  if not ok then return nil, err end
  ok, err = expect_identity(value.deliveryRevision, expected.revision, "Delivery Manifest deliveryRevision")
  if not ok then return nil, err end
  ok, err = number_field(value.sampleRate, "Delivery Manifest.sampleRate", true, 1)
  if not ok then return nil, err end
  ok, err = object(value.reference, "Delivery Manifest.reference")
  if not ok then return nil, err end
  ok, err = string_field(value.reference.referenceId, "Delivery Manifest.reference.referenceId")
  if not ok then return nil, err end
  ok, err = number_field(value.reference.reviewedRevision, "Delivery Manifest.reference.reviewedRevision", true, 1)
  if not ok then return nil, err end
  ok, err = array(value.lanes, "Delivery Manifest.lanes")
  if not ok then return nil, err end

  local lane_ids, clip_ids = {}, {}
  for lane_index, lane in ipairs(value.lanes) do
    local lane_label = string.format("Delivery Manifest.lanes[%d]", lane_index)
    ok, err = object(lane, lane_label); if not ok then return nil, err end
    ok, err = string_field(lane.laneId, lane_label .. ".laneId"); if not ok then return nil, err end
    ok, err = claim(lane_ids, lane.laneId, "Delivery Lane ID"); if not ok then return nil, err end
    ok, err = array(lane.clips, lane_label .. ".clips"); if not ok then return nil, err end
    for clip_index, clip in ipairs(lane.clips) do
      local clip_label = string.format("%s.clips[%d]", lane_label, clip_index)
      ok, err = object(clip, clip_label); if not ok then return nil, err end
      ok, err = string_field(clip.clipId, clip_label .. ".clipId"); if not ok then return nil, err end
      ok, err = claim(clip_ids, clip.clipId, "Delivery Clip ID"); if not ok then return nil, err end
      ok, err = number_field(clip.mediaRevision, clip_label .. ".mediaRevision", true, 1); if not ok then return nil, err end
      ok, err = string_field(clip.mediaFile, clip_label .. ".mediaFile"); if not ok then return nil, err end
      ok, err = hash_field(clip.mediaHash, clip_label .. ".mediaHash"); if not ok then return nil, err end
      for _, field in ipairs({ "startOffsetSamples", "sourceOffsetSamples", "lengthSamples" }) do
        ok, err = number_field(clip[field], clip_label .. "." .. field, true, field == "lengthSamples" and 0 or nil)
        if not ok then return nil, err end
      end
      ok, err = optional_number(clip.mediaSampleRate, clip_label .. ".mediaSampleRate", true, 1)
      if not ok then return nil, err end
      ok, err = optional_number(clip.channelCount, clip_label .. ".channelCount", true, 1)
      if not ok then return nil, err end
      ok, err = optional_number(clip.itemGain, clip_label .. ".itemGain")
      if not ok then return nil, err end
      for _, field in ipairs({ "fadeInSamples", "fadeOutSamples" }) do
        ok, err = optional_number(clip[field], clip_label .. "." .. field, true, 0)
        if not ok then return nil, err end
      end
      if clip.take ~= nil and type(clip.take) ~= "table" then
        return fail(clip_label .. ".take", "must be an object.")
      end
      local take = clip.take or {}
      for _, field in ipairs({ "volume", "pan", "playbackRate", "pitch" }) do
        ok, err = optional_number(take[field], clip_label .. ".take." .. field)
        if not ok then return nil, err end
      end
      ok, err = optional_number(take.channelMode, clip_label .. ".take.channelMode", true)
      if not ok then return nil, err end
      if take.polarityInverted ~= nil and type(take.polarityInverted) ~= "boolean" then
        return fail(clip_label .. ".take.polarityInverted", "must be a boolean.")
      end
    end
  end
  return true
end

function M.delivery_media_path(fs, package_root, media_file)
  if type(media_file) ~= "string" or not media_file:match("^%.%./media/") then
    return fail("Delivery mediaFile", "must be a relative ../media/... path.")
  end
  local tail = media_file:sub(10)
  if tail == "" or tail:find("\\", 1, true) or tail:find(":", 1, true) then
    return fail("Delivery mediaFile", "contains an invalid path.")
  end
  for part in tail:gmatch("[^/]+") do
    if part == "." or part == ".." then
      return fail("Delivery mediaFile", "must remain inside the managed media directory.")
    end
  end
  if tail:find("//", 1, true) or tail:sub(1, 1) == "/" or tail:sub(-1) == "/" then
    return fail("Delivery mediaFile", "contains an invalid path.")
  end
  return fs.join(package_root, "media", tail)
end

function M.reference_pointer(value)
  local ok, err = object(value, "reference.json")
  if not ok then return nil, err end
  if value.schemaVersion ~= 2 then return fail("reference.json", "uses an unsupported schema version.") end
  for _, field in ipairs({ "masterProjectId", "referenceId" }) do
    ok, err = string_field(value[field], "reference.json." .. field)
    if not ok then return nil, err end
  end
  ok, err = number_field(value.latestReferenceRevision, "reference.json.latestReferenceRevision", true, 1)
  if not ok then return nil, err end
  local expected = string.format("history/reference-%04d.json", value.latestReferenceRevision)
  if value.manifest ~= expected then return fail("reference.json.manifest", "must be " .. expected .. ".") end
  return true
end

function M.reference_snapshot(value, expected)
  expected = expected or {}
  local ok, err = object(value, "Reference Manifest")
  if not ok then return nil, err end
  if value.schemaVersion ~= 2 then return fail("Reference Manifest", "uses an unsupported schema version.") end
  for _, field in ipairs({ "masterProjectId", "masterProjectName", "referenceId" }) do
    ok, err = string_field(value[field], "Reference Manifest." .. field)
    if not ok then return nil, err end
  end
  ok, err = expect_identity(value.masterProjectId, expected.master_project_id, "Reference Manifest masterProjectId")
  if not ok then return nil, err end
  ok, err = expect_identity(value.referenceId, expected.reference_id, "Reference Manifest referenceId")
  if not ok then return nil, err end
  ok, err = number_field(value.referenceRevision, "Reference Manifest.referenceRevision", true, 1)
  if not ok then return nil, err end
  ok, err = expect_identity(value.referenceRevision, expected.revision, "Reference Manifest referenceRevision")
  if not ok then return nil, err end
  ok, err = object(value.timeline, "Reference Manifest.timeline"); if not ok then return nil, err end
  ok, err = number_field(value.timeline.sampleRate, "Reference Manifest.timeline.sampleRate", true, 1)
  if not ok then return nil, err end
  for _, field in ipairs({ "projectTimecodeOffsetSamples", "referenceStartSamples" }) do
    ok, err = number_field(value.timeline[field], "Reference Manifest.timeline." .. field, true)
    if not ok then return nil, err end
  end
  if value.timeline.referenceStartMarkerId ~= nil then
    ok, err = string_field(value.timeline.referenceStartMarkerId,
      "Reference Manifest.timeline.referenceStartMarkerId")
    if not ok then return nil, err end
  end
  ok, err = object(value.timeline.frameRate, "Reference Manifest.timeline.frameRate")
  if not ok then return nil, err end
  ok, err = number_field(value.timeline.frameRate.numerator, "Reference Manifest.timeline.frameRate.numerator", true, 1)
  if not ok then return nil, err end
  ok, err = number_field(value.timeline.frameRate.denominator, "Reference Manifest.timeline.frameRate.denominator", true, 1)
  if not ok then return nil, err end
  if value.timeline.frameRate.dropFrame ~= nil and
      type(value.timeline.frameRate.dropFrame) ~= "boolean" then
    return fail("Reference Manifest.timeline.frameRate.dropFrame", "must be a boolean.")
  end
  for _, field in ipairs({ "lanes", "markers", "regions" }) do
    ok, err = array(value[field], "Reference Manifest." .. field)
    if not ok then return nil, err end
  end

  local lane_ids, item_ids, entry_ids = {}, {}, {}
  for lane_index, lane in ipairs(value.lanes) do
    local label = string.format("Reference Manifest.lanes[%d]", lane_index)
    ok, err = object(lane, label); if not ok then return nil, err end
    ok, err = string_field(lane.laneId, label .. ".laneId"); if not ok then return nil, err end
    ok, err = claim(lane_ids, lane.laneId, "Reference Lane ID"); if not ok then return nil, err end
    ok, err = array(lane.items, label .. ".items"); if not ok then return nil, err end
    for item_index, item in ipairs(lane.items) do
      local item_label = string.format("%s.items[%d]", label, item_index)
      ok, err = object(item, item_label); if not ok then return nil, err end
      ok, err = string_field(item.itemId, item_label .. ".itemId"); if not ok then return nil, err end
      ok, err = claim(item_ids, item.itemId, "Reference Item ID"); if not ok then return nil, err end
      ok, err = string_field(item.videoFile, item_label .. ".videoFile"); if not ok then return nil, err end
      ok, err = hash_field(item.videoHash, item_label .. ".videoHash"); if not ok then return nil, err end
      for _, field in ipairs({ "startSamples", "sourceOffsetSamples", "durationSamples", "playbackRate" }) do
        ok, err = number_field(item[field], item_label .. "." .. field, field ~= "playbackRate", field == "durationSamples" and 0 or nil)
        if not ok then return nil, err end
      end
    end
  end
  for collection_index, collection in ipairs({ value.markers, value.regions }) do
    for index, entry in ipairs(collection) do
      local label = "Reference timeline entry[" .. index .. "]"
      ok, err = object(entry, label); if not ok then return nil, err end
      ok, err = string_field(entry.entryId, label .. ".entryId"); if not ok then return nil, err end
      ok, err = claim(entry_ids, entry.entryId, "Reference timeline entry ID"); if not ok then return nil, err end
      ok, err = number_field(entry.startSamples, label .. ".startSamples", true); if not ok then return nil, err end
      if collection_index == 2 then
        ok, err = number_field(entry.endSamples, label .. ".endSamples", true)
        if not ok then return nil, err end
        if entry.endSamples < entry.startSamples then
          return fail(label .. ".endSamples", "must not precede startSamples.")
        end
      elseif entry.endSamples ~= nil then
        return fail(label .. ".endSamples", "is only valid for Regions.")
      end
    end
  end
  if value.timeline.referenceStartMarkerId ~= nil and
      not entry_ids[value.timeline.referenceStartMarkerId] then
    return fail("Reference Manifest.timeline.referenceStartMarkerId",
      "must identify a published Marker.")
  end
  if value.timeline.referenceStartMarkerId ~= nil then
    local is_marker = false
    for _, marker in ipairs(value.markers) do
      if marker.entryId == value.timeline.referenceStartMarkerId then is_marker = true end
    end
    if not is_marker then
      return fail("Reference Manifest.timeline.referenceStartMarkerId",
        "must identify a Marker, not a Region.")
    end
  end
  return true
end

return M
