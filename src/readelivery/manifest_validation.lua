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
  for _, field in ipairs({ "sourceProjectId", "deliverySetId" }) do
    ok, err = string_field(value[field], "delivery.json." .. field)
    if not ok then return nil, err end
  end
  ok, err = number_field(value.latestPublishRevision, "delivery.json.latestPublishRevision", true, 1)
  if not ok then return nil, err end
  local expected = string.format("history/publish-%04d.json", value.latestPublishRevision)
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
  for _, field in ipairs({ "sourceProjectId", "deliverySetId", "sourceProjectName" }) do
    ok, err = string_field(value[field], "Delivery Manifest." .. field)
    if not ok then return nil, err end
  end
  ok, err = expect_identity(value.sourceProjectId, expected.source_project_id, "Delivery Manifest sourceProjectId")
  if not ok then return nil, err end
  ok, err = expect_identity(value.deliverySetId, expected.delivery_set_id, "Delivery Manifest deliverySetId")
  if not ok then return nil, err end
  ok, err = number_field(value.publishRevision, "Delivery Manifest.publishRevision", true, 1)
  if not ok then return nil, err end
  ok, err = expect_identity(value.publishRevision, expected.revision, "Delivery Manifest publishRevision")
  if not ok then return nil, err end
  ok, err = number_field(value.sampleRate, "Delivery Manifest.sampleRate", true, 1)
  if not ok then return nil, err end
  ok, err = object(value.picture, "Delivery Manifest.picture")
  if not ok then return nil, err end
  ok, err = string_field(value.picture.pictureId, "Delivery Manifest.picture.pictureId")
  if not ok then return nil, err end
  ok, err = number_field(value.picture.reviewedRevision, "Delivery Manifest.picture.reviewedRevision", true, 1)
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

function M.picture_pointer(value)
  local ok, err = object(value, "picture.json")
  if not ok then return nil, err end
  if value.schemaVersion ~= 2 then return fail("picture.json", "uses an unsupported schema version.") end
  ok, err = string_field(value.pictureId, "picture.json.pictureId"); if not ok then return nil, err end
  ok, err = number_field(value.latestPictureRevision, "picture.json.latestPictureRevision", true, 1)
  if not ok then return nil, err end
  local expected = string.format("picture-history/picture-%04d.json", value.latestPictureRevision)
  if value.manifest ~= expected then return fail("picture.json.manifest", "must be " .. expected .. ".") end
  return true
end

function M.picture_snapshot(value, expected)
  expected = expected or {}
  local ok, err = object(value, "Master Reference Manifest")
  if not ok then return nil, err end
  if value.schemaVersion ~= 2 then return fail("Master Reference Manifest", "uses an unsupported schema version.") end
  ok, err = string_field(value.pictureId, "Master Reference Manifest.pictureId"); if not ok then return nil, err end
  ok, err = expect_identity(value.pictureId, expected.picture_id, "Master Reference Manifest pictureId")
  if not ok then return nil, err end
  ok, err = number_field(value.pictureRevision, "Master Reference Manifest.pictureRevision", true, 1)
  if not ok then return nil, err end
  ok, err = expect_identity(value.pictureRevision, expected.revision, "Master Reference Manifest pictureRevision")
  if not ok then return nil, err end
  ok, err = object(value.timeline, "Master Reference Manifest.timeline"); if not ok then return nil, err end
  ok, err = number_field(value.timeline.sampleRate, "Master Reference Manifest.timeline.sampleRate", true, 1)
  if not ok then return nil, err end
  for _, field in ipairs({ "projectTimecodeOffsetSamples", "referenceStartSamples" }) do
    ok, err = number_field(value.timeline[field], "Master Reference Manifest.timeline." .. field, true)
    if not ok then return nil, err end
  end
  ok, err = object(value.timeline.frameRate, "Master Reference Manifest.timeline.frameRate")
  if not ok then return nil, err end
  ok, err = number_field(value.timeline.frameRate.numerator, "Master Reference Manifest.timeline.frameRate.numerator", true, 1)
  if not ok then return nil, err end
  ok, err = number_field(value.timeline.frameRate.denominator, "Master Reference Manifest.timeline.frameRate.denominator", true, 1)
  if not ok then return nil, err end
  if value.timeline.frameRate.dropFrame ~= nil and
      type(value.timeline.frameRate.dropFrame) ~= "boolean" then
    return fail("Master Reference Manifest.timeline.frameRate.dropFrame", "must be a boolean.")
  end
  for _, field in ipairs({ "lanes", "markers", "regions" }) do
    ok, err = array(value[field], "Master Reference Manifest." .. field)
    if not ok then return nil, err end
  end

  local lane_ids, item_ids, entry_ids = {}, {}, {}
  for lane_index, lane in ipairs(value.lanes) do
    local label = string.format("Master Reference Manifest.lanes[%d]", lane_index)
    ok, err = object(lane, label); if not ok then return nil, err end
    ok, err = string_field(lane.laneId, label .. ".laneId"); if not ok then return nil, err end
    ok, err = claim(lane_ids, lane.laneId, "Picture Lane ID"); if not ok then return nil, err end
    ok, err = array(lane.items, label .. ".items"); if not ok then return nil, err end
    for item_index, item in ipairs(lane.items) do
      local item_label = string.format("%s.items[%d]", label, item_index)
      ok, err = object(item, item_label); if not ok then return nil, err end
      ok, err = string_field(item.itemId, item_label .. ".itemId"); if not ok then return nil, err end
      ok, err = claim(item_ids, item.itemId, "Picture Item ID"); if not ok then return nil, err end
      ok, err = string_field(item.videoFile, item_label .. ".videoFile"); if not ok then return nil, err end
      ok, err = hash_field(item.videoHash, item_label .. ".videoHash"); if not ok then return nil, err end
      for _, field in ipairs({ "startSamples", "sourceOffsetSamples", "durationSamples", "playbackRate" }) do
        ok, err = number_field(item[field], item_label .. "." .. field, field ~= "playbackRate", field == "durationSamples" and 0 or nil)
        if not ok then return nil, err end
      end
    end
  end
  local ffop_count = 0
  for collection_index, collection in ipairs({ value.markers, value.regions }) do
    for index, entry in ipairs(collection) do
      local label = "Master Reference timeline entry[" .. index .. "]"
      ok, err = object(entry, label); if not ok then return nil, err end
      ok, err = string_field(entry.entryId, label .. ".entryId"); if not ok then return nil, err end
      ok, err = claim(entry_ids, entry.entryId, "Picture timeline entry ID"); if not ok then return nil, err end
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
      if entry.semanticRole ~= nil then
        if entry.semanticRole ~= "FFOP" or collection_index ~= 1 then
          return fail(label .. ".semanticRole", "must be FFOP on a Marker.")
        end
        ffop_count = ffop_count + 1
      end
    end
  end
  if ffop_count > 1 then return fail("Master Reference Manifest", "contains more than one FFOP Marker.") end
  return true
end

return M
