-- Pure presentation decisions. Nothing here calls ImGui or REAPER.
local M = {}

function M.count(value, noun)
  return string.format("%d %s", value, value == 1 and noun or noun .. "s")
end

function M.project_name(path)
  local name = (path or ""):match("([^/\\]+)$")
  if not name or name == "" then return "Untitled Project" end
  return (name:gsub("%.[Rr][Pp][Pp]$", ""))
end

-- Subscriptions created before the name was stored still carry the package
-- path, whose last directory is the Source project name.
function M.subscription_name(entry)
  if entry.sourceProjectName and entry.sourceProjectName ~= "" then
    return entry.sourceProjectName
  end
  return (entry.pointerPath or ""):match("[/\\]([^/\\]+)[/\\][^/\\]+$") or "Unnamed Source"
end

function M.checked_text(seconds)
  if not seconds then return nil end
  if seconds < 60 then return "Checked just now" end
  if seconds < 3600 then return string.format("Checked %d min ago", seconds // 60) end
  return string.format("Checked %d h ago", seconds // 3600)
end

function M.blocked_summary(count, verb)
  return string.format("Fix %s to %s", M.count(count, "issue"), verb)
end

local function revision_label(value)
  return value > 0 and ("r" .. value) or "None"
end

function M.source_reference(input)
  local check = input.check or { state = "idle" }
  local synchronized = input.synchronized or 0
  local rows = { { "Synchronized", revision_label(synchronized) } }
  if not input.subscribed then
    return {
      state = "unsubscribed", status = "Not Connected", level = "warning",
      note = "Choose the reference.json your mix project published.",
      action = { id = "choose_reference", label = "Choose reference.json" },
      attention = true,
    }
  end
  if check.state == "unreachable" then
    return {
      state = "unreachable", status = "Couldn't Reach Shared Storage", level = "blocked",
      rows = rows, action = { id = "retry", label = "Retry" }, attention = true,
    }
  end
  if check.state == "invalid" then
    return {
      state = "invalid", status = "Couldn't Read the Reference", level = "blocked",
      note = check.error, rows = rows, action = { id = "retry", label = "Retry" }, attention = true,
    }
  end
  if input.media_error then
    return {
      state = "blocked", status = input.media_error, level = "blocked", rows = rows,
      action = { id = "review_update", label = "Review Update" }, attention = true,
    }
  end
  if check.state ~= "done" then
    return { state = "checking", status = "Checking...", level = "neutral", rows = rows, attention = false }
  end
  if check.latest > synchronized then
    return {
      state = "newer", status = string.format("Reference r%d Available", check.latest),
      level = "warning", rows = rows,
      action = { id = "review_update", label = "Review Update" }, attention = true,
    }
  end
  return {
    state = "current", status = "Up to Date", level = "ready",
    rows = { { "Reference", revision_label(synchronized) } }, attention = false,
  }
end

function M.source_delivery(input, pending_reference)
  if (input.track_count or 0) == 0 then
    return {
      state = "unconfigured", status = "No Delivery Tracks", level = "warning",
      note = "Select tracks in REAPER first.",
      action = { id = "register_tracks", label = "Register Selected Tracks" },
      attention = true,
    }
  end
  local revision = input.delivery_revision or 0
  return {
    state = revision > 0 and "published" or "unpublished",
    status = revision > 0 and ("Last Published r" .. revision) or "Not Published Yet",
    level = "neutral",
    rows = { { "Tracks", tostring(input.track_count) }, { "Items", tostring(input.item_count or 0) } },
    note = pending_reference and string.format("Will record Reference r%d", pending_reference) or nil,
    action = { id = "review_publish", label = "Review and Publish" },
    attention = true,
  }
end

function M.source_cards(input)
  local reference = M.source_reference(input)
  local synchronized = input.synchronized or 0
  local pending = reference.state == "newer" and synchronized > 0 and synchronized or nil
  return {
    reference = reference,
    delivery = M.source_delivery(input, pending),
    highlight = reference.attention and "reference" or "delivery",
  }
end

function M.master_reference(input)
  if (input.track_count or 0) == 0 then
    return {
      state = "unconfigured", status = "No Reference Tracks", level = "warning",
      note = "Select video tracks in REAPER first.",
      action = { id = "register_tracks", label = "Register Selected Tracks" },
      attention = true,
    }
  end
  local rows = { { "Tracks", tostring(input.track_count) }, { "Markers", tostring(input.marker_count or 0) } }
  local revision = input.reference_revision or 0
  if revision == 0 then
    return {
      state = "unpublished", status = "Not Published Yet", level = "warning", rows = rows,
      action = { id = "review_publish", label = "Review and Publish" }, attention = true,
    }
  end
  local package_check = input.package_check
  if package_check and package_check.state == "missing" then
    return {
      state = "package_missing", status = "Package Missing", level = "blocked", rows = rows,
      note = string.format(
        "Published files for Reference r%d weren't found. Publish again to restore them.", revision
      ),
      action = { id = "review_publish", label = "Review and Publish" }, attention = true,
    }
  end
  return {
    state = "published", status = "Published r" .. revision, level = "neutral", rows = rows,
    action = { id = "review_publish", label = "Review and Publish" }, attention = false,
  }
end

function M.delivery_row(row, master_reference_revision)
  local check = row.check or { state = "idle" }
  local accepted = row.accepted or 0
  if check.state == "unreachable" then
    return { state = "unreachable", status = "Couldn't Reach", level = "blocked",
      action = { id = "retry", label = "Retry" }, attention = true }
  end
  if check.state == "invalid" then
    return { state = "invalid", status = "Couldn't Read Delivery", level = "blocked", note = check.error,
      action = { id = "retry", label = "Retry" }, attention = true }
  end
  if check.state ~= "done" then
    return { state = "checking", status = "Checking...", level = "neutral", attention = false }
  end
  if check.latest > accepted then
    return { state = "newer", status = string.format("r%d Available · Have r%d", check.latest, accepted),
      level = "warning", action = { id = "sync", label = "Sync" }, attention = true }
  end
  if (row.unmapped_count or 0) > 0 then
    local n = row.unmapped_count
    return { state = "unmapped", status = string.format("%d %s Not Imported", n, n == 1 and "Lane" or "Lanes"),
      level = "neutral", action = { id = "map_lanes", label = "Map Lanes" }, attention = true }
  end
  if check.reviewed_reference and check.reviewed_reference < master_reference_revision then
    return { state = "older_reference",
      status = string.format("Made Against Reference r%d", check.reviewed_reference),
      level = "warning", attention = false }
  end
  return { state = "current", status = string.format("Up to Date · r%d", accepted),
    level = "ready", attention = false }
end

function M.master_cards(input)
  local reference = M.master_reference(input)
  local rows, row_attention, checking = {}, false, false
  for index, source in ipairs(input.rows or {}) do
    local row = M.delivery_row(source, input.reference_revision or 0)
    row.id, row.name = source.id, source.name
    rows[index] = row
    row_attention = row_attention or row.attention
    checking = checking or row.state == "checking"
  end
  local highlight
  if reference.attention then
    highlight = "reference"
  elseif #rows == 0 or row_attention then
    highlight = "deliveries"
  end
  return {
    reference = reference,
    rows = rows,
    highlight = highlight,
    all_current = highlight == nil and not checking,
    deliveries_empty = {
      status = "No Deliveries Yet", level = "warning",
      note = "Add the delivery.json a department published.",
      action = { id = "add_delivery", label = "Add Delivery" },
    },
  }
end

function M.lane_mapping_options(lane)
  local options = {}
  local suggestions = lane.suggestions or {}
  if #suggestions > 0 then
    table.insert(options, { header = "Suggested" })
    for _, suggestion in ipairs(suggestions) do
      table.insert(options, { id = "suggestion", label = suggestion.display_name, track_ref = suggestion.track_ref })
    end
    table.insert(options, { separator = true })
  end
  table.insert(options, { id = "create", label = "New Track" })
  table.insert(options, { id = "selected", label = "Selected Track" })
  table.insert(options, { separator = true })
  table.insert(options, { id = "unmapped", label = "Don't Import" })
  return options
end

function M.mapping_from_option(option, selected_tracks)
  if option.id == "suggestion" then return { kind = "existing", track_ref = option.track_ref } end
  if option.id == "create" then return { kind = "create" } end
  if option.id == "unmapped" then return { kind = "unmapped" } end
  if option.id == "selected" then
    if #selected_tracks ~= 1 then return nil, "Select exactly one track in REAPER first." end
    return { kind = "existing", track_ref = selected_tracks[1] }
  end
  return nil, "Unknown mapping option."
end

function M.lane_mapping_label(mapping, default_kind, track_name)
  local kind = mapping and mapping.kind or default_kind
  if kind == "unmapped" then return "Don't Import" end
  if kind == "existing" then return track_name(mapping.track_ref) end
  return "New Track"
end

function M.mapping_summary(lanes, mappings, default_kind)
  local new_tracks, items = 0, 0
  for _, lane in ipairs(lanes) do
    local kind = mappings[lane.lane_id] and mappings[lane.lane_id].kind or default_kind
    if kind == "create" then new_tracks = new_tracks + 1 end
    if kind ~= "unmapped" then items = items + #lane.clips end
  end
  return M.count(new_tracks, "new track") .. " · " .. M.count(items, "item")
end

function M.with_parent(mappings, parent_track_ref)
  local result = {}
  for lane_id, mapping in pairs(mappings) do
    local copy = {}
    for key, value in pairs(mapping) do copy[key] = value end
    if copy.kind == "create" then copy.parent_track_ref = parent_track_ref end
    result[lane_id] = copy
  end
  return result
end

-- Label and explanation for the whole-project shift (D065); a negative delta
-- means the Reference moved earlier.
function M.shift_texts(seconds)
  local amount = string.format("%.3f s", math.abs(seconds))
  local direction = seconds < 0 and "earlier" or "later"
  local label = string.format("Move All Project Content %s %s", amount,
    seconds < 0 and "Earlier" or "Later")
  local note = string.format(
    "The whole Reference moved %s %s. Move your items, markers, and regions with it to stay in sync.",
    amount, direction)
  return label, note
end

function M.reference_declaration_options(synchronized, last_declared)
  local options = { { id = synchronized, label = string.format("r%d (Synced)", synchronized) } }
  if last_declared and last_declared > 0 and last_declared ~= synchronized then
    table.insert(options, { id = last_declared, label = "r" .. last_declared })
  end
  return options
end

return M
