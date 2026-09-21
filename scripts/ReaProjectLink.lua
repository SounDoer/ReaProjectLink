-- @description ReaProjectLink
-- @version 0.1.0-dev
-- @author ReaProjectLink contributors

local source = debug.getinfo(1, "S").source:sub(2)
local scripts_dir = source:match("^(.*)[/\\]")
local root = scripts_dir and scripts_dir:match("^(.*)[/\\]scripts$")
if not root then
  reaper.ShowMessageBox("Could not resolve the repository path.", "ReaProjectLink", 0)
  return
end
package.path = root .. "/src/?.lua;" .. root .. "/src/?/init.lua;" .. package.path
local runtime_requirements = require("reaprojectlink.runtime_requirements")
local runtime_ok, runtime_error = runtime_requirements.check_reaper(reaper)
if not runtime_ok then
  reaper.ShowMessageBox(runtime_error, "ReaProjectLink", 0)
  return
end
if not reaper.ImGui_GetBuiltinPath then
  reaper.ShowMessageBox(
    "Install ReaImGui " .. runtime_requirements.minimum_reaimgui_api ..
      " or newer through ReaPack and restart REAPER.",
    "ReaProjectLink",
    0
  )
  return
end
package.path = reaper.ImGui_GetBuiltinPath() .. "/?.lua;" .. package.path
local ok_imgui, ImGui = pcall(function() return require("imgui")("0.9") end)
if not ok_imgui then
  reaper.ShowMessageBox(
    "Could not load the ReaImGui " .. runtime_requirements.minimum_reaimgui_api ..
      " compatibility API:\n" .. tostring(ImGui),
    "ReaProjectLink",
    0
  )
  return
end

local constants = require("reaprojectlink.constants")
local filesystem = require("reaprojectlink.filesystem")
local json = require("reaprojectlink.json")
local delivery_import = require("reaprojectlink.delivery_import")
local delivery_update = require("reaprojectlink.delivery_update")
local reference_publish = require("reaprojectlink.reference_publish").create()
local reference_subscription = require("reaprojectlink.reference_subscription")
local adapter = require("reaprojectlink.reaper_adapter")
local delivery_publish = require("reaprojectlink.delivery_publish").create()
local project_service = require("reaprojectlink.project_service")
local ui_factory = require("reaprojectlink.ui")

local ctx = ImGui.CreateContext("ReaProjectLink")
local ui = ui_factory.create(ImGui, ctx)
local fs = filesystem.create(reaper)
local smoke_path = os.getenv("REAPROJECTLINK_UI_SMOKE_RESULT")
local smoke_frame_count = 0
local window_open = true
local message, message_is_error
local source_reference, delivery_review, reference_review, import_review, update_review
local import_mappings = {}
local source_save_as_decision
local master_save_as_decision
local update_lanes = {}
local update_rebindings = {}
local update_target_input = 0
local publish_anyway, import_reference_override, update_reference_override = false, false, false
local reference_publish_anyway = false
local source_shift_entire_project = false
local lock_info, lock_package_root
local active_project_token = adapter.project_token()
local moved_items_change_count = -1
local source_page = "overview"

local function reset_transient_state()
  message, message_is_error = nil, nil
  source_reference, delivery_review, reference_review = nil, nil, nil
  import_review, update_review = nil, nil
  import_mappings = {}
  source_save_as_decision = nil
  master_save_as_decision = nil
  update_lanes = {}
  update_rebindings = {}
  update_target_input = 0
  publish_anyway, import_reference_override = false, false
  update_reference_override, reference_publish_anyway = false, false
  source_shift_entire_project = false
  lock_info, lock_package_root = nil, nil
  moved_items_change_count = -1
  source_page = "overview"
end

local function notify(value, is_error)
  if is_error then
    message, message_is_error = value, true
  else
    -- Successful routine actions are reflected by the surrounding state. They
    -- do not need a persistent global notification that displaces the UI.
    message, message_is_error = nil, false
  end
end

local function short_id(value)
  return tostring(value or ""):sub(1, 8)
end

-- Subscriptions created before the name was stored still carry the package
-- path, whose last directory is the Source project name.
local function subscription_name(entry)
  if entry.sourceProjectName and entry.sourceProjectName ~= "" then
    return entry.sourceProjectName
  end
  return (entry.pointerPath or ""):match("[/\\]([^/\\]+)[/\\][^/\\]+$") or "Unnamed Source"
end

local function choose_json(title)
  local ok, path = reaper.GetUserFileNameForRead("", title, "json")
  return ok and path or nil
end

local function metadata()
  local user = os.getenv("USERNAME") or os.getenv("USER") or "unknown"
  local now = os.date("!%Y-%m-%dT%H:%M:%SZ")
  return {
    published_at = now,
    published_by = user,
    lock_metadata = {
      user = user,
      machine = os.getenv("COMPUTERNAME") or "unknown",
      started_at = now,
    },
  }
end

local function draw_error_banner()
  if not message or not message_is_error then return end
  local error_message = message
  ImGui.PushStyleColor(ctx, ImGui.Col_ChildBg, 0x28171dff)
  ImGui.PushStyleColor(ctx, ImGui.Col_Border, 0x71313dff)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 18, 11)
  if ImGui.BeginChild(ctx, "global-error", 0, 70, 1, ImGui.WindowFlags_NoScrollbar) then
    ui:status("Error", "blocked")
    ImGui.SameLine(ctx)
    if ImGui.SmallButton(ctx, "Dismiss##global-error") then
      message, message_is_error = nil, false
    end
    ImGui.TextWrapped(ctx, error_message)
    ImGui.EndChild(ctx)
  end
  ImGui.PopStyleVar(ctx)
  ImGui.PopStyleColor(ctx, 2)
end

local function inspect_lock(package_root)
  lock_info = fs.read_lock(package_root)
  lock_package_root = lock_info and package_root or nil
end

local function draw_lock()
  if not lock_info then return end
  ImGui.TextWrapped(ctx, string.format(
    "Publish lock: %s on %s since %s",
    lock_info.user or "unknown user",
    lock_info.machine or "unknown machine",
    lock_info.started_at or "unknown time"
  ))
  ImGui.TextWrapped(ctx, "Confirm that no other user or computer is publishing before unlocking.")
  if ImGui.Button(ctx, "Unlock Publishing...") then
    local confirmed = reaper.ShowMessageBox(
      "Unlock publishing only if no other user or computer is publishing to this package.",
      "Unlock Publishing",
      1
    ) == 1
    if confirmed then
      local removed, err = fs.remove_lock(lock_package_root, lock_info.token)
      if removed then
        lock_info, lock_package_root = nil, nil
        notify("Publishing unlocked. Refresh the Review before trying again.")
      else notify(err, true) end
    end
  end
  ImGui.Separator(ctx)
end

local function draw_uninitialized(state)
  ImGui.TextWrapped(ctx, "Choose the Project Type for this saved .rpp.")
  if ImGui.Button(ctx, "Initialize Source Project") then
    local result, err = project_service.initialize_source(adapter)
    notify(result and "Source Project initialized." or err, not result)
  end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Initialize Master Project") then
    local result, err = project_service.initialize_master(adapter)
    notify(result and "Master Project initialized." or err, not result)
  end
  if state.path == "" then ImGui.TextWrapped(ctx, "Save this project before initialization.") end
end

local function check_source_reference()
  local status, err = reference_subscription.check(adapter, fs)
  source_reference = status
  notify(status and "Reference subscription checked." or err, not status)
end

local function draw_source_reference(state)
  ImGui.Text(ctx, "Reference Subscription")
  if ImGui.Button(ctx, "Select reference.json") then
    local path = choose_json("Select published reference.json")
    if path then
      local result, err = reference_subscription.subscribe(adapter, fs, path)
      if result then check_source_reference() else notify(err, true) end
    end
  end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Check Reference Update") then check_source_reference() end
  if not source_reference then
    if not state.reference_manifest_path or state.reference_manifest_path == "" then
      ImGui.TextWrapped(ctx, "No Reference subscription yet.")
    else
      ImGui.TextWrapped(ctx, "Subscribed: " .. state.reference_manifest_path)
      ImGui.TextWrapped(ctx, string.format(
        "Synchronized Reference Revision %d | Reviewed Reference Revision %d | Check Reference Update for the latest revision",
        state.synchronized_reference_revision,
        state.reviewed_reference_revision
      ))
    end
    return
  end
  ImGui.TextWrapped(ctx, string.format(
    "Reference %s | Latest Reference Revision %d | Synchronized Reference Revision %d | Reviewed Reference Revision %d",
    source_reference.reference_id,
    source_reference.latest_revision,
    source_reference.synchronized_revision,
    source_reference.reviewed_revision
  ))
  local mirror = source_reference.alignment_mode ~= "relative"
  local changed, next_mirror = ImGui.Checkbox(ctx, "Mirror Master Timeline", mirror)
  if changed then
    local result, err = reference_subscription.set_alignment_mode(
      adapter, next_mirror and "mirror" or "relative"
    )
    if result then check_source_reference() else notify(err, true) end
  end
  if source_reference.video_error then ImGui.TextWrapped(ctx, "Blocked: " .. source_reference.video_error) end
  if ImGui.Button(ctx, "Detach Selected Reference Items") then
    local result, err = reference_subscription.detach_selected_reference_items(adapter)
    notify(result and string.format("Detached %d Reference Item(s).", result.detached) or err, not result)
  end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Detach Selected Reference Tracks") then
    local result, err = reference_subscription.detach_selected_reference_tracks(adapter)
    notify(result and string.format("Detached %d Reference Track(s).", result.detached) or err, not result)
  end
  if source_reference.can_shift_entire_project then
    ImGui.TextWrapped(ctx, string.format(
      "The entire Reference moved by %.3f seconds.", source_reference.shift_seconds
    ))
    local changed
    changed, source_shift_entire_project = ImGui.Checkbox(
      ctx, "Shift entire Source project by this amount", source_shift_entire_project
    )
  end
  if source_reference.available and
      source_reference.synchronized_revision ~= source_reference.latest_revision and
      ImGui.Button(ctx, "Synchronize Reference") then
    local result, err = reference_subscription.synchronize(adapter, source_reference, {
      shift_entire_project = source_shift_entire_project,
    })
    source_shift_entire_project = false
    if result then check_source_reference() else notify(err, true) end
  end
  if source_reference.synchronized_revision == source_reference.latest_revision and
      source_reference.reviewed_revision ~= source_reference.latest_revision and
      ImGui.Button(ctx, "Mark Reference Reviewed") then
    local result, err = reference_subscription.mark_reviewed(adapter, source_reference)
    if result then check_source_reference() else notify(err, true) end
  end
end

local function refresh_delivery_review()
  local review, err = delivery_publish.review(adapter, fs, {
    publish_anyway = publish_anyway,
    save_as_decision = source_save_as_decision,
  })
  delivery_review = review
  notify(review and "Delivery Publish Review refreshed." or err, not review)
end

local function draw_delivery_review()
  if not delivery_review then return end
  ImGui.Separator(ctx)
  if delivery_review.project_change_count and
      delivery_review.project_change_count ~= adapter.project_change_count() then
    ImGui.TextWrapped(ctx, "Delivery Publish Review Out of Date: the project changed.")
    if ImGui.Button(ctx, "Refresh Delivery Publish Review") then refresh_delivery_review() end
    return
  end
  ImGui.Text(ctx, string.format(
    "Delivery r%d | Reference r%s | %d blocker(s)",
    delivery_review.delivery_revision,
    tostring(delivery_review.reviewed_reference_revision or "none"),
    delivery_review.blocker_count
  ))
  ImGui.TextWrapped(ctx, "Output: " .. delivery_review.package_root)
  if delivery_review.reference_blocker then ImGui.TextWrapped(ctx, delivery_review.reference_blocker) end
  if delivery_review.save_as_blocker then
    ImGui.TextWrapped(ctx, delivery_review.save_as_blocker)
    if ImGui.Button(ctx, "Continue Existing Project") then
      source_save_as_decision = "continue"
      refresh_delivery_review()
    end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Start New Project") then
      source_save_as_decision = "new"
      refresh_delivery_review()
    end
  end
  if delivery_review.has_unprocessed_fx then
    if not publish_anyway and ImGui.Button(ctx, "Publish Unprocessed Media...") then
      publish_anyway = reaper.ShowMessageBox(
        "Detected Track FX or Take FX will not be included in the published media. Continue?",
        "Publish Unprocessed Media",
        1
      ) == 1
      if publish_anyway then refresh_delivery_review() end
    elseif publish_anyway then
      ImGui.TextWrapped(ctx, "Warning: detected FX will not be included in the published media.")
    end
  end
  for _, lane in ipairs(delivery_review.lanes) do
    if ImGui.TreeNode(ctx, lane.display_name .. "##" .. lane.lane_id) then
      if lane.fx_blocked then ImGui.TextWrapped(ctx, "Blocked: Delivery Track has FX.") end
      for _, row in ipairs(lane.clips) do
        ImGui.TextWrapped(ctx, string.format("[%s] %s", row.status, row.display_name or "(unnamed)"))
        for _, blocker in ipairs(row.blockers or {}) do ImGui.TextWrapped(ctx, "  " .. blocker) end
      end
      ImGui.TreePop(ctx)
    end
  end
  if delivery_review.blocker_count == 0 and ImGui.Button(ctx, "Save & Publish Delivery") then
    local result, err = delivery_publish.publish(delivery_review, adapter, fs, metadata())
    if result then
      local message = "Published Delivery Revision " .. result.delivery_revision .. "."
      if result.project_save_error then message = message .. " " .. result.project_save_error end
      if result.lock_release_error then
        message = message .. " Publish lock cleanup failed: " .. result.lock_release_error
      end
      notify(message, result.project_save_error ~= nil or result.lock_release_error ~= nil)
      delivery_review, source_save_as_decision = nil, nil
    else notify(err, true); inspect_lock(delivery_review.package_root) end
  end
end

local function project_name(path)
  local name = (path or ""):match("([^/\\]+)$") or "Untitled project"
  return name:gsub("%.[Rr][Pp][Pp]$", "")
end

local function source_reference_revisions(state)
  if source_reference then
    return source_reference.latest_revision or 0,
      source_reference.synchronized_revision or 0,
      source_reference.reviewed_revision or 0
  end
  return nil, state.synchronized_reference_revision or 0,
    state.reviewed_reference_revision or 0
end

local function open_delivery_review()
  refresh_delivery_review()
  if delivery_review then source_page = "delivery_review" end
end

local function draw_source_next_action(state, lanes)
  if ui:begin_card("source-next-action", 124) then
    ui:heading("Next action")
    local subscribed = state.reference_manifest_path and state.reference_manifest_path ~= ""
    local latest, synchronized, reviewed = source_reference_revisions(state)
    if not subscribed then
      ui:status("Setup required", "warning")
      if ui:primary_button("Subscribe to Reference  →") then source_page = "reference" end
    elseif not source_reference then
      ui:status("Reference status not checked", "primary")
      if ui:primary_button("Check Reference Update") then check_source_reference() end
    elseif not source_reference.available or source_reference.video_error then
      ui:status("Reference needs attention", "blocked")
      if ui:primary_button("Open Reference  →") then source_page = "reference" end
    elseif synchronized ~= latest then
      ui:status(string.format("Reference r%d available", latest), "warning")
      if ui:primary_button("Review Reference Update  →") then source_page = "reference" end
    elseif reviewed ~= latest then
      ui:status(string.format("Reference r%d review required", latest), "warning")
      if ui:primary_button("Open Reference  →") then source_page = "reference" end
    elseif #lanes == 0 then
      ui:status("Delivery setup required", "warning")
      if ui:primary_button("Set Up Delivery Tracks  →") then source_page = "delivery" end
    else
      ui:status("Ready to review", "ready")
      if ui:primary_button("Review Delivery  →") then open_delivery_review() end
    end
  end
  ui:end_card()
end

local function draw_source_reference_card(state, width)
  if ui:begin_card("source-reference-card", 206, width) then
    ui:heading("Reference")
    local subscribed = state.reference_manifest_path and state.reference_manifest_path ~= ""
    local latest, synchronized, reviewed = source_reference_revisions(state)
    if not subscribed then
      ui:status("Not subscribed", "warning")
      ui:muted("Connect this Source Project to the Reference published by its Master Project.")
      if ImGui.Button(ctx, "Open Reference") then source_page = "reference" end
    elseif not latest then
      ui:status("Status not checked", "primary")
      ui:label_value("Synchronized", "Reference r" .. synchronized)
      ui:label_value("Reviewed", "Reference r" .. reviewed)
      if ImGui.Button(ctx, "Check for Update") then check_source_reference() end
    else
      local level = latest == synchronized and latest == reviewed and "ready" or "warning"
      local label = level == "ready" and "Synchronized and reviewed" or "Action required"
      ui:status(label, level)
      ui:label_value("Latest", "Reference r" .. latest)
      ui:label_value("Synchronized", "Reference r" .. synchronized)
      ui:label_value("Reviewed", "Reference r" .. reviewed)
      if ImGui.Button(ctx, "Open Reference") then source_page = "reference" end
    end
  end
  ui:end_card()
end

local function draw_source_delivery_card(state, lanes, width)
  if ui:begin_card("source-delivery-card", 206, width) then
    ui:heading("Delivery")
    local item_count = 0
    for _, lane in ipairs(lanes) do item_count = item_count + lane.item_count end
    if #lanes == 0 then
      ui:status("Not configured", "warning")
      ui:muted("No Delivery Tracks are registered in this Source Project.")
      if ImGui.Button(ctx, "Set Up Delivery Tracks") then source_page = "delivery" end
    else
      ui:status("Ready to review", "ready")
      ui:label_value("Latest", state.delivery_revision > 0 and
        ("Delivery r" .. state.delivery_revision) or "Not published")
      ui:label_value("Tracks", #lanes)
      ui:label_value("Items", item_count)
      if ImGui.Button(ctx, "Open Delivery") then source_page = "delivery" end
      ImGui.SameLine(ctx)
      if ui:primary_button("Review Delivery") then open_delivery_review() end
    end
  end
  ui:end_card()
end

local function draw_source_overview(state)
  local lanes = project_service.delivery_tracks(adapter)
  draw_source_next_action(state, lanes)
  ImGui.Dummy(ctx, 0, 4)
  local available_width = ImGui.GetContentRegionAvail(ctx)
  if available_width >= 660 then
    local card_width = (available_width - 10) / 2
    draw_source_reference_card(state, card_width)
    ImGui.SameLine(ctx)
    draw_source_delivery_card(state, lanes, 0)
  else
    draw_source_reference_card(state, 0)
    draw_source_delivery_card(state, lanes, 0)
  end
  ImGui.Dummy(ctx, 0, 4)
  if ui:begin_card("source-project-health", 88) then
    ui:heading("Project health")
    if state.path == "" then
      ui:status("Project must be saved", "blocked")
    elseif lock_info then
      ui:status("Publishing is locked", "blocked")
    else
      ui:status("Project is available", "ready")
    end
  end
  ui:end_card()
end

local function draw_source_reference_page(state)
  if ui:begin_card("source-reference-page", 0) then draw_source_reference(state) end
  ui:end_card()
end

local function draw_source_delivery_page(state)
  if ui:begin_card("source-delivery-page", 0) then
    ui:heading("Delivery Tracks")
    if state.delivery_revision > 0 then
      ui:status("Latest Delivery r" .. state.delivery_revision, "ready")
    else
      ui:status("No Delivery published", "warning")
    end
    if ui:primary_button("Register Selected Delivery Tracks") then
      local result, err = project_service.register_selected_tracks(adapter)
      notify(result and string.format("Registered %d Track(s).", result.added) or err, not result)
    end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Unregister Selected Delivery Tracks...") then
      local result, err = project_service.unregister_selected_tracks(adapter)
      notify(result and string.format("Unregistered %d Track(s).", result.removed) or err, not result)
    end
    ImGui.Separator(ctx)
    local lanes = project_service.delivery_tracks(adapter)
    if #lanes == 0 then
      ui:muted("No Delivery Tracks are registered. Select Tracks in REAPER, then register them here.")
    else
      for _, lane in ipairs(lanes) do
        ImGui.Text(ctx, lane.display_name)
        ImGui.SameLine(ctx, 280)
        ui:muted(string.format("%d Item(s)", lane.item_count))
      end
    end
    ImGui.Dummy(ctx, 0, 8)
    if ui:primary_button("Review Delivery  →") then open_delivery_review() end
  end
  ui:end_card()
end

local function draw_source_settings(state)
  if ui:begin_card("source-settings-project", 0) then
    ui:heading("Project")
    ui:label_value("Project Type", "Source Project")
    ui:label_value("Project ID", state.project_id or "Not initialized")
    ui:label_value("Delivery ID", state.delivery_id or "Not assigned")
    ui:label_value("Project path", state.path ~= "" and state.path or "Not saved")
    ui:label_value("Reference manifest", state.reference_manifest_path or "Not subscribed")
    ui:label_value("Synchronized", "Reference r" .. (state.synchronized_reference_revision or 0))
    ui:label_value("Reviewed", "Reference r" .. (state.reviewed_reference_revision or 0))
  end
  ui:end_card()
end

local function draw_source_review_page()
  if ImGui.Button(ctx, "←  Back to Delivery") then
    source_page = "delivery"
    delivery_review = nil
  end
  ImGui.Dummy(ctx, 0, 4)
  ui:title("Delivery Publish Review")
  ui:muted("Validate the complete Delivery snapshot before it becomes externally visible.")
  ImGui.Dummy(ctx, 0, 8)
  if ui:begin_card("source-delivery-review", 0) then draw_delivery_review() end
  ui:end_card()
end

local function draw_source_navigation()
  local items = {
    { "Overview", "overview" },
    { "Reference", "reference" },
    { "Delivery", "delivery" },
    { "Settings", "settings" },
  }
  for _, item in ipairs(items) do
    local selected = source_page == item[2] or
      (source_page == "delivery_review" and item[2] == "delivery")
    if ui:nav_item(item[1], selected) then source_page = item[2] end
  end
end

local function draw_source(state)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 22, 14)
  if ImGui.BeginChild(ctx, "source-header", 0, 78, 1) then
    ui:title("ReaProjectLink")
    ui:heading(project_name(state.path))
    ImGui.SameLine(ctx)
    ui:status("Source Project", "primary")
    ImGui.EndChild(ctx)
  end
  ImGui.PopStyleVar(ctx)

  draw_error_banner()

  ImGui.PushStyleColor(ctx, ImGui.Col_ChildBg, ui.colors.sidebar)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 14, 18)
  if ImGui.BeginChild(ctx, "source-sidebar", 188, 0, 1) then
    draw_source_navigation()
    ImGui.EndChild(ctx)
  end
  ImGui.PopStyleVar(ctx)
  ImGui.PopStyleColor(ctx)
  ImGui.SameLine(ctx, 0, 0)

  ImGui.PushStyleColor(ctx, ImGui.Col_ChildBg, ui.colors.window)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 24, 20)
  if ImGui.BeginChild(ctx, "source-content", 0, 0) then
    draw_lock()
    if source_page == "overview" then draw_source_overview(state)
    elseif source_page == "reference" then draw_source_reference_page(state)
    elseif source_page == "delivery" then draw_source_delivery_page(state)
    elseif source_page == "settings" then draw_source_settings(state)
    elseif source_page == "delivery_review" then draw_source_review_page()
    else source_page = "overview" end
    ImGui.EndChild(ctx)
  end
  ImGui.PopStyleVar(ctx)
  ImGui.PopStyleColor(ctx)
end

local function refresh_reference_review()
  local review, err = reference_publish.review(adapter, fs, {
    publish_anyway = reference_publish_anyway,
    save_as_decision = master_save_as_decision,
  })
  reference_review = review
  notify(review and "Reference Publish Review ready." or err, not review)
end

local function draw_reference_publish(state)
  ImGui.Text(ctx, "Reference Publishing")
  if state.reference_revision > 0 then
    ImGui.TextWrapped(ctx, string.format(
      "Reference %s | Latest Reference Revision %d",
      short_id(state.reference_id),
      state.reference_revision
    ))
  else
    ImGui.TextWrapped(ctx, "No Reference published yet.")
  end
  if ImGui.Button(ctx, "Register Selected Reference Tracks") then
    local result, err = reference_publish.register_selected_tracks(adapter)
    notify(result and string.format("Registered %d Reference Track(s).", result.added) or err, not result)
  end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Unregister Selected Reference Tracks") then
    local result, err = reference_publish.unregister_selected_tracks(adapter)
    notify(result and string.format("Removed %d Reference Track(s).", result.removed) or err, not result)
  end
  if ImGui.Button(ctx, "Treat Selected Reference Items as New...") then
    if reaper.ShowMessageBox(
      "Assign new stable identities? Source Projects will see these as new Reference Items.",
      "Treat Reference Items as New",
      1
    ) == 1 then
      local result, err = reference_publish.reset_selected_reference_items(adapter)
      notify(result and string.format("Assigned new identities to %d Reference Item(s).", result.reset) or err, not result)
    end
  end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Treat Selected Reference Tracks as New...") then
    if reaper.ShowMessageBox(
      "Assign new stable identities? Source Projects will see these as new Reference Tracks.",
      "Treat Reference Tracks as New",
      1
    ) == 1 then
      local result, err = reference_publish.reset_selected_reference_tracks(adapter)
      notify(result and string.format("Assigned new identities to %d Reference Track(s).", result.reset) or err, not result)
    end
  end
  if ImGui.Button(ctx, "Register Selected Markers/Regions") then
    local result, err = reference_publish.register_selected_timeline_entries(adapter)
    notify(result and string.format("Registered %d timeline entry/entries.", result.added) or err, not result)
  end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Unregister Selected Markers/Regions") then
    local result, err = reference_publish.unregister_selected_timeline_entries(adapter)
    notify(result and string.format("Removed %d timeline entry/entries.", result.removed) or err, not result)
  end
  if ImGui.Button(ctx, "Set Selected Marker as Reference Start") then
    local result, err = reference_publish.set_selected_reference_start(adapter)
    notify(result and "Reference Start Marker assigned." or err, not result)
  end
  local registered_timeline, timeline_error = reference_publish.timeline_entries(adapter)
  ImGui.TextWrapped(ctx, string.format(
    "%d Reference Track(s), %d registered Marker/Region entries.",
    #reference_publish.reference_tracks(adapter),
    (function()
      local count = 0
      for _, entry in ipairs(registered_timeline or {}) do
        if entry.registered then count = count + 1 end
      end
      return count
    end)()
  ))
  if timeline_error then ImGui.TextWrapped(ctx, "Blocked: " .. timeline_error) end
  if ImGui.Button(ctx, "Open Reference Publish Review") then refresh_reference_review() end
  if not reference_review then return end
  if reference_review.project_change_count and
      reference_review.project_change_count ~= adapter.project_change_count() then
    ImGui.TextWrapped(ctx, "Reference Publish Review Out of Date: the project changed.")
    if ImGui.Button(ctx, "Refresh Reference Publish Review") then
      refresh_reference_review()
    end
    return
  end
  ImGui.TextWrapped(ctx, string.format(
    "%d Track(s) | %d video Item(s) | %d Marker(s) | %d Region(s) | %d blocker(s)",
    #reference_review.lanes, reference_review.item_count,
    #reference_review.markers, #reference_review.regions, reference_review.blocker_count
  ))
  if reference_review.empty_blocker then ImGui.TextWrapped(ctx, reference_review.empty_blocker) end
  if reference_review.save_as_blocker then
    ImGui.TextWrapped(ctx, reference_review.save_as_blocker)
    if ImGui.Button(ctx, "Continue Existing Project##reference") then
      master_save_as_decision = "continue"
      refresh_reference_review()
    end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Start New Project##reference") then
      master_save_as_decision = "new"
      refresh_reference_review()
    end
  end
  for _, blocker in ipairs(reference_review.blockers or {}) do
    if blocker ~= reference_review.empty_blocker then
      ImGui.TextWrapped(ctx, "Blocked: " .. blocker)
    end
  end
  if reference_review.unchanged then
    ImGui.TextWrapped(ctx, string.format(
      "This Reference is identical to Reference r%d.",
      reference_review.base_revision
    ))
    if not reference_publish_anyway and
        ImGui.Button(ctx, "Publish Unchanged Reference Revision...") then
      reference_publish_anyway = reaper.ShowMessageBox(
        "Publish a new unchanged Reference Revision? Source Projects will still need to synchronize and review it.",
        "Publish Unchanged Reference Revision",
        1
      ) == 1
      if reference_publish_anyway then refresh_reference_review() end
    end
  end
  if reference_review.blocker_count == 0 and not reference_review.unchanged_blocker then
    ImGui.TextWrapped(ctx, string.format(
      "Will publish as Reference r%d.",
      reference_review.reference_revision
    ))
    if ImGui.Button(ctx, "Save & Publish Reference") then
      local result, err = reference_publish.publish(reference_review, adapter, fs, metadata())
      if result then
        local message = "Published Reference revision " .. result.reference_revision .. "."
        if result.project_save_error then message = message .. " " .. result.project_save_error end
        if result.lock_release_error then
          message = message .. " Publish lock cleanup failed: " .. result.lock_release_error
        end
        notify(message, result.project_save_error ~= nil or result.lock_release_error ~= nil)
        reference_review, reference_publish_anyway, master_save_as_decision = nil, false, nil
      else notify(err, true); inspect_lock(reference_review.package_root) end
    end
  end
end

local function draw_mapping(lane, mappings, prefix)
  local mapping = mappings[lane.lane_id]
  ImGui.Text(ctx, lane.display_name .. " (" .. #lane.clips .. " Clips to import)")
  if lane.orphaned then
    ImGui.TextWrapped(ctx, "  Target Track Missing; map the Lane again to restore the Clips.")
  end
  for _, present in ipairs(lane.present_clips or {}) do
    ImGui.TextWrapped(ctx, string.format(
      "  %s is already in this project on %s and will not be imported again.",
      present.display_name or short_id(present.clip_id),
      present.track_name or "an unnamed Track"
    ))
  end
  if ImGui.Button(ctx, "Create Track##" .. prefix .. lane.lane_id) then
    mappings[lane.lane_id] = { kind = "create" }
  end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Use Selected Track##" .. prefix .. lane.lane_id) then
    local selected = adapter.selected_tracks()
    if #selected == 1 then
      mappings[lane.lane_id] = { kind = "existing", track_ref = selected[1] }
    else notify("Select exactly one Track.", true) end
  end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Leave Unmapped##" .. prefix .. lane.lane_id) then
    mappings[lane.lane_id] = { kind = "unmapped" }
  end
  for _, suggestion in ipairs(lane.suggestions or {}) do
    if ImGui.Button(ctx, "Use " .. suggestion.display_name .. "##" .. prefix .. suggestion.track_guid) then
      mappings[lane.lane_id] = { kind = "existing", track_ref = suggestion.track_ref }
    end
  end
  if mapping then
    local detail = mapping.kind
    if mapping.kind == "existing" then
      detail = "use " .. adapter.track_name(mapping.track_ref)
    end
    ImGui.Text(ctx, "  Mapping: " .. detail)
  end
end

local function begin_import()
  local path = choose_json("Select Source delivery.json")
  if not path then return end
  local review, err = delivery_import.review(adapter, fs, path)
  import_review, import_mappings = review, {}
  if review then
    for _, lane in ipairs(review.lanes) do import_mappings[lane.lane_id] = { kind = "create" } end
    notify("First Import Review ready.")
  else notify(err, true) end
end

local function draw_import()
  if not import_review then return end
  ImGui.TextWrapped(ctx, string.format(
    "%s | Delivery r%d | Reviewed Reference Revision %d",
    import_review.snapshot.sourceProjectName,
    import_review.pointer.latestDeliveryRevision,
    import_review.snapshot.reference.reviewedRevision
  ))
  if import_review.reference_error then ImGui.TextWrapped(ctx, "Blocked: " .. import_review.reference_error) end
  if import_review.reference_warning then
    local changed
    changed, import_reference_override = ImGui.Checkbox(ctx, "Allow Reference revision difference", import_reference_override)
  end
  ImGui.Separator(ctx)
  ImGui.Text(ctx, string.format("Delivery Lanes to map (%d)", #import_review.lanes))
  if ImGui.Button(ctx, "Create All Under Selected Folder Track##import") then
    local selected = adapter.selected_tracks()
    if #selected == 1 then
      for _, lane in ipairs(import_review.lanes) do
        import_mappings[lane.lane_id] = {
          kind = "create",
          parent_track_ref = selected[1],
        }
      end
    else notify("Select exactly one Folder Track.", true) end
  end
  for _, lane in ipairs(import_review.lanes) do draw_mapping(lane, import_mappings, "import-") end
  if import_review.blocker_count == 0 and ImGui.Button(ctx, "Import Delivery") then
    local result, err = delivery_import.apply(import_review, adapter, {
      mappings = import_mappings,
      allow_reference_revision_mismatch = import_reference_override,
    })
    if result then
      notify(string.format("Imported %d Item(s) on %d new Track(s).", result.created_items, result.created_tracks))
      import_review, import_mappings = nil, {}
    else notify(err, true) end
  end
end

local function subscriptions()
  local stored = adapter.get_project_value(constants.PROJECT_KEYS.delivery_subscriptions)
  if not stored or stored == "" then return {} end
  local ok, value = pcall(json.decode, stored)
  return ok and value or {}
end

local function begin_update(source_id, target_revision)
  local review, err = delivery_update.review(adapter, fs, source_id, target_revision)
  -- A failed reload keeps the review the user is looking at.
  if not review then notify(err, true); return end
  update_review = review
  update_lanes = {}
  update_rebindings = {}
  update_target_input = review.target_revision
  for _, lane in ipairs(review.unmapped_lanes) do
    update_lanes[lane.lane_id] = { kind = "unmapped" }
  end
  if review.pending_count == 0 then
    notify(string.format(
      "Delivery r%d contains no synchronized Items.",
      review.target_revision
    ))
  else
    notify("Delivery Update Review ready.")
  end
end

local function draw_bound_lanes()
  if #update_review.bound_lanes == 0 then return end
  ImGui.Separator(ctx)
  ImGui.Text(ctx, string.format("Mapped Delivery Lanes (%d)", #update_review.bound_lanes))
  ImGui.TextWrapped(ctx, "Each synchronization replaces Source-managed Items on these Tracks.")
  for _, lane in ipairs(update_review.bound_lanes) do
    local rebound = update_rebindings[lane.lane_id]
    ImGui.Text(ctx, string.format(
      "%s -> %s",
      lane.display_name,
      rebound and adapter.track_name(rebound) or lane.track_name
    ))
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Use Selected Track##rebind-" .. lane.lane_id) then
      local selected = adapter.selected_tracks()
      if #selected == 1 then update_rebindings[lane.lane_id] = selected[1]
      else notify("Select exactly one Track.", true) end
    end
    if rebound then
      ImGui.SameLine(ctx)
      if ImGui.Button(ctx, "Keep Current##rebind-" .. lane.lane_id) then
        update_rebindings[lane.lane_id] = nil
      end
    end
  end
end

local function draw_update_target()
  ImGui.Text(ctx, string.format(
    "Target Delivery Revision %d of %d",
    update_review.target_revision,
    update_review.latest_revision
  ))
  ImGui.SetNextItemWidth(ctx, 120)
  local changed
  changed, update_target_input = ImGui.InputInt(ctx, "Revision##target", update_target_input)
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Load Revision") then
    begin_update(update_review.source_project_id, update_target_input)
  end
end

local function draw_update()
  if not update_review then return end
  draw_update_target()
  ImGui.TextWrapped(ctx, string.format(
    "Synchronize Source snapshot: replace %d managed Item(s) with %d Item(s) from Delivery r%d.",
    update_review.replacement_count,
    update_review.source_item_count,
    update_review.target_revision
  ))
  ImGui.TextWrapped(ctx,
    "Synchronized Items on mapped Tracks are Source-managed. Move an Item to another Track and confirm Keep as Local before editing it independently.")
  if update_review.reference_warning then
    local changed
    changed, update_reference_override = ImGui.Checkbox(ctx, "Allow Reference revision difference##update", update_reference_override)
  end
  if #update_review.unmapped_lanes > 0 then
    ImGui.Separator(ctx)
    ImGui.Text(ctx, string.format(
      "Delivery Lanes to map (%d)",
      #update_review.unmapped_lanes
    ))
    if ImGui.Button(ctx, "Create All Under Selected Folder Track##update") then
      local selected = adapter.selected_tracks()
      if #selected == 1 then
        for _, lane in ipairs(update_review.unmapped_lanes) do
          update_lanes[lane.lane_id] = {
            kind = "create",
            parent_track_ref = selected[1],
          }
        end
      else notify("Select exactly one Folder Track.", true) end
    end
  end
  for _, lane in ipairs(update_review.unmapped_lanes) do draw_mapping(lane, update_lanes, "update-") end
  draw_bound_lanes()
  if update_review.blocker_count == 0 and ImGui.Button(ctx, "Synchronize Delivery") then
    local result, err = delivery_update.apply(update_review, adapter, {
      lane_mappings = update_lanes,
      lane_rebindings = update_rebindings,
      allow_reference_revision_mismatch = update_reference_override,
    })
    if result then
      notify(string.format(
        "Synchronized Delivery r%d: replaced %d Item(s) with %d Source Item(s).",
        update_review.target_revision,
        result.deleted_items,
        result.new_items
      ))
      update_review = nil
    else notify(err, true) end
  end
end

local function confirm_moved_items()
  local change_count = adapter.project_change_count()
  if change_count == moved_items_change_count then return end
  moved_items_change_count = change_count
  local moved = delivery_update.moved_instances(adapter)
  if #moved == 0 then return end
  local confirmed = reaper.ShowMessageBox(
    string.format(
      "%d synchronized Item(s) were moved out of their mapped Track.\n\n" ..
      "Keep them as local Master content? They will no longer be updated from the Source.\n\n" ..
      "Choose No to keep them Source-managed; the next synchronization will replace them.",
      #moved
    ),
    "Keep Moved Items as Local",
    4
  ) == 6
  if confirmed then
    local result, err = delivery_update.detach_many(adapter, moved)
    notify(result and string.format("Kept %d moved Item(s) as local content.", result.detached) or err, not result)
    moved_items_change_count = adapter.project_change_count()
  end
end

local function draw_master(state)
  confirm_moved_items()
  ImGui.Text(ctx, "Project Type: Master")
  ImGui.TextWrapped(ctx, "Project ID: " .. short_id(state.project_id))
  ImGui.TextWrapped(ctx, "Project: " .. state.path)
  ImGui.Separator(ctx)
  draw_reference_publish(state)
  ImGui.Separator(ctx)
  ImGui.Text(ctx, "Delivery Subscriptions")
  if ImGui.Button(ctx, "Add Delivery") then begin_import() end
  local entries = subscriptions()
  for _, entry in ipairs(entries) do
    ImGui.TextWrapped(ctx, string.format(
      "%s (%s) | Handled Delivery Revision %d",
      subscription_name(entry),
      short_id(entry.sourceProjectId),
      entry.acceptedDeliveryRevision or 0
    ))
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Synchronize Delivery...##" .. entry.sourceProjectId) then begin_update(entry.sourceProjectId) end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Remove Subscription##" .. entry.sourceProjectId) then
      local result, err = delivery_import.remove_subscription(adapter, entry.sourceProjectId)
      notify(result and "Delivery subscription removed; Tracks and Items were kept." or err, not result)
    end
  end
  draw_import()
  draw_update()
end

local function draw()
  local project_token = adapter.project_token()
  if project_token ~= active_project_token then
    reset_transient_state()
    active_project_token = project_token
    notify("Current REAPER project changed; cached reviews and decisions were cleared.")
  end
  ImGui.SetNextWindowSize(ctx, 1040, 720, ImGui.Cond_FirstUseEver)
  ui:push_theme()
  local visible
  visible, window_open = ImGui.Begin(ctx, "ReaProjectLink", window_open)
  if visible then
    ui:push_font(ui.font_body)
    local state = project_service.project_state(adapter)
    if not state.project_type or state.project_type == "" then
      ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 24, 20)
      draw_error_banner()
      draw_lock()
      draw_uninitialized(state)
      ImGui.PopStyleVar(ctx)
    elseif state.project_type == constants.PROJECT_TYPES.source then draw_source(state)
    elseif state.project_type == constants.PROJECT_TYPES.master then
      ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 24, 20)
      draw_error_banner()
      draw_lock()
      draw_master(state)
      ImGui.PopStyleVar(ctx)
    else ImGui.TextWrapped(ctx, "Unsupported Project Type: " .. tostring(state.project_type)) end
    ui:pop_font()
    -- ReaImGui only accepts End() when Begin() returned true, unlike Dear ImGui.
    ImGui.End(ctx)
  end
  ui:pop_theme()
end

local function loop()
  local ok, err = xpcall(draw, debug.traceback)
  if smoke_path then
    smoke_frame_count = smoke_frame_count + 1
    if not ok or smoke_frame_count >= 3 then
      local file = io.open(smoke_path, "w")
      if file then
        file:write(ok and "PASS ReaProjectLink UI frames\n" or "FAIL\n" .. tostring(err) .. "\n")
        file:close()
      end
      window_open = false
      reaper.Main_OnCommand(40004, 0)
      return
    end
  end
  if not ok then
    reaper.ShowConsoleMsg("ReaProjectLink error:\n" .. tostring(err) .. "\n")
    reaper.ShowMessageBox(tostring(err), "ReaProjectLink error", 0)
    return
  end
  if window_open then reaper.defer(loop) end
end

reaper.atexit(function()
  if ctx and reaper.ImGui_DestroyContext then reaper.ImGui_DestroyContext(ctx) end
  ctx = nil
end)
reaper.defer(loop)
