local view_models = require("reaprojectlink.ui.view_models")

local function equal(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
  end
end

local function source_input(overrides)
  local input = {
    subscribed = true,
    synchronized = 4,
    check = { state = "done", latest = 4 },
    track_count = 3,
    item_count = 18,
    delivery_revision = 12,
  }
  for key, value in pairs(overrides or {}) do input[key] = value end
  return input
end

local function master_input(overrides)
  local input = {
    track_count = 1,
    marker_count = 2,
    reference_revision = 8,
    rows = {
      { id = "a", name = "A", accepted = 3, unmapped_count = 0,
        check = { state = "done", latest = 3, reviewed_reference = 8 } },
    },
  }
  for key, value in pairs(overrides or {}) do input[key] = value end
  return input
end

local tests = {}

function tests.formats_project_and_subscription_names()
  equal(view_models.project_name("C:/show/SFX_Main.RPP"), "SFX_Main", "project name")
  equal(view_models.project_name(""), "Untitled project", "unsaved project")
  equal(view_models.subscription_name({ sourceProjectName = "Dialogue" }), "Dialogue", "stored name")
  equal(view_models.subscription_name({ pointerPath = "C:/dx/_ReaProjectLink/DX/delivery.json" }),
    "DX", "name from package path")
  equal(view_models.subscription_name({}), "Unnamed Source", "no name")
end

function tests.formats_counts_and_check_age()
  equal(view_models.count(1, "item"), "1 item", "singular")
  equal(view_models.count(3, "new track"), "3 new tracks", "plural")
  equal(view_models.checked_text(nil), nil, "never checked")
  equal(view_models.checked_text(20), "Checked just now", "seconds")
  equal(view_models.checked_text(185), "Checked 3 min ago", "minutes")
  equal(view_models.checked_text(7300), "Checked 2 h ago", "hours")
  equal(view_models.blocked_summary(1, "publish"), "Fix 1 issue to publish", "one issue")
  equal(view_models.blocked_summary(2, "import"), "Fix 2 issues to import", "issues")
end

function tests.source_highlights_reference_until_it_is_current()
  local cases = {
    { { subscribed = false }, "unsubscribed", "reference" },
    { { check = { state = "unreachable" } }, "unreachable", "reference" },
    { { check = { state = "invalid", error = "bad" } }, "invalid", "reference" },
    { { media_error = "Media File Not Found" }, "blocked", "reference" },
    { { check = { state = "done", latest = 5 } }, "newer", "reference" },
    { { check = { state = "checking" } }, "checking", "delivery" },
    { {}, "current", "delivery" },
  }
  for _, case in ipairs(cases) do
    local cards = view_models.source_cards(source_input(case[1]))
    equal(cards.reference.state, case[2], "reference state")
    equal(cards.highlight, case[3], case[2] .. " highlight")
  end
end

function tests.source_reference_card_text_and_actions()
  local newer = view_models.source_cards(source_input({ check = { state = "done", latest = 5 } })).reference
  equal(newer.status, "Reference r5 available", "newer status")
  equal(newer.level, "warning", "newer level")
  equal(newer.rows[1][1], "Synchronized", "synchronized label")
  equal(newer.rows[1][2], "r4", "synchronized value")
  equal(newer.action.id, "review_update", "newer action")
  local unsubscribed = view_models.source_cards(source_input({ subscribed = false })).reference
  equal(unsubscribed.action.id, "choose_reference", "subscribe action")
  local unreachable = view_models.source_cards(source_input({ check = { state = "unreachable" } })).reference
  equal(unreachable.status, "Couldn't reach shared storage", "unreachable status")
  equal(unreachable.action.id, "retry", "retry action")
  local invalid = view_models.source_cards(source_input({ check = { state = "invalid", error = "bad" } })).reference
  equal(invalid.note, "bad", "invalid detail")
  local blocked = view_models.source_cards(source_input({ media_error = "Media File Not Found" })).reference
  equal(blocked.status, "Media File Not Found", "media status")
  equal(blocked.action.id, "review_update", "media action")
  local checking = view_models.source_cards(source_input({ check = { state = "checking" } })).reference
  equal(checking.status, "Checking...", "checking status")
  equal(checking.action, nil, "no action while checking")
  local current = view_models.source_cards(source_input()).reference
  equal(current.status, "Up to date", "current status")
  equal(current.rows[1][2], "r4", "current revision")
  equal(current.action, nil, "no action when current")
end

function tests.source_delivery_card_states()
  local empty = view_models.source_cards(source_input({ track_count = 0 })).delivery
  equal(empty.status, "No delivery tracks", "no tracks")
  equal(empty.action.id, "register_tracks", "register action")
  local never = view_models.source_cards(source_input({ delivery_revision = 0 })).delivery
  equal(never.status, "Not published yet", "never published")
  local published = view_models.source_cards(source_input()).delivery
  equal(published.status, "Last published r12", "published")
  equal(published.rows[1][2], "3", "track count")
  equal(published.rows[2][2], "18", "item count")
  equal(published.action.id, "review_publish", "publish action")
  equal(published.note, nil, "no pending note")
  local pending = view_models.source_cards(source_input({ check = { state = "done", latest = 5 } })).delivery
  equal(pending.note, "Will record Reference r4", "pending note")
  local unsynchronized = view_models.source_cards(source_input({
    synchronized = 0, check = { state = "done", latest = 5 },
  })).delivery
  equal(unsynchronized.note, nil, "no note without a synchronized revision")
end

function tests.master_highlight_priority()
  equal(view_models.master_cards(master_input({ track_count = 0 })).highlight, "reference", "no tracks")
  equal(view_models.master_cards(master_input({ reference_revision = 0 })).highlight, "reference", "unpublished")
  equal(view_models.master_cards(master_input({ rows = {} })).highlight, "deliveries", "no subscriptions")
  local newer = view_models.master_cards(master_input({ rows = {
    { id = "a", name = "A", accepted = 3, unmapped_count = 0,
      check = { state = "done", latest = 4, reviewed_reference = 8 } },
  } }))
  equal(newer.highlight, "deliveries", "newer delivery")
  local current = view_models.master_cards(master_input())
  equal(current.highlight, nil, "nothing to do")
  equal(current.all_current, true, "all up to date")
  equal(current.rows[1].id, "a", "row id kept")
  equal(current.rows[1].name, "A", "row name kept")
  local checking = view_models.master_cards(master_input({ rows = {
    { id = "a", name = "A", accepted = 3, unmapped_count = 0 },
  } }))
  equal(checking.all_current, false, "checking is not up to date")
end

function tests.master_reference_card_states()
  local unconfigured = view_models.master_cards(master_input({ track_count = 0 })).reference
  equal(unconfigured.status, "No reference tracks", "unconfigured")
  equal(unconfigured.action.id, "register_tracks", "register action")
  local unpublished = view_models.master_cards(master_input({ reference_revision = 0 })).reference
  equal(unpublished.status, "Not published yet", "unpublished")
  equal(unpublished.action.id, "review_publish", "publish action")
  local published = view_models.master_cards(master_input()).reference
  equal(published.status, "Published r8", "published")
  equal(published.level, "neutral", "published level")
  equal(published.attention, false, "published needs no attention")
  equal(published.rows[2][2], "2", "marker count")
  local empty = view_models.master_cards(master_input({ rows = {} })).deliveries_empty
  equal(empty.action.id, "add_delivery", "add action")
end

function tests.delivery_row_priority()
  local function row(check, unmapped)
    return view_models.delivery_row({ accepted = 3, unmapped_count = unmapped or 0, check = check }, 8)
  end
  local unreachable = row({ state = "unreachable" }, 2)
  equal(unreachable.state, "unreachable", "unreachable first")
  equal(unreachable.action.id, "retry", "retry action")
  equal(row({ state = "invalid", error = "bad" }).note, "bad", "invalid detail")
  local newer = row({ state = "done", latest = 4, reviewed_reference = 7 }, 2)
  equal(newer.state, "newer", "newer before unmapped")
  equal(newer.status, "r4 available · have r3", "newer status")
  equal(newer.action.id, "sync", "sync action")
  local unmapped = row({ state = "done", latest = 3, reviewed_reference = 7 }, 2)
  equal(unmapped.state, "unmapped", "unmapped before older reference")
  equal(unmapped.status, "2 lanes not imported", "unmapped status")
  equal(unmapped.action.id, "map_lanes", "map action")
  local older = row({ state = "done", latest = 3, reviewed_reference = 7 })
  equal(older.state, "older_reference", "older reference")
  equal(older.status, "Made against Reference r7", "older status")
  equal(older.action, nil, "older has no action")
  equal(row({ state = "done", latest = 3, reviewed_reference = 8 }).status, "Up to date · r3", "current")
  equal(row(nil).status, "Checking...", "not checked yet")
end

function tests.lane_mapping_options_and_labels()
  local lane = { lane_id = "a", clips = { {}, {} },
    suggestions = { { display_name = "DX Main", track_ref = "track-1" } } }
  local options = view_models.lane_mapping_options(lane)
  equal(options[1].header, "Suggested", "suggestion header")
  equal(options[2].label, "DX Main", "suggestion first")
  local ids = {}
  for _, option in ipairs(options) do
    if option.id then table.insert(ids, option.id) end
  end
  equal(table.concat(ids, ","), "suggestion,create,selected,unmapped", "option order")
  equal(view_models.lane_mapping_options({ suggestions = {} })[1].id, "create", "no header without suggestions")

  local mapping = view_models.mapping_from_option(options[2], {})
  equal(mapping.kind, "existing", "suggestion maps to existing")
  equal(mapping.track_ref, "track-1", "suggested track")
  local none, err = view_models.mapping_from_option({ id = "selected" }, {})
  equal(none, nil, "no selection")
  equal(err, "Select exactly one track in REAPER first.", "selection error")
  equal(view_models.mapping_from_option({ id = "selected" }, { "t" }).track_ref, "t", "selected track")
  equal(view_models.mapping_from_option({ id = "create" }, {}).kind, "create", "create")
  equal(view_models.mapping_from_option({ id = "unmapped" }, {}).kind, "unmapped", "skip")

  equal(view_models.lane_mapping_label(nil, "create", tostring), "New track", "import default")
  equal(view_models.lane_mapping_label(nil, "unmapped", tostring), "Don't import", "update default")
  equal(view_models.lane_mapping_label({ kind = "existing", track_ref = "Bus" }, "create", tostring),
    "Bus", "existing track name")
end

function tests.mapping_summary_and_parent()
  local lanes = {
    { lane_id = "a", clips = { {}, {} } },
    { lane_id = "b", clips = { {} } },
    { lane_id = "c", clips = { {} } },
  }
  local mappings = { b = { kind = "existing", track_ref = "t" }, c = { kind = "unmapped" } }
  equal(view_models.mapping_summary(lanes, mappings, "create"), "1 new track · 3 items", "summary")
  local parented = view_models.with_parent({
    a = { kind = "create" },
    b = { kind = "existing", track_ref = "t" },
  }, "folder")
  equal(parented.a.parent_track_ref, "folder", "new track parent")
  equal(parented.b.parent_track_ref, nil, "existing track untouched")
end

function tests.reference_declaration_options()
  local options = view_models.reference_declaration_options(5, 4)
  equal(#options, 2, "two choices")
  equal(options[1].id, 5, "synchronized first")
  equal(options[1].label, "r5 (synced)", "synchronized label")
  equal(options[2].label, "r4", "previous label")
  equal(#view_models.reference_declaration_options(5, 5), 1, "same revision")
  equal(#view_models.reference_declaration_options(5, 0), 1, "no previous declaration")
end

local passed = 0
for name, test in pairs(tests) do
  local ok, err = pcall(test)
  if not ok then error(name .. ": " .. tostring(err)) end
  passed = passed + 1
end

return passed
