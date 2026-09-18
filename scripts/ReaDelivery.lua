-- @description ReaDelivery
-- @version 0.1.0-dev
-- @author ReaDelivery contributors

local source = debug.getinfo(1, "S").source:sub(2)
local scripts_dir = source:match("^(.*)[/\\]")
local root = scripts_dir and scripts_dir:match("^(.*)[/\\]scripts$")
if not root then
  reaper.ShowMessageBox("Could not resolve the repository path.", "ReaDelivery", 0)
  return
end
package.path = root .. "/src/?.lua;" .. root .. "/src/?/init.lua;" .. package.path
if not reaper.ImGui_GetBuiltinPath then
  reaper.ShowMessageBox("Install ReaImGui through ReaPack and restart REAPER.", "ReaDelivery", 0)
  return
end
package.path = reaper.ImGui_GetBuiltinPath() .. "/?.lua;" .. package.path
local ok_imgui, ImGui = pcall(function() return require("imgui")("0.9") end)
if not ok_imgui then
  reaper.ShowMessageBox("Could not load ReaImGui:\n" .. tostring(ImGui), "ReaDelivery", 0)
  return
end

local constants = require("readelivery.constants")
local filesystem = require("readelivery.filesystem")
local json = require("readelivery.json")
local mix_import = require("readelivery.mix_import")
local mix_update = require("readelivery.mix_update")
local picture_publish = require("readelivery.picture_publish").create()
local picture_subscription = require("readelivery.picture_subscription")
local adapter = require("readelivery.reaper_adapter")
local source_publish = require("readelivery.source_publish").create()
local source_service = require("readelivery.source_service")

local ctx = ImGui.CreateContext("ReaDelivery")
local fs = filesystem.create(reaper)
local smoke_path = os.getenv("READELIVERY_UI_SMOKE_RESULT")
local window_open = true
local message, message_is_error
local source_picture, source_review, picture_review, import_review, update_review
local source_decisions, import_mappings = {}, {}
local source_save_as_decision
local update_decisions, update_additions, update_lanes = {}, {}, {}
local publish_anyway, import_picture_override, update_picture_override = false, false, false
local picture_publish_anyway = false
local show_unchanged = false
local lock_info, lock_package_root

local function notify(value, is_error)
  message, message_is_error = value, is_error or false
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

local function draw_notice()
  if not message then return end
  if message_is_error then ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xff6b6bff) end
  ImGui.TextWrapped(ctx, message)
  if message_is_error then ImGui.PopStyleColor(ctx) end
  ImGui.Separator(ctx)
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
  if ImGui.Button(ctx, "Remove Observed Stale Lock") then
    local removed, err = fs.remove_lock(lock_package_root, lock_info.token)
    if removed then
      lock_info, lock_package_root = nil, nil
      notify("Observed Publish lock removed. Retry with a fresh review.")
    else notify(err, true) end
  end
  ImGui.Separator(ctx)
end

local function draw_uninitialized(state)
  ImGui.TextWrapped(ctx, "Initialize this saved .rpp as one ReaDelivery project mode.")
  if ImGui.Button(ctx, "Initialize Source Project") then
    local result, err = source_service.initialize_source(adapter)
    notify(result and "Source Project initialized." or err, not result)
  end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Initialize Mix Project") then
    local result, err = source_service.initialize_mix(adapter)
    notify(result and "Mix Project initialized." or err, not result)
  end
  if state.path == "" then ImGui.TextWrapped(ctx, "Save this project before initialization.") end
end

local function check_source_picture()
  local status, err = picture_subscription.check(adapter, fs)
  source_picture = status
  notify(status and "Picture subscription checked." or err, not status)
end

local function draw_source_picture(state)
  ImGui.Text(ctx, "Picture Subscription")
  if ImGui.Button(ctx, "Select picture.json") then
    local path = choose_json("Select published picture.json")
    if path then
      local result, err = picture_subscription.subscribe(adapter, fs, path)
      if result then check_source_picture() else notify(err, true) end
    end
  end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Check Picture Update") then check_source_picture() end
  if not source_picture then
    if not state.picture_manifest_path or state.picture_manifest_path == "" then
      ImGui.TextWrapped(ctx, "No Picture subscription yet.")
    else
      ImGui.TextWrapped(ctx, "Subscribed: " .. state.picture_manifest_path)
      ImGui.TextWrapped(ctx, string.format(
        "Synchronized r%d | reviewed r%d | Check Picture Update for the latest revision",
        state.synchronized_picture_revision,
        state.reviewed_picture_revision
      ))
    end
    return
  end
  ImGui.TextWrapped(ctx, string.format(
    "Picture %s | latest r%d | synchronized r%d | reviewed r%d",
    source_picture.picture_id,
    source_picture.latest_revision,
    source_picture.synchronized_revision,
    source_picture.reviewed_revision
  ))
  if source_picture.video_error then ImGui.TextWrapped(ctx, "Blocked: " .. source_picture.video_error) end
  if source_picture.available and
      source_picture.synchronized_revision ~= source_picture.latest_revision and
      ImGui.Button(ctx, "Synchronize Picture") then
    local result, err = picture_subscription.synchronize(adapter, source_picture)
    if result then check_source_picture() else notify(err, true) end
  end
  if source_picture.synchronized_revision == source_picture.latest_revision and
      source_picture.reviewed_revision ~= source_picture.latest_revision and
      ImGui.Button(ctx, "Mark Picture Reviewed") then
    local result, err = picture_subscription.mark_reviewed(adapter, source_picture)
    if result then check_source_picture() else notify(err, true) end
  end
end

local function refresh_source_review()
  local review, err = source_publish.review(adapter, fs, {
    identity_decisions = source_decisions,
    publish_anyway = publish_anyway,
    save_as_decision = source_save_as_decision,
  })
  source_review = review
  notify(review and "Publish Review refreshed." or err, not review)
end

local function draw_source_review()
  if not source_review then return end
  ImGui.Separator(ctx)
  ImGui.Text(ctx, string.format(
    "Publish r%d | Picture r%s | %d blocker(s)",
    source_review.publish_revision,
    tostring(source_review.reviewed_picture_revision or "none"),
    source_review.blocker_count
  ))
  ImGui.TextWrapped(ctx, "Output: " .. source_review.package_root)
  if source_review.picture_blocker then ImGui.TextWrapped(ctx, source_review.picture_blocker) end
  if source_review.save_as_blocker then
    ImGui.TextWrapped(ctx, source_review.save_as_blocker)
    if ImGui.Button(ctx, "Continue Logical Source") then
      source_save_as_decision = "continue"
      refresh_source_review()
    end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Start New Source") then
      source_save_as_decision = "new"
      source_decisions = {}
      refresh_source_review()
    end
  end
  local changed
  changed, publish_anyway = ImGui.Checkbox(ctx, "Publish Anyway for detected FX", publish_anyway)
  if changed then refresh_source_review() end
  changed, show_unchanged = ImGui.Checkbox(ctx, "Show Unchanged Clips", show_unchanged)
  for _, lane in ipairs(source_review.lanes) do
    if ImGui.TreeNode(ctx, lane.display_name .. "##" .. lane.lane_id) then
      if lane.fx_blocked then ImGui.TextWrapped(ctx, "Blocked: Delivery Track has FX.") end
      for _, row in ipairs(lane.clips) do
        if row.status ~= "Unchanged" or show_unchanged then
          ImGui.TextWrapped(ctx, string.format("[%s] %s", row.status, row.display_name or "(unnamed)"))
        end
        if row.status == "Needs Decision" then
          local item_key = tostring(row.clip.item_ref)
          if ImGui.Button(ctx, "Create New Clip##" .. item_key) then
            source_decisions[row.clip.item_ref] = { kind = "new" }
            refresh_source_review()
          end
          for _, candidate in ipairs(row.suggestions or {}) do
            if ImGui.Button(ctx, "Link as revision of " .. (candidate.display_name or candidate.clip_id) .. "##" .. candidate.clip_id) then
              source_decisions[row.clip.item_ref] = { kind = "link", clip_id = candidate.clip_id }
              refresh_source_review()
            end
            ImGui.SameLine(ctx)
            ImGui.TextWrapped(ctx, table.concat(candidate.reasons, ", "))
          end
        end
        if row.status ~= "Unchanged" or show_unchanged then
          for _, blocker in ipairs(row.blockers or {}) do ImGui.TextWrapped(ctx, "  " .. blocker) end
        end
      end
      ImGui.TreePop(ctx)
    end
  end
  for _, row in ipairs(source_review.retired or {}) do
    ImGui.TextWrapped(ctx, "[Retired] " .. (row.display_name or row.clip_id))
  end
  if source_review.blocker_count == 0 and ImGui.Button(ctx, "Save & Publish") then
    local result, err = source_publish.publish(source_review, adapter, fs, metadata())
    if result then
      notify("Published Delivery revision " .. result.publish_revision .. ".")
      source_review, source_decisions, source_save_as_decision = nil, {}, nil
    else notify(err, true); inspect_lock(source_review.package_root) end
  end
end

local function draw_source(state)
  ImGui.Text(ctx, "Mode: Source")
  ImGui.TextWrapped(ctx, "Source ID: " .. (state.source_project_id or "assigned on first Publish"))
  ImGui.TextWrapped(ctx, "Project: " .. state.path)
  ImGui.Separator(ctx)
  draw_source_picture(state)
  ImGui.Separator(ctx)
  ImGui.Text(ctx, "Delivery Tracks")
  if ImGui.Button(ctx, "Register Selected Track(s)") then
    local result, err = source_service.register_selected_tracks(adapter)
    notify(result and string.format("Registered %d Track(s).", result.added) or err, not result)
  end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Remove Selected Track(s)") then
    local result, err = source_service.unregister_selected_tracks(adapter)
    notify(result and string.format("Removed %d Track(s).", result.removed) or err, not result)
  end
  if ImGui.Button(ctx, "Open Publish Review") then refresh_source_review() end
  draw_source_review()
end

local function refresh_picture_review()
  local review, err = picture_publish.review(adapter, fs, {
    publish_anyway = picture_publish_anyway,
  })
  picture_review = review
  notify(review and "Picture Publish Review ready." or err, not review)
end

local function draw_picture_publish(state)
  ImGui.Text(ctx, "Authoritative Picture")
  if state.picture_revision > 0 then
    ImGui.TextWrapped(ctx, string.format(
      "Published Picture %s | r%d",
      state.picture_id,
      state.picture_revision
    ))
  else
    ImGui.TextWrapped(ctx, "No Picture published yet.")
  end
  if ImGui.Button(ctx, "Review Selected Picture Item") then refresh_picture_review() end
  if not picture_review then return end
  ImGui.TextWrapped(ctx, string.format(
    "%s | %d samples",
    picture_review.video_file,
    picture_review.duration_samples
  ))
  if picture_review.unchanged then
    ImGui.TextWrapped(ctx, string.format(
      "This Picture is identical to published revision r%d.",
      picture_review.base_revision
    ))
    local changed
    changed, picture_publish_anyway = ImGui.Checkbox(
      ctx,
      "Publish Anyway for an unchanged Picture",
      picture_publish_anyway
    )
    if changed then refresh_picture_review() end
  end
  if not picture_review.unchanged_blocker then
    ImGui.TextWrapped(ctx, string.format(
      "Will publish as r%d.",
      picture_review.picture_revision
    ))
    if ImGui.Button(ctx, "Save & Publish Picture") then
      local result, err = picture_publish.publish(picture_review, adapter, fs, metadata())
      if result then
        notify("Published Picture revision " .. result.picture_revision .. ".")
        picture_review, picture_publish_anyway = nil, false
      else notify(err, true); inspect_lock(picture_review.package_root) end
    end
  end
end

local function draw_mapping(lane, mappings, prefix)
  local mapping = mappings[lane.lane_id]
  ImGui.Text(ctx, lane.display_name .. " (" .. #lane.clips .. " Clips)")
  if ImGui.Button(ctx, "Create Track##" .. prefix .. lane.lane_id) then
    mappings[lane.lane_id] = { kind = "create" }
  end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Skip##" .. prefix .. lane.lane_id) then
    mappings[lane.lane_id] = { kind = "skip" }
  end
  for _, suggestion in ipairs(lane.suggestions or {}) do
    if ImGui.Button(ctx, "Use " .. suggestion.display_name .. "##" .. prefix .. suggestion.track_guid) then
      mappings[lane.lane_id] = { kind = "existing", track_ref = suggestion.track_ref }
    end
  end
  if mapping then ImGui.Text(ctx, "  Mapping: " .. mapping.kind) end
end

local function begin_import()
  local path = choose_json("Select Source delivery.json")
  if not path then return end
  local review, err = mix_import.review(adapter, fs, path)
  import_review, import_mappings = review, {}
  if review then
    for _, lane in ipairs(review.lanes) do import_mappings[lane.lane_id] = { kind = "create" } end
    notify("First Import Review ready.")
  else notify(err, true) end
end

local function draw_import()
  if not import_review then return end
  ImGui.TextWrapped(ctx, string.format(
    "%s | Publish r%d | reviewed Picture r%d",
    import_review.snapshot.sourceProjectName,
    import_review.pointer.latestPublishRevision,
    import_review.snapshot.picture.reviewedRevision
  ))
  if import_review.picture_error then ImGui.TextWrapped(ctx, "Blocked: " .. import_review.picture_error) end
  if import_review.picture_warning then
    local changed
    changed, import_picture_override = ImGui.Checkbox(ctx, "Allow Picture revision difference", import_picture_override)
  end
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
  if import_review.blocker_count == 0 and ImGui.Button(ctx, "Confirm Import") then
    local result, err = mix_import.apply(import_review, adapter, {
      mappings = import_mappings,
      allow_picture_revision_mismatch = import_picture_override,
    })
    if result then
      notify(string.format("Imported %d Item(s) on %d new Track(s).", result.created_items, result.created_tracks))
      import_review, import_mappings = nil, {}
    else notify(err, true) end
  end
end

local function subscriptions()
  local stored = adapter.get_project_value(constants.PROJECT_KEYS.source_subscriptions)
  if not stored or stored == "" then return {} end
  local ok, value = pcall(json.decode, stored)
  return ok and value or {}
end

local function begin_update(source_id)
  local review, err = mix_update.review(adapter, fs, source_id)
  update_review = review
  update_decisions, update_additions, update_lanes = {}, {}, {}
  if not review then notify(err, true); return end
  for _, row in ipairs(review.instances) do
    update_decisions[row.decision_key] = { media_choice = row.plan.media.choice, field_choices = {} }
  end
  for _, row in ipairs(review.additions) do update_additions[row.clip.clipId] = "import" end
  for _, lane in ipairs(review.unmapped_lanes) do update_lanes[lane.lane_id] = { kind = "skip" } end
  notify("Source Update Review ready.")
end

local function draw_update()
  if not update_review then return end
  ImGui.Text(ctx, "Update to Publish r" .. update_review.latest_revision)
  if update_review.picture_warning then
    local changed
    changed, update_picture_override = ImGui.Checkbox(ctx, "Allow Picture revision difference##update", update_picture_override)
  end
  for _, row in ipairs(update_review.instances) do
    local decision = update_decisions[row.decision_key]
    if ImGui.TreeNode(ctx, row.clip_id .. " / " .. row.instance_id .. "##" .. row.decision_key) then
      if row.plan.retired then ImGui.TextWrapped(ctx, "Retired upstream; the Item will not be deleted.")
      else
        if row.plan.media.pending then
          local accept = decision.media_choice == "accept_new_take"
          local changed
          changed, accept = ImGui.Checkbox(ctx, "Accept audio as new Take", accept)
          if changed then decision.media_choice = accept and "accept_new_take" or "skip" end
          if row.advanced_take_state and accept then
            changed, decision.replace_anyway = ImGui.Checkbox(
              ctx,
              "Replace Anyway despite advanced Take state",
              decision.replace_anyway or false
            )
          end
        end
        for field, plan in pairs(row.plan.fields) do
          if plan.kind ~= "unchanged" then
            local choice = decision.field_choices[field] or plan.choice
            if ImGui.Button(ctx, field .. ": " .. choice .. "##" .. row.decision_key .. field) then
              decision.field_choices[field] = choice == "keep_mix" and "use_source" or "keep_mix"
            end
          end
        end
      end
      ImGui.TreePop(ctx)
    end
  end
  for _, row in ipairs(update_review.additions) do
    local id = row.clip.clipId
    local include = update_additions[id] == "import"
    local changed
    changed, include = ImGui.Checkbox(ctx, "Import new Clip " .. (row.clip.displayName or id), include)
    if changed then update_additions[id] = include and "import" or "skip" end
  end
  if #update_review.unmapped_lanes > 0 and
      ImGui.Button(ctx, "Create New Lanes Under Selected Folder Track") then
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
  for _, lane in ipairs(update_review.unmapped_lanes) do draw_mapping(lane, update_lanes, "update-") end
  if update_review.blocker_count == 0 and ImGui.Button(ctx, "Apply Update") then
    local result, err = mix_update.apply(update_review, adapter, {
      instances = update_decisions,
      additions = update_additions,
      lane_mappings = update_lanes,
      allow_picture_revision_mismatch = update_picture_override,
    })
    if result then
      notify(string.format("Updated %d Instance(s), added %d Take(s) and %d Item(s).", result.updated_instances, result.new_takes, result.new_items))
      update_review = nil
    else notify(err, true) end
  end
end

local function detach_selected()
  local count = 0
  for _, item in ipairs(adapter.selected_items()) do
    if mix_update.detach(adapter, item) then count = count + 1 end
  end
  notify(string.format("Detached %d selected Item(s).", count))
end

local function draw_mix(state)
  ImGui.Text(ctx, "Mode: Mix")
  ImGui.TextWrapped(ctx, "Project: " .. state.path)
  ImGui.Separator(ctx)
  draw_picture_publish(state)
  ImGui.Separator(ctx)
  ImGui.Text(ctx, "Source Deliveries")
  if ImGui.Button(ctx, "Add Source delivery.json") then begin_import() end
  ImGui.SameLine(ctx)
  if ImGui.Button(ctx, "Detach Selected Instance(s)") then detach_selected() end
  for _, entry in ipairs(subscriptions()) do
    ImGui.TextWrapped(ctx, string.format("%s | accepted r%d", entry.sourceProjectId, entry.acceptedPublishRevision or 0))
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Check Update##" .. entry.sourceProjectId) then begin_update(entry.sourceProjectId) end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "Remove Subscription##" .. entry.sourceProjectId) then
      local result, err = mix_import.remove_subscription(adapter, entry.sourceProjectId)
      notify(result and "Source subscription removed; Tracks and Items were kept." or err, not result)
    end
  end
  draw_import()
  draw_update()
end

local function draw()
  ImGui.SetNextWindowSize(ctx, 820, 680, ImGui.Cond_FirstUseEver)
  local visible
  visible, window_open = ImGui.Begin(ctx, "ReaDelivery", window_open)
  if visible then
    draw_notice()
    draw_lock()
    local state = source_service.project_state(adapter)
    if not state.mode or state.mode == "" then draw_uninitialized(state)
    elseif state.mode == constants.PROJECT_MODES.source then draw_source(state)
    elseif state.mode == constants.PROJECT_MODES.mix then draw_mix(state)
    else ImGui.TextWrapped(ctx, "Unsupported project mode: " .. tostring(state.mode)) end
    -- ReaImGui only accepts End() when Begin() returned true, unlike Dear ImGui.
    ImGui.End(ctx)
  end
end

local function loop()
  local ok, err = xpcall(draw, debug.traceback)
  if smoke_path then
    local file = io.open(smoke_path, "w")
    if file then file:write(ok and "PASS ReaDelivery UI frame\n" or "FAIL\n" .. tostring(err) .. "\n"); file:close() end
    window_open = false
    reaper.Main_OnCommand(40004, 0)
    return
  end
  if not ok then
    reaper.ShowConsoleMsg("ReaDelivery error:\n" .. tostring(err) .. "\n")
    reaper.ShowMessageBox(tostring(err), "ReaDelivery error", 0)
    return
  end
  if window_open then reaper.defer(loop) end
end

reaper.atexit(function()
  if ctx and reaper.ImGui_DestroyContext then reaper.ImGui_DestroyContext(ctx) end
  ctx = nil
end)
reaper.defer(loop)
