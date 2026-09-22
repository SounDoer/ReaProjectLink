# UI Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the navigation-rail UI with the single-panel, card-based, two-theme UI described in `docs/superpowers/specs/2026-09-22-ui-redesign-design.md`, and move the Reference review declaration into Delivery Publish.

**Architecture:** Pure Lua modules (`theme` palette logic, `view_models`, `app_state`) hold every decision that can be unit-tested without ImGui. A thin `components` module draws the shared widgets with ReaImGui. One view module per screen composes components and calls the existing domain services. `ReaProjectLink.lua` becomes a bootstrap that creates the `ui/app.lua` shell.

**Tech Stack:** Lua 5.4 ReaScript, ReaImGui 0.9 compatibility API, the repository's dependency-free spec runner inside REAPER.

---

## Conventions for every task

- Read `AGENTS.md` and the spec before starting. Code, comments, and commits are English.
- Spec files follow the existing pattern: a `tests` table of functions, a runner loop at the bottom that returns the number of passed tests. Every new spec file must be added to `tests/specs.lua`.
- Commits use Conventional Commits and end with the attribution line:

```text
Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
```

### Run core tests (PowerShell)

REAPER must not be running (`Get-Process reaper` returns nothing). If it is, ask the user to close it.

```powershell
$root = (git rev-parse --show-toplevel); $reaper = "C:\Program Files\REAPER (x64)\reaper.exe"
Remove-Item "$root\tests\.last-result" -ErrorAction SilentlyContinue
$p = Start-Process $reaper -ArgumentList "-new","-nosplash","`"$root\tests\run_in_reaper.lua`"" -PassThru; $null = $p.WaitForExit(180000)
Get-Content "$root\tests\.last-result"
```

Pass: the file starts with `PASS`. Fail: it starts with `FAIL` followed by the failing test name and traceback.

### Run UI smoke (PowerShell)

```powershell
$root = (git rev-parse --show-toplevel); $reaper = "C:\Program Files\REAPER (x64)\reaper.exe"
Remove-Item "$root\tests\.last-ui-result" -ErrorAction SilentlyContinue
$env:REAPROJECTLINK_UI_SMOKE_RESULT = "$root\tests\.last-ui-result"
$p = Start-Process $reaper -ArgumentList "-new","-nosplash","`"$root\tests\run_ui_smoke.lua`"" -PassThru; $null = $p.WaitForExit(120000)
Remove-Item Env:REAPROJECTLINK_UI_SMOKE_RESULT; Get-Content "$root\tests\.last-ui-result"
```

## File map

| File | Status | Responsibility |
|---|---|---|
| `ReaProjectLink/lib/reaprojectlink/ui/theme.lua` | create | Palettes, Auto detection, preference storage, fonts, style push/pop |
| `ReaProjectLink/lib/reaprojectlink/ui/icons.lua` | create | DrawList icons |
| `ReaProjectLink/lib/reaprojectlink/ui/components.lua` | create | Shared widgets; no domain logic |
| `ReaProjectLink/lib/reaprojectlink/ui/view_models.lua` | create | Pure card/row/mapping/text decisions |
| `ReaProjectLink/lib/reaprojectlink/ui/app_state.lua` | create | View routing, toasts, check scheduling |
| `ReaProjectLink/lib/reaprojectlink/ui/workflow.lua` | create | Shared view helpers: dialogs, notices, publish messages, lock |
| `ReaProjectLink/lib/reaprojectlink/ui/checks.lua` | create | Runs pointer checks into `app_state` |
| `ReaProjectLink/lib/reaprojectlink/ui/app.lua` | create | Window shell and view dispatch |
| `ReaProjectLink/lib/reaprojectlink/ui/views/*.lua` | create | `card`, `header`, `setup`, `settings`, `source_main`, `master_main`, four Review views |
| `ReaProjectLink/lib/reaprojectlink/reference_subscription.lua` | modify | Add `peek`; remove `mark_reviewed` |
| `ReaProjectLink/lib/reaprojectlink/delivery_update.lua` | modify | Add `peek` |
| `ReaProjectLink/lib/reaprojectlink/delivery_publish.lua` | modify | Declared Reference revision |
| `ReaProjectLink/lib/reaprojectlink/reaper_adapter.lua` | modify | Add `select_items` |
| `ReaProjectLink/ReaProjectLink.lua` | rewrite | Bootstrap + shell + smoke driver |
| `ReaProjectLink/lib/reaprojectlink/ui.lua` | delete | Replaced by `ui/` |
| `tests/ui_theme_spec.lua`, `tests/ui_view_models_spec.lua`, `tests/ui_app_state_spec.lua`, `tests/ui_modules_spec.lua`, `tests/pointer_peek_spec.lua` | create | Unit specs |
| `tests/ui_smoke_scenarios.lua` | create | One UI frame per scenario |
| `tests/run_ui_smoke.lua`, `tests/specs.lua`, `tests/delivery_publish_spec.lua`, `tests/reference_subscription_spec.lua` | modify | |
| `docs/ui-spec.md`, `docs/decisions.md`, `docs/architecture.md`, `docs/ui-implementation-plan.md`, spec file | modify | Documentation |

---

### Task 1: Theme palette logic

**Files:**
- Create: `ReaProjectLink/lib/reaprojectlink/ui/theme.lua`
- Create: `tests/ui_theme_spec.lua`
- Modify: `tests/specs.lua`

- [ ] **Step 1: Write the failing spec**

Create `tests/ui_theme_spec.lua`:

```lua
local theme = require("reaprojectlink.ui.theme")

local function equal(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
  end
end

local tests = {}

function tests.palettes_share_every_token()
  local count = 0
  for key in pairs(theme.PALETTES.light) do
    count = count + 1
    assert(theme.PALETTES.dark[key], "dark palette is missing " .. key)
  end
  for key in pairs(theme.PALETTES.dark) do
    assert(theme.PALETTES.light[key], "light palette is missing " .. key)
  end
  equal(count, 14, "token count")
end

function tests.resolves_explicit_and_automatic_modes()
  equal(theme.resolve("light", nil), "light", "explicit light")
  equal(theme.resolve("dark", { 255, 255, 255 }), "dark", "explicit dark wins")
  equal(theme.resolve("auto", { 240, 240, 240 }), "light", "bright REAPER theme")
  equal(theme.resolve("auto", { 30, 30, 30 }), "dark", "dark REAPER theme")
  equal(theme.resolve("auto", nil), "dark", "unknown REAPER theme")
end

function tests.mixes_channels_and_keeps_alpha()
  equal(theme.mix(0x000000ff, 0xffffffff, 0.5), 0x808080ff, "midpoint")
  equal(theme.mix(0x102030ff, 0x102030ff, 0.3), 0x102030ff, "same color")
  equal(theme.mix(0x00000080, 0xffffffff, 1), 0xffffff80, "first alpha kept")
end

function tests.colors_add_derived_tokens()
  local colors = theme.colors("light")
  equal(colors.accent, theme.PALETTES.light.accent, "base token copied")
  assert(colors.accent_hover and colors.accent_active and colors.surface_active,
    "derived tokens exist")
  equal(theme.colors("unknown").bg, theme.PALETTES.dark.bg, "unknown mode falls back to dark")
end

function tests.stores_the_preference_globally()
  local stored = {}
  local reaper_api = {}
  function reaper_api.GetExtState(section, key) return stored[section .. "/" .. key] or "" end
  function reaper_api.SetExtState(section, key, value, persist)
    assert(persist, "preference persists across sessions")
    stored[section .. "/" .. key] = value
  end
  equal(theme.load_preference(reaper_api), "auto", "default preference")
  stored["ReaProjectLink/theme"] = "purple"
  equal(theme.load_preference(reaper_api), "auto", "invalid preference")
  theme.save_preference(reaper_api, "light")
  equal(theme.load_preference(reaper_api), "light", "saved preference")
end

function tests.reads_the_reaper_background()
  local reaper_api = {}
  function reaper_api.GetThemeColor() return -1 end
  function reaper_api.ColorFromNative() error("not called for a missing color") end
  equal(theme.reaper_background(reaper_api), nil, "missing theme color")
  function reaper_api.GetThemeColor(name)
    equal(name, "col_main_bg2", "theme color name")
    return 1234
  end
  function reaper_api.ColorFromNative(value)
    equal(value, 1234, "native color")
    return 10, 20, 30
  end
  local rgb = theme.reaper_background(reaper_api)
  equal(rgb[1] .. "," .. rgb[2] .. "," .. rgb[3], "10,20,30", "rgb")
end

local passed = 0
for name, test in pairs(tests) do
  local ok, err = pcall(test)
  if not ok then error(name .. ": " .. tostring(err)) end
  passed = passed + 1
end

return passed
```

Append `"ui_theme_spec.lua",` as the last entry of the list in `tests/specs.lua`.

- [ ] **Step 2: Run core tests to verify the failure**

Run: **Run core tests**.
Expected: `FAIL` with `module 'reaprojectlink.ui.theme' not found`.

- [ ] **Step 3: Implement the theme module**

Create `ReaProjectLink/lib/reaprojectlink/ui/theme.lua`:

```lua
local M = {}

M.PALETTES = {
  light = {
    bg = 0xf3f4f6ff, surface = 0xffffffff, surface_hover = 0xeef0f3ff,
    border = 0xdadde2ff, text = 0x1d2025ff, muted = 0x5f6670ff,
    accent = 0x2f6fe0ff, on_accent = 0xffffffff, accent_bg = 0xe4edfcff,
    ready = 0x1f8a63ff, warning = 0xa86a0cff, warning_bg = 0xfdf1dcff,
    blocked = 0xc93c46ff, blocked_bg = 0xfbe5e6ff,
  },
  dark = {
    bg = 0x16181cff, surface = 0x1f2227ff, surface_hover = 0x272b31ff,
    border = 0x30343cff, text = 0xe6e8ebff, muted = 0x9aa0a8ff,
    accent = 0x4c8dffff, on_accent = 0x0b1220ff, accent_bg = 0x1c2a44ff,
    ready = 0x3fbf8fff, warning = 0xe0a84aff, warning_bg = 0x3a2f1cff,
    blocked = 0xeb5f68ff, blocked_bg = 0x3b2224ff,
  },
}

M.PREFERENCES = { "auto", "light", "dark" }
M.EXT_SECTION = "ReaProjectLink"
M.EXT_KEY = "theme"

local function channels(color)
  return (color >> 24) & 0xff, (color >> 16) & 0xff, (color >> 8) & 0xff, color & 0xff
end

-- Blends RGB toward `b`; alpha always comes from `a`.
function M.mix(a, b, t)
  local ar, ag, ab, aa = channels(a)
  local br, bg, bb = channels(b)
  local function lerp(x, y) return math.floor(x + (y - x) * t + 0.5) end
  return (lerp(ar, br) << 24) | (lerp(ag, bg) << 16) | (lerp(ab, bb) << 8) | aa
end

function M.luminance(r, g, b)
  return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255
end

function M.resolve(preference, background)
  if preference == "light" or preference == "dark" then return preference end
  if background and M.luminance(background[1], background[2], background[3]) >= 0.5 then
    return "light"
  end
  return "dark"
end

function M.colors(mode)
  local base = M.PALETTES[mode] or M.PALETTES.dark
  local colors = {}
  for key, value in pairs(base) do colors[key] = value end
  colors.accent_hover = M.mix(base.accent, base.text, 0.15)
  colors.accent_active = M.mix(base.accent, base.bg, 0.15)
  colors.surface_active = M.mix(base.surface_hover, base.text, 0.08)
  return colors
end

function M.load_preference(reaper_api)
  local value = reaper_api.GetExtState(M.EXT_SECTION, M.EXT_KEY)
  for _, name in ipairs(M.PREFERENCES) do
    if name == value then return value end
  end
  return "auto"
end

function M.save_preference(reaper_api, value)
  reaper_api.SetExtState(M.EXT_SECTION, M.EXT_KEY, value, true)
end

function M.reaper_background(reaper_api)
  if not reaper_api.GetThemeColor then return nil end
  local native = reaper_api.GetThemeColor("col_main_bg2", 0)
  if not native or native < 0 then return nil end
  local r, g, b = reaper_api.ColorFromNative(native)
  return { r, g, b }
end

function M.create(ImGui, ctx, reaper_api)
  local function font(size, bold)
    local value = ImGui.CreateFont("sans-serif", size, bold and ImGui.FontFlags_Bold or nil)
    ImGui.Attach(ctx, value)
    return value
  end

  local self = {
    fonts = {
      title = font(16, true),
      heading = font(14, true),
      body = font(13),
      small = font(12),
    },
    preference = M.load_preference(reaper_api),
    mode = "dark",
  }
  self.colors = M.colors(self.mode)

  function self:refresh()
    local mode = M.resolve(self.preference, M.reaper_background(reaper_api))
    if mode ~= self.mode then
      self.mode = mode
      self.colors = M.colors(mode)
    end
  end

  function self:set_preference(value)
    self.preference = value
    M.save_preference(reaper_api, value)
    self:refresh()
  end

  -- Used by the UI smoke test: changes the mode without touching ExtState.
  function self:use(value)
    self.preference = value
    self:refresh()
  end

  local pushed_colors, pushed_vars = 0, 0

  function self:push()
    local c = self.colors
    local colors = {
      { ImGui.Col_Text, c.text }, { ImGui.Col_TextDisabled, c.muted },
      { ImGui.Col_WindowBg, c.bg }, { ImGui.Col_ChildBg, c.surface },
      { ImGui.Col_PopupBg, c.surface }, { ImGui.Col_Border, c.border },
      { ImGui.Col_Separator, c.border }, { ImGui.Col_FrameBg, c.surface_hover },
      { ImGui.Col_FrameBgHovered, c.surface_active }, { ImGui.Col_FrameBgActive, c.surface_active },
      { ImGui.Col_Button, c.surface }, { ImGui.Col_ButtonHovered, c.surface_hover },
      { ImGui.Col_ButtonActive, c.surface_active }, { ImGui.Col_Header, c.surface_hover },
      { ImGui.Col_HeaderHovered, c.surface_hover }, { ImGui.Col_HeaderActive, c.surface_active },
      { ImGui.Col_CheckMark, c.accent }, { ImGui.Col_TitleBgActive, c.surface },
    }
    for _, pair in ipairs(colors) do ImGui.PushStyleColor(ctx, pair[1], pair[2]) end
    local vars = {
      { ImGui.StyleVar_WindowPadding, 12, 12 }, { ImGui.StyleVar_FramePadding, 10, 5 },
      { ImGui.StyleVar_ItemSpacing, 8, 8 }, { ImGui.StyleVar_ItemInnerSpacing, 6, 4 },
      { ImGui.StyleVar_WindowRounding, 6 }, { ImGui.StyleVar_ChildRounding, 6 },
      { ImGui.StyleVar_FrameRounding, 6 }, { ImGui.StyleVar_PopupRounding, 6 },
      { ImGui.StyleVar_FrameBorderSize, 1 }, { ImGui.StyleVar_ChildBorderSize, 1 },
      { ImGui.StyleVar_PopupBorderSize, 1 },
    }
    for _, var in ipairs(vars) do ImGui.PushStyleVar(ctx, var[1], var[2], var[3]) end
    pushed_colors, pushed_vars = #colors, #vars
  end

  function self:pop()
    ImGui.PopStyleVar(ctx, pushed_vars)
    ImGui.PopStyleColor(ctx, pushed_colors)
  end

  return self
end

return M
```

- [ ] **Step 4: Run core tests to verify they pass**

Run: **Run core tests**.
Expected: `PASS <N> core tests + REAPER/ReaImGui smoke`, with N six higher than before this task.

- [ ] **Step 5: Commit**

```bash
git add ReaProjectLink/lib/reaprojectlink/ui/theme.lua tests/ui_theme_spec.lua tests/specs.lua
git commit -m "feat(ui): add light and dark theme tokens"
```

---

### Task 2: View models

**Files:**
- Create: `ReaProjectLink/lib/reaprojectlink/ui/view_models.lua`
- Create: `tests/ui_view_models_spec.lua`
- Modify: `tests/specs.lua`

- [ ] **Step 1: Write the failing spec**

Create `tests/ui_view_models_spec.lua`:

```lua
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
```

Append `"ui_view_models_spec.lua",` to `tests/specs.lua`.

- [ ] **Step 2: Run core tests to verify the failure**

Run: **Run core tests**. Expected: `FAIL` with `module 'reaprojectlink.ui.view_models' not found`.

- [ ] **Step 3: Implement the view models**

Create `ReaProjectLink/lib/reaprojectlink/ui/view_models.lua`:

```lua
-- Pure presentation decisions. Nothing here calls ImGui or REAPER.
local M = {}

function M.count(value, noun)
  return string.format("%d %s", value, value == 1 and noun or noun .. "s")
end

function M.project_name(path)
  local name = (path or ""):match("([^/\\]+)$")
  if not name or name == "" then return "Untitled project" end
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
      state = "unsubscribed", status = "Not connected", level = "warning",
      note = "Choose the reference.json your mix project published.",
      action = { id = "choose_reference", label = "Choose reference.json" },
      attention = true,
    }
  end
  if check.state == "unreachable" then
    return {
      state = "unreachable", status = "Couldn't reach shared storage", level = "blocked",
      rows = rows, action = { id = "retry", label = "Retry" }, attention = true,
    }
  end
  if check.state == "invalid" then
    return {
      state = "invalid", status = "Couldn't read the Reference", level = "blocked",
      note = check.error, rows = rows, action = { id = "retry", label = "Retry" }, attention = true,
    }
  end
  if input.media_error then
    return {
      state = "blocked", status = input.media_error, level = "blocked", rows = rows,
      action = { id = "review_update", label = "Review update" }, attention = true,
    }
  end
  if check.state ~= "done" then
    return { state = "checking", status = "Checking...", level = "neutral", rows = rows, attention = false }
  end
  if check.latest > synchronized then
    return {
      state = "newer", status = string.format("Reference r%d available", check.latest),
      level = "warning", rows = rows,
      action = { id = "review_update", label = "Review update" }, attention = true,
    }
  end
  return {
    state = "current", status = "Up to date", level = "ready",
    rows = { { "Reference", revision_label(synchronized) } }, attention = false,
  }
end

function M.source_delivery(input, pending_reference)
  if (input.track_count or 0) == 0 then
    return {
      state = "unconfigured", status = "No delivery tracks", level = "warning",
      note = "Select tracks in REAPER first.",
      action = { id = "register_tracks", label = "Register selected tracks" },
      attention = true,
    }
  end
  local revision = input.delivery_revision or 0
  return {
    state = revision > 0 and "published" or "unpublished",
    status = revision > 0 and ("Last published r" .. revision) or "Not published yet",
    level = "neutral",
    rows = { { "Tracks", tostring(input.track_count) }, { "Items", tostring(input.item_count or 0) } },
    note = pending_reference and string.format("Will record Reference r%d", pending_reference) or nil,
    action = { id = "review_publish", label = "Review and publish" },
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
      state = "unconfigured", status = "No reference tracks", level = "warning",
      note = "Select video tracks in REAPER first.",
      action = { id = "register_tracks", label = "Register selected tracks" },
      attention = true,
    }
  end
  local rows = { { "Tracks", tostring(input.track_count) }, { "Markers", tostring(input.marker_count or 0) } }
  local revision = input.reference_revision or 0
  if revision == 0 then
    return {
      state = "unpublished", status = "Not published yet", level = "warning", rows = rows,
      action = { id = "review_publish", label = "Review and publish" }, attention = true,
    }
  end
  return {
    state = "published", status = "Published r" .. revision, level = "neutral", rows = rows,
    action = { id = "review_publish", label = "Review and publish" }, attention = false,
  }
end

function M.delivery_row(row, master_reference_revision)
  local check = row.check or { state = "idle" }
  local accepted = row.accepted or 0
  if check.state == "unreachable" then
    return { state = "unreachable", status = "Couldn't reach", level = "blocked",
      action = { id = "retry", label = "Retry" }, attention = true }
  end
  if check.state == "invalid" then
    return { state = "invalid", status = "Couldn't read delivery", level = "blocked", note = check.error,
      action = { id = "retry", label = "Retry" }, attention = true }
  end
  if check.state ~= "done" then
    return { state = "checking", status = "Checking...", level = "neutral", attention = false }
  end
  if check.latest > accepted then
    return { state = "newer", status = string.format("r%d available · have r%d", check.latest, accepted),
      level = "warning", action = { id = "sync", label = "Sync" }, attention = true }
  end
  if (row.unmapped_count or 0) > 0 then
    return { state = "unmapped", status = M.count(row.unmapped_count, "lane") .. " not imported",
      level = "neutral", action = { id = "map_lanes", label = "Map lanes" }, attention = true }
  end
  if check.reviewed_reference and check.reviewed_reference < master_reference_revision then
    return { state = "older_reference",
      status = string.format("Made against Reference r%d", check.reviewed_reference),
      level = "warning", attention = false }
  end
  return { state = "current", status = string.format("Up to date · r%d", accepted),
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
      status = "No deliveries yet", level = "warning",
      note = "Add the delivery.json a department published.",
      action = { id = "add_delivery", label = "Add delivery" },
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
  table.insert(options, { id = "create", label = "New track" })
  table.insert(options, { id = "selected", label = "Selected track" })
  table.insert(options, { separator = true })
  table.insert(options, { id = "unmapped", label = "Don't import" })
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
  if kind == "unmapped" then return "Don't import" end
  if kind == "existing" then return track_name(mapping.track_ref) end
  return "New track"
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

function M.reference_declaration_options(synchronized, last_declared)
  local options = { { id = synchronized, label = string.format("r%d (synced)", synchronized) } }
  if last_declared and last_declared > 0 and last_declared ~= synchronized then
    table.insert(options, { id = last_declared, label = "r" .. last_declared })
  end
  return options
end

return M
```

- [ ] **Step 4: Run core tests to verify they pass**

Run: **Run core tests**. Expected: `PASS`, count up by 11.

- [ ] **Step 5: Commit**

```bash
git add ReaProjectLink/lib/reaprojectlink/ui/view_models.lua tests/ui_view_models_spec.lua tests/specs.lua
git commit -m "feat(ui): add card and mapping view models"
```

---

### Task 3: App state

**Files:**
- Create: `ReaProjectLink/lib/reaprojectlink/ui/app_state.lua`
- Create: `tests/ui_app_state_spec.lua`
- Modify: `tests/specs.lua`

- [ ] **Step 1: Write the failing spec**

Create `tests/ui_app_state_spec.lua`:

```lua
local app_state = require("reaprojectlink.ui.app_state")

local function equal(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
  end
end

local now = 100
local function clock() return now end

local tests = {}

function tests.starts_on_the_main_panel()
  local app = app_state.new(clock)
  equal(app.view, "main", "view")
  equal(app.review, nil, "review")
  equal(app.checks.reference.state, "idle", "reference check")
  equal(app.moved_items_change_count, -1, "moved-item tracking")
end

function tests.opens_and_leaves_reviews_and_settings()
  local app = app_state.new(clock)
  app:open_review("delivery_publish", { data = 1 })
  equal(app.view, "review", "review view")
  equal(app.review.kind, "delivery_publish", "review kind")
  equal(app.review.data, 1, "review fields")
  app:back()
  equal(app.view, "main", "back to main")
  equal(app.review, nil, "review cleared")
  app:open_settings()
  equal(app.view, "settings", "settings view")
  app:back()
  equal(app.view, "main", "settings closed")
end

function tests.success_toasts_expire_and_errors_stay()
  now = 100
  local app = app_state.new(clock)
  app:notify("Saved")
  equal(app:visible_toast().text, "Saved", "visible toast")
  now = 104
  equal(app:visible_toast(), nil, "success toast expired")
  app:notify("Broken", true)
  now = 500
  equal(app:visible_toast().is_error, true, "error toast stays")
  app:dismiss_toast()
  equal(app:visible_toast(), nil, "dismissed")
end

function tests.checks_run_one_frame_after_the_request()
  local app = app_state.new(clock)
  app:request_check()
  equal(app.checks.reference.state, "checking", "reference marked checking")
  equal(app:check_due(), false, "first frame shows Checking")
  equal(app:check_due(), true, "second frame runs the check")
  equal(app:check_due(), false, "check runs once")
end

function tests.a_new_check_keeps_the_last_known_results()
  local app = app_state.new(clock)
  app.checks.reference = { state = "done", latest = 5 }
  app.checks.deliveries = { a = { state = "done", latest = 3, reviewed_reference = 8 } }
  app:request_check()
  equal(app.checks.reference.latest, 5, "reference latest kept")
  equal(app.checks.deliveries.a.state, "checking", "delivery marked checking")
  equal(app.checks.deliveries.a.latest, 3, "delivery latest kept")
  equal(app.checks.deliveries.a.reviewed_reference, 8, "reviewed Reference kept")
end

function tests.reports_seconds_since_the_last_check()
  now = 100
  local app = app_state.new(clock)
  equal(app:seconds_since_check(), nil, "never checked")
  app:finish_check()
  now = 130.7
  equal(app:seconds_since_check(), 30, "whole seconds")
end

function tests.reset_clears_transient_state()
  local app = app_state.new(clock)
  app:open_review("reference_update", {})
  app:notify("Broken", true)
  app.lock = { info = {} }
  app.media_error = "Media File Not Found"
  app.moved_items_change_count = 9
  app:request_check()
  app:reset()
  equal(app.view, "main", "view reset")
  equal(app.review, nil, "review reset")
  equal(app.toast, nil, "toast reset")
  equal(app.lock, nil, "lock reset")
  equal(app.media_error, nil, "media error reset")
  equal(app.check_phase, nil, "check phase reset")
  equal(app.moved_items_change_count, -1, "moved-item tracking reset")
end

local passed = 0
for name, test in pairs(tests) do
  local ok, err = pcall(test)
  if not ok then error(name .. ": " .. tostring(err)) end
  passed = passed + 1
end

return passed
```

Append `"ui_app_state_spec.lua",` to `tests/specs.lua`.

- [ ] **Step 2: Run core tests to verify the failure**

Run: **Run core tests**. Expected: `FAIL` with `module 'reaprojectlink.ui.app_state' not found`.

- [ ] **Step 3: Implement app state**

Create `ReaProjectLink/lib/reaprojectlink/ui/app_state.lua`:

```lua
-- Transient UI state for the active REAPER project (D067). `clock` returns
-- seconds, for example `reaper.time_precise`.
local M = {}

M.TOAST_SECONDS = 4

function M.new(clock)
  local app = { clock = clock }

  function app:reset()
    self.view = "main"
    self.review = nil
    self.toast = nil
    self.lock = nil
    self.media_error = nil
    self.checks = { reference = { state = "idle" }, deliveries = {} }
    self.check_phase = nil
    self.checked_at = nil
    self.moved_items_change_count = -1
  end

  function app:open_review(kind, fields)
    fields = fields or {}
    fields.kind = kind
    self.review = fields
    self.view = "review"
  end

  function app:open_settings()
    self.view = "settings"
  end

  function app:back()
    self.review = nil
    self.view = "main"
  end

  function app:notify(text, is_error)
    self.toast = { text = tostring(text), is_error = is_error == true, shown_at = self.clock() }
  end

  function app:visible_toast()
    local toast = self.toast
    if toast and not toast.is_error and self.clock() - toast.shown_at >= M.TOAST_SECONDS then
      self.toast = nil
    end
    return self.toast
  end

  function app:dismiss_toast()
    self.toast = nil
  end

  -- The first frame after a request renders "Checking..."; the next one runs it.
  function app:request_check()
    self.check_phase = "requested"
    self.checks.reference = { state = "checking", latest = self.checks.reference.latest }
    for id, check in pairs(self.checks.deliveries) do
      self.checks.deliveries[id] = {
        state = "checking", latest = check.latest, reviewed_reference = check.reviewed_reference,
      }
    end
  end

  function app:check_due()
    if self.check_phase == "requested" then
      self.check_phase = "shown"
      return false
    end
    if self.check_phase == "shown" then
      self.check_phase = nil
      return true
    end
    return false
  end

  function app:finish_check()
    self.checked_at = self.clock()
  end

  function app:seconds_since_check()
    if not self.checked_at then return nil end
    return math.floor(self.clock() - self.checked_at)
  end

  app:reset()
  return app
end

return M
```

- [ ] **Step 4: Run core tests to verify they pass**

Run: **Run core tests**. Expected: `PASS`, count up by 7.

- [ ] **Step 5: Commit**

```bash
git add ReaProjectLink/lib/reaprojectlink/ui/app_state.lua tests/ui_app_state_spec.lua tests/specs.lua
git commit -m "feat(ui): add transient app state and check scheduling"
```

---

### Task 4: Pointer-only update checks

The main panel must not hash media (spec section 4). `reference_subscription.check` hashes every Reference video, so add a pointer-only `peek` to the Reference subscription and to Delivery updates.

**Files:**
- Modify: `ReaProjectLink/lib/reaprojectlink/reference_subscription.lua` (add after `M.check`)
- Modify: `ReaProjectLink/lib/reaprojectlink/delivery_update.lua` (add before `M.review`)
- Create: `tests/pointer_peek_spec.lua`
- Modify: `tests/specs.lua`

- [ ] **Step 1: Write the failing spec**

Create `tests/pointer_peek_spec.lua`:

```lua
local json = require("reaprojectlink.json")
local reference_subscription = require("reaprojectlink.reference_subscription")
local delivery_update = require("reaprojectlink.delivery_update")

local function equal(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
  end
end

local files, values = {}, {}
local fs = {}
function fs.exists(path) return files[path] ~= nil end
function fs.read_file(path) return files[path] end
function fs.join(...) return (table.concat({ ... }, "/"):gsub("/+", "/")) end
function fs.hash_file() error("a pointer check must not hash media") end

local adapter = {}
function adapter.get_project_value(key) return values[key] end

local reference_path = "C:/mix/_ReaProjectLink/MIX/reference.json"
local delivery_root = "C:/dx/_ReaProjectLink/DX"
local subscription = {
  pointerPath = delivery_root .. "/delivery.json",
  sourceProjectId = "source-1",
  deliveryId = "delivery-1",
}

local function reset()
  files, values = {}, {}
  files[reference_path] = json.encode({
    schemaVersion = 2, masterProjectId = "master-1", referenceId = "reference-1",
    latestReferenceRevision = 5, manifest = "history/reference-0005.json",
  })
  files[delivery_root .. "/delivery.json"] = json.encode({
    schemaVersion = 1, sourceProjectId = "source-1", deliveryId = "delivery-1",
    latestDeliveryRevision = 3, manifest = "history/delivery-0003.json",
  })
  files[delivery_root .. "/history/delivery-0003.json"] = json.encode({
    schemaVersion = 1, reference = { referenceId = "reference-1", reviewedRevision = 6 },
  })
  values.reference_manifest_path = reference_path
  values.reference_id = "reference-1"
end

local tests = {}

function tests.reference_peek_requires_a_subscription()
  reset()
  values.reference_manifest_path = nil
  local status, _, kind = reference_subscription.peek(adapter, fs)
  equal(status, nil, "no status")
  equal(kind, "unsubscribed", "kind")
end

function tests.reference_peek_reports_unreachable_storage()
  reset()
  files[reference_path] = nil
  local status, err, kind = reference_subscription.peek(adapter, fs)
  equal(status, nil, "no status")
  equal(kind, "unreachable", "kind")
  equal(err, "Couldn't reach shared storage.", "message")
end

function tests.reference_peek_reads_only_the_pointer()
  reset()
  local status = assert(reference_subscription.peek(adapter, fs))
  equal(status.latest_revision, 5, "latest revision")
end

function tests.reference_peek_rejects_a_changed_identity()
  reset()
  values.reference_id = "other-reference"
  local status, _, kind = reference_subscription.peek(adapter, fs)
  equal(status, nil, "no status")
  equal(kind, "invalid", "kind")
end

function tests.delivery_peek_reads_the_pointer_and_latest_snapshot()
  reset()
  local status = assert(delivery_update.peek(fs, subscription))
  equal(status.latest_revision, 3, "latest revision")
  equal(status.reviewed_reference_revision, 6, "reviewed Reference revision")
end

function tests.delivery_peek_reports_unreachable_storage()
  reset()
  files[subscription.pointerPath] = nil
  local status, _, kind = delivery_update.peek(fs, subscription)
  equal(status, nil, "no status")
  equal(kind, "unreachable", "kind")
end

function tests.delivery_peek_rejects_a_changed_identity()
  reset()
  local changed = { pointerPath = subscription.pointerPath, sourceProjectId = "other", deliveryId = "delivery-1" }
  local status, _, kind = delivery_update.peek(fs, changed)
  equal(status, nil, "no status")
  equal(kind, "invalid", "kind")
end

local passed = 0
for name, test in pairs(tests) do
  local ok, err = pcall(test)
  if not ok then error(name .. ": " .. tostring(err)) end
  passed = passed + 1
end

return passed
```

Append `"pointer_peek_spec.lua",` to `tests/specs.lua`.

- [ ] **Step 2: Run core tests to verify the failure**

Run: **Run core tests**. Expected: `FAIL` with `attempt to call a nil value (field 'peek')`.

- [ ] **Step 3: Add `reference_subscription.peek`**

In `ReaProjectLink/lib/reaprojectlink/reference_subscription.lua`, insert directly after the `end` that closes `function M.check(adapter, fs)`:

```lua
-- Reads only reference.json. The third return value classifies a failure as
-- "unsubscribed", "unreachable", or "invalid" for the main panel.
function M.peek(adapter, fs)
  local pointer_path = adapter.get_project_value(constants.PROJECT_KEYS.reference_manifest_path)
  if not pointer_path or pointer_path == "" then
    return nil, "No Reference subscription.", "unsubscribed"
  end
  if not fs.exists(pointer_path) then
    return nil, "Couldn't reach shared storage.", "unreachable"
  end
  local pointer, pointer_error = manifest_file.read(fs, pointer_path, "reference.json", 2)
  if not pointer then return nil, pointer_error, "invalid" end
  local valid, validation_error = manifest_validation.reference_pointer(pointer)
  if not valid then return nil, validation_error, "invalid" end
  local expected_id = adapter.get_project_value(constants.PROJECT_KEYS.reference_id)
  if expected_id and expected_id ~= "" and pointer.referenceId ~= expected_id then
    return nil, "Subscribed Reference ID changed unexpectedly.", "invalid"
  end
  return { latest_revision = pointer.latestReferenceRevision }
end
```

- [ ] **Step 4: Add `delivery_update.peek`**

In `ReaProjectLink/lib/reaprojectlink/delivery_update.lua`, insert directly before `function M.review(adapter, fs, source_project_id, target_revision)`:

```lua
-- Reads only delivery.json and its latest snapshot (small JSON, no media).
function M.peek(fs, subscription)
  if not fs.exists(subscription.pointerPath) then
    return nil, "Couldn't reach shared storage.", "unreachable"
  end
  local pointer, pointer_error = manifest_file.read(fs, subscription.pointerPath, "delivery.json", 1)
  if not pointer then return nil, pointer_error, "invalid" end
  local valid, validation_error = manifest_validation.delivery_pointer(pointer)
  if not valid then return nil, validation_error, "invalid" end
  if pointer.sourceProjectId ~= subscription.sourceProjectId or
      pointer.deliveryId ~= subscription.deliveryId then
    return nil, "Subscribed Source or Delivery identity changed.", "invalid"
  end
  local package_root = subscription.pointerPath:match("^(.*)[/\\][^/\\]+$")
  local snapshot, snapshot_error = manifest_file.read(
    fs, fs.join(package_root, pointer.manifest), "Delivery Manifest", 1
  )
  if not snapshot then return nil, snapshot_error, "invalid" end
  return {
    latest_revision = pointer.latestDeliveryRevision,
    reviewed_reference_revision = snapshot.reference and snapshot.reference.reviewedRevision,
  }
end
```

- [ ] **Step 5: Run core tests to verify they pass**

Run: **Run core tests**. Expected: `PASS`, count up by 7.

- [ ] **Step 6: Commit**

```bash
git add ReaProjectLink/lib/reaprojectlink/reference_subscription.lua ReaProjectLink/lib/reaprojectlink/delivery_update.lua tests/pointer_peek_spec.lua tests/specs.lua
git commit -m "feat(workflow): add pointer-only update checks"
```

---

### Task 5: Declare the checked Reference at Delivery Publish (spec 9.1)

**Files:**
- Modify: `ReaProjectLink/lib/reaprojectlink/delivery_publish.lua:129-138` (review) and the end of `service.publish`
- Modify: `ReaProjectLink/lib/reaprojectlink/reference_subscription.lua` (remove `M.mark_reviewed`)
- Modify: `ReaProjectLink/ReaProjectLink.lua:282-287` (remove the old Mark Reference Reviewed button)
- Modify: `tests/delivery_publish_spec.lua`
- Modify: `tests/reference_subscription_spec.lua:104-106`

- [ ] **Step 1: Update the publish spec**

In `tests/delivery_publish_spec.lua`, replace the fixture line

```lua
  reviewed_reference_revision = "7",
```

with

```lua
  synchronized_reference_revision = "7",
```

After the line `assert(captured_publish.snapshot.reference.reviewedRevision == 7, "reviewed Reference revision")` add:

```lua
assert(project_values.reviewed_reference_revision == "7", "declared Reference revision persisted")
```

After the line `assert(next_review.lanes[1].clips[1].status == "Included", "next snapshot needs no lineage decision")` add:

```lua
project_values.synchronized_reference_revision = "8"
local declared_default = assert(service.review(adapter, fs, {}))
assert(declared_default.reviewed_reference_revision == 8,
  "declaration defaults to the Synchronized Reference Revision")
assert(declared_default.last_declared_reference_revision == 7, "previous declaration is offered")
local declared_older = assert(service.review(adapter, fs, { declared_reference_revision = 7 }))
assert(declared_older.reviewed_reference_revision == 7, "the previous revision may be declared")
project_values.synchronized_reference_revision = nil
local unsynchronized = assert(service.review(adapter, fs, {}))
assert(unsynchronized.reference_blocker, "publishing requires a Synchronized Reference Revision")
project_values.synchronized_reference_revision = "8"
```

Change the final `return 6` to `return 7`.

- [ ] **Step 2: Update the subscription spec**

In `tests/reference_subscription_spec.lua`, delete these three lines (they follow `assert(values.reviewed_reference_revision == nil, "sync does not imply review")`):

```lua
local reviewed, review_error = reference_subscription.mark_reviewed(adapter, status)
assert(reviewed, review_error)
assert(values.reviewed_reference_revision == "3", "review is explicit")
```

and the blank line after them. Change the final `return 11` to `return 10`.

- [ ] **Step 3: Run core tests to verify the failure**

Run: **Run core tests**. Expected: `FAIL` from `delivery_publish_spec.lua`: the first review now has a `reference_blocker` because no Reviewed Revision is stored (`publishable review` assertion).

- [ ] **Step 4: Implement the declaration in `delivery_publish.review`**

In `ReaProjectLink/lib/reaprojectlink/delivery_publish.lua`, replace

```lua
    review.reference_id = adapter.get_project_value(constants.PROJECT_KEYS.reference_id)
    review.reviewed_reference_revision = tonumber(adapter.get_project_value(
      constants.PROJECT_KEYS.reviewed_reference_revision
    ))
    if not review.reference_id or review.reference_id == "" or
        not review.reviewed_reference_revision or not reference_start_samples then
      review.blocker_count = review.blocker_count + 1
      review.reference_blocker = "Subscribe to and review a Reference revision before audio Publish."
    end
```

with

```lua
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
```

- [ ] **Step 5: Persist the declaration after a successful Publish**

In `service.publish`, replace

```lua
    adapter.set_project_value(
      constants.PROJECT_KEYS.delivery_revision,
      tostring(result.delivery_revision)
    )
```

with

```lua
    adapter.set_project_value(
      constants.PROJECT_KEYS.delivery_revision,
      tostring(result.delivery_revision)
    )
    adapter.set_project_value(
      constants.PROJECT_KEYS.reviewed_reference_revision,
      tostring(review.reviewed_reference_revision)
    )
```

- [ ] **Step 6: Remove `mark_reviewed`**

In `ReaProjectLink/lib/reaprojectlink/reference_subscription.lua`, delete the whole `function M.mark_reviewed(adapter, status) ... end` block.

In `ReaProjectLink/ReaProjectLink.lua`, delete the block that calls it (inside `draw_source_reference`):

```lua
  if source_reference.synchronized_revision == source_reference.latest_revision and
      source_reference.reviewed_revision ~= source_reference.latest_revision and
      ImGui.Button(ctx, "Mark Reference Reviewed") then
    local result, err = reference_subscription.mark_reviewed(adapter, source_reference)
    if result then check_source_reference() else notify(err, true) end
  end
```

- [ ] **Step 7: Run core tests to verify they pass**

Run: **Run core tests**. Expected: `PASS`.

- [ ] **Step 8: Commit**

```bash
git add ReaProjectLink/lib/reaprojectlink/delivery_publish.lua ReaProjectLink/lib/reaprojectlink/reference_subscription.lua ReaProjectLink/ReaProjectLink.lua tests/delivery_publish_spec.lua tests/reference_subscription_spec.lua
git commit -m "feat(delivery): declare the checked Reference revision at publish"
```

---

### Task 6: Icons and components

**Files:**
- Create: `ReaProjectLink/lib/reaprojectlink/ui/icons.lua`
- Create: `ReaProjectLink/lib/reaprojectlink/ui/components.lua`
- Create: `tests/ui_modules_spec.lua`
- Modify: `tests/specs.lua`

- [ ] **Step 1: Write the failing spec**

Create `tests/ui_modules_spec.lua`:

```lua
local function equal(actual, expected, label)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
  end
end

-- Later tasks append their modules here so that every UI file is at least
-- loaded (syntax and require errors) by the core suite.
local MODULES = {
  "reaprojectlink.ui.theme",
  "reaprojectlink.ui.icons",
  "reaprojectlink.ui.components",
}

local tests = {}

function tests.every_ui_module_loads()
  for _, name in ipairs(MODULES) do
    assert(type(require(name)) == "table", name .. " returns a module table")
  end
end

function tests.every_icon_draws_primitives()
  local icons = require("reaprojectlink.ui.icons")
  local calls = 0
  local ImGui = setmetatable({}, {
    __index = function() return function() calls = calls + 1 end end,
  })
  for _, name in ipairs(icons.NAMES) do
    calls = 0
    equal(icons.draw(ImGui, "draw-list", name, 0, 0, 16, 0xffffffff), true, name .. " is known")
    assert(calls > 0, name .. " draws at least one primitive")
  end
  equal(icons.draw(ImGui, "draw-list", "missing", 0, 0, 16, 0xffffffff), false, "unknown icon")
end

local passed = 0
for name, test in pairs(tests) do
  local ok, err = pcall(test)
  if not ok then error(name .. ": " .. tostring(err)) end
  passed = passed + 1
end

return passed
```

Append `"ui_modules_spec.lua",` to `tests/specs.lua`.

- [ ] **Step 2: Run core tests to verify the failure**

Run: **Run core tests**. Expected: `FAIL` with `module 'reaprojectlink.ui.icons' not found`.

- [ ] **Step 3: Implement icons**

Create `ReaProjectLink/lib/reaprojectlink/ui/icons.lua`:

```lua
-- Icons are drawn with DrawList primitives so the package needs no icon font.
local M = {}

M.NAMES = {
  "more", "gear", "dot", "back", "plus", "check", "cross", "warning", "film", "upload", "download",
}

-- Line segments in unit coordinates: { x1, y1, x2, y2 }.
local SEGMENTS = {
  back = { { 0.8, 0.5, 0.2, 0.5 }, { 0.2, 0.5, 0.45, 0.25 }, { 0.2, 0.5, 0.45, 0.75 } },
  plus = { { 0.5, 0.2, 0.5, 0.8 }, { 0.2, 0.5, 0.8, 0.5 } },
  check = { { 0.2, 0.55, 0.42, 0.75 }, { 0.42, 0.75, 0.8, 0.28 } },
  cross = { { 0.25, 0.25, 0.75, 0.75 }, { 0.75, 0.25, 0.25, 0.75 } },
  warning = {
    { 0.5, 0.12, 0.9, 0.85 }, { 0.9, 0.85, 0.1, 0.85 }, { 0.1, 0.85, 0.5, 0.12 },
    { 0.5, 0.4, 0.5, 0.6 },
  },
  film = {
    { 0.15, 0.25, 0.85, 0.25 }, { 0.85, 0.25, 0.85, 0.75 }, { 0.85, 0.75, 0.15, 0.75 },
    { 0.15, 0.75, 0.15, 0.25 }, { 0.35, 0.25, 0.35, 0.75 }, { 0.65, 0.25, 0.65, 0.75 },
  },
  upload = {
    { 0.5, 0.7, 0.5, 0.15 }, { 0.5, 0.15, 0.28, 0.37 }, { 0.5, 0.15, 0.72, 0.37 },
    { 0.2, 0.85, 0.8, 0.85 },
  },
  download = {
    { 0.5, 0.15, 0.5, 0.7 }, { 0.5, 0.7, 0.28, 0.48 }, { 0.5, 0.7, 0.72, 0.48 },
    { 0.2, 0.85, 0.8, 0.85 },
  },
}

function M.draw(ImGui, draw_list, name, x, y, size, color)
  local thickness = math.max(1, size / 12)
  local segments = SEGMENTS[name]
  if segments then
    for _, s in ipairs(segments) do
      ImGui.DrawList_AddLine(draw_list, x + s[1] * size, y + s[2] * size,
        x + s[3] * size, y + s[4] * size, color, thickness)
    end
    return true
  end
  local cx, cy = x + size / 2, y + size / 2
  if name == "more" then
    for _, offset in ipairs({ 0.2, 0.5, 0.8 }) do
      ImGui.DrawList_AddCircleFilled(draw_list, x + offset * size, cy, math.max(1, size * 0.08), color)
    end
  elseif name == "dot" then
    ImGui.DrawList_AddCircleFilled(draw_list, cx, cy, size * 0.2, color)
  elseif name == "gear" then
    ImGui.DrawList_AddCircle(draw_list, cx, cy, size * 0.28, color, 0, thickness)
    ImGui.DrawList_AddCircle(draw_list, cx, cy, size * 0.1, color, 0, thickness)
    for tooth = 0, 7 do
      local angle = tooth * math.pi / 4
      ImGui.DrawList_AddLine(draw_list,
        cx + math.cos(angle) * size * 0.28, cy + math.sin(angle) * size * 0.28,
        cx + math.cos(angle) * size * 0.42, cy + math.sin(angle) * size * 0.42,
        color, thickness * 1.5)
    end
  else
    return false
  end
  return true
end

return M
```

- [ ] **Step 4: Implement components**

Create `ReaProjectLink/lib/reaprojectlink/ui/components.lua`:

```lua
local icons = require("reaprojectlink.ui.icons")

-- Shared widgets. They standardize spacing and color and never contain domain
-- or REAPER mutation logic.
local M = {}

-- ReaImGui's 0.9 compatibility table predates the named ChildFlags constants;
-- BeginChild accepts the Dear ImGui bit values directly.
local CHILD_BORDER = 1
local CHILD_ALWAYS_USE_PADDING = 2
local CHILD_AUTO_RESIZE_Y = 32
local CARD_FLAGS = CHILD_BORDER | CHILD_ALWAYS_USE_PADDING | CHILD_AUTO_RESIZE_Y
local PAGE_MAX_WIDTH = 720
local FOOTER_HEIGHT = 48
local STACK_BELOW = 560
local VALUE_COLUMN = 130
local LEVEL_COLOR = { neutral = "muted", ready = "ready", warning = "warning", blocked = "blocked" }
local NOTICE_STYLE = {
  blocked = { "blocked_bg", "blocked", "cross" },
  warning = { "warning_bg", "warning", "warning" },
  ready = { "accent_bg", "text", "check" },
}

function M.create(ImGui, ctx, theme)
  local c = {}
  local cards, pages = {}, {}

  local function colors() return theme.colors end
  local function level_color(level) return colors()[LEVEL_COLOR[level] or "muted"] end
  local function visible_label(label) return (label:gsub("##.*$", "")) end

  local function styled_button(label, fill, hover, active, text, border)
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, fill)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, hover)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, active)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, text)
    ImGui.PushStyleColor(ctx, ImGui.Col_Border, border)
    local clicked = ImGui.Button(ctx, label)
    ImGui.PopStyleColor(ctx, 5)
    return clicked
  end

  -- Text ----------------------------------------------------------------------

  function c.title(text)
    ImGui.PushFont(ctx, theme.fonts.title)
    ImGui.Text(ctx, text)
    ImGui.PopFont(ctx)
  end

  function c.heading(text)
    ImGui.PushFont(ctx, theme.fonts.heading)
    ImGui.Text(ctx, text)
    ImGui.PopFont(ctx)
  end

  function c.colored(text, color)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, color)
    ImGui.TextWrapped(ctx, text)
    ImGui.PopStyleColor(ctx)
  end

  function c.muted(text) c.colored(text, colors().muted) end

  function c.small(text)
    ImGui.PushFont(ctx, theme.fonts.small)
    c.muted(text)
    ImGui.PopFont(ctx)
  end

  function c.inline_muted(text) ImGui.TextColored(ctx, colors().muted, text) end

  function c.section(text)
    ImGui.Dummy(ctx, 0, 4)
    c.small(text)
  end

  function c.key_value(label, value)
    ImGui.TextColored(ctx, colors().muted, label)
    ImGui.SameLine(ctx, VALUE_COLUMN)
    ImGui.TextWrapped(ctx, tostring(value))
  end

  function c.copy_value(id, label, value)
    ImGui.AlignTextToFramePadding(ctx)
    ImGui.TextColored(ctx, colors().muted, label)
    ImGui.SameLine(ctx, VALUE_COLUMN)
    if ImGui.SmallButton(ctx, "Copy##" .. id) then ImGui.SetClipboardText(ctx, tostring(value)) end
    ImGui.SameLine(ctx)
    ImGui.TextWrapped(ctx, tostring(value))
  end

  -- Icons and status ------------------------------------------------------------

  function c.icon(name, color, size)
    size = size or ImGui.GetTextLineHeight(ctx)
    local x, y = ImGui.GetCursorScreenPos(ctx)
    icons.draw(ImGui, ImGui.GetWindowDrawList(ctx), name, x, y, size, color or colors().text)
    ImGui.Dummy(ctx, size, size)
  end

  function c.status(text, level)
    local color = level_color(level)
    c.icon("dot", color)
    ImGui.SameLine(ctx, 0, 6)
    c.colored(text, color)
  end

  function c.inline_status(text, level)
    local color = level_color(level)
    c.icon("dot", color)
    ImGui.SameLine(ctx, 0, 6)
    ImGui.TextColored(ctx, color, text)
  end

  function c.status_width(text)
    return ImGui.GetTextLineHeight(ctx) + 6 + ImGui.CalcTextSize(ctx, text)
  end

  function c.badge(text)
    local k = colors()
    ImGui.PushFont(ctx, theme.fonts.small)
    local width, height = ImGui.CalcTextSize(ctx, text)
    local x, y = ImGui.GetCursorScreenPos(ctx)
    local draw_list = ImGui.GetWindowDrawList(ctx)
    ImGui.DrawList_AddRectFilled(draw_list, x, y, x + width + 12, y + height + 4, k.accent_bg, 4)
    ImGui.DrawList_AddText(draw_list, x + 6, y + 2, k.accent, text)
    ImGui.Dummy(ctx, width + 12, height + 4)
    ImGui.PopFont(ctx)
  end

  -- Buttons and layout helpers ---------------------------------------------------

  function c.button(label, kind)
    local k = colors()
    if kind == "primary" then
      return styled_button(label, k.accent, k.accent_hover, k.accent_active, k.on_accent, k.accent)
    elseif kind == "danger" then
      return styled_button(label, k.surface, k.blocked_bg, k.blocked_bg, k.blocked, k.blocked)
    end
    return ImGui.Button(ctx, label)
  end

  function c.disabled_button(label)
    ImGui.BeginDisabled(ctx, true)
    ImGui.Button(ctx, label)
    ImGui.EndDisabled(ctx)
  end

  function c.button_width(label)
    local padding = ImGui.GetStyleVar(ctx, ImGui.StyleVar_FramePadding)
    return ImGui.CalcTextSize(ctx, visible_label(label)) + padding * 2
  end

  function c.icon_button(id, name, tooltip)
    local size = ImGui.GetFrameHeight(ctx)
    local x, y = ImGui.GetCursorScreenPos(ctx)
    local clicked = ImGui.InvisibleButton(ctx, id, size, size)
    local hovered = ImGui.IsItemHovered(ctx)
    local draw_list = ImGui.GetWindowDrawList(ctx)
    if hovered then
      ImGui.DrawList_AddRectFilled(draw_list, x, y, x + size, y + size, colors().surface_hover, 6)
    end
    local pad = size * 0.2
    icons.draw(ImGui, draw_list, name, x + pad, y + pad, size - pad * 2,
      hovered and colors().text or colors().muted)
    if hovered and tooltip then ImGui.SetTooltip(ctx, tooltip) end
    return clicked
  end

  -- Continues the current line and moves the cursor so that `width` pixels end
  -- at the right edge; wraps to a new line when there is not enough room.
  function c.same_line_right(width)
    ImGui.SameLine(ctx)
    local available = ImGui.GetContentRegionAvail(ctx)
    if available < width then
      ImGui.NewLine(ctx)
      available = ImGui.GetContentRegionAvail(ctx)
    end
    ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx) + math.max(0, available - width))
  end

  -- Returns the card width and whether two cards fit side by side.
  function c.card_width()
    local available = ImGui.GetContentRegionAvail(ctx)
    if available < STACK_BELOW then return 0, false end
    return (available - 12) / 2, true
  end

  -- Cards ----------------------------------------------------------------------

  function c.begin_card(id, width, highlighted)
    local k = colors()
    ImGui.PushStyleColor(ctx, ImGui.Col_Border, highlighted and k.accent or k.border)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_ChildBorderSize, highlighted and 2 or 1)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 12, 12)
    local visible = ImGui.BeginChild(ctx, id, width or 0, 0, CARD_FLAGS, ImGui.WindowFlags_NoScrollbar)
    ImGui.PopStyleVar(ctx, 2)
    ImGui.PopStyleColor(ctx)
    table.insert(cards, visible)
    return visible
  end

  function c.end_card()
    if table.remove(cards) then ImGui.EndChild(ctx) end
  end

  function c.card_header(icon, title)
    c.icon(icon, colors().muted)
    ImGui.SameLine(ctx, 0, 6)
    c.heading(title)
  end

  -- Draws a "more" icon button with a popup menu. Entries are
  -- { id = ..., label = ... } or { separator = true }. Returns the chosen id.
  function c.menu(id, entries, align_right)
    if align_right ~= false then c.same_line_right(ImGui.GetFrameHeight(ctx)) end
    if c.icon_button(id .. "-open", "more", "More actions") then ImGui.OpenPopup(ctx, id) end
    local chosen
    if ImGui.BeginPopup(ctx, id) then
      for _, entry in ipairs(entries) do
        if entry.separator then
          ImGui.Separator(ctx)
        elseif ImGui.MenuItem(ctx, entry.label) then
          chosen = entry.id
        end
      end
      ImGui.EndPopup(ctx)
    end
    return chosen
  end

  -- Notices --------------------------------------------------------------------

  -- A tinted, full-width message with optional buttons. Returns the index of
  -- the clicked action.
  function c.notice(id, level, text, actions)
    local style = NOTICE_STYLE[level] or NOTICE_STYLE.ready
    local k = colors()
    ImGui.PushStyleColor(ctx, ImGui.Col_ChildBg, k[style[1]])
    ImGui.PushStyleColor(ctx, ImGui.Col_Border, k[style[1]])
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 10, 8)
    local visible = ImGui.BeginChild(ctx, id, 0, 0, CARD_FLAGS, ImGui.WindowFlags_NoScrollbar)
    ImGui.PopStyleVar(ctx)
    ImGui.PopStyleColor(ctx, 2)
    local chosen
    if visible then
      c.icon(style[3], k[style[2]])
      ImGui.SameLine(ctx, 0, 6)
      c.colored(text, k[style[2]])
      for index, label in ipairs(actions or {}) do
        if index > 1 then ImGui.SameLine(ctx) end
        if ImGui.Button(ctx, label .. "##" .. id .. "-" .. index) then chosen = index end
      end
      ImGui.EndChild(ctx)
    end
    return chosen
  end

  function c.toast(toast)
    local chosen = c.notice("toast", toast.is_error and "blocked" or "ready", toast.text,
      toast.is_error and { "Dismiss" } or nil)
    return chosen == 1
  end

  -- Selection ------------------------------------------------------------------

  -- Options are { label = ... } (returned when chosen), { header = ... }, or
  -- { separator = true }. Returns the chosen option table.
  function c.dropdown(id, preview, options)
    local chosen
    ImGui.SetNextItemWidth(ctx, -1)
    if ImGui.BeginCombo(ctx, "##" .. id, preview) then
      for index, option in ipairs(options) do
        if option.separator then
          ImGui.Separator(ctx)
        elseif option.header then
          ImGui.TextColored(ctx, colors().muted, option.header)
        elseif ImGui.Selectable(ctx, option.label .. "##" .. id .. "-" .. index, false) then
          chosen = option
        end
      end
      ImGui.EndCombo(ctx)
    end
    return chosen
  end

  -- Options are { id = ..., label = ... }. Returns the selected id.
  function c.segmented(id, options, selected)
    local chosen = selected
    local k = colors()
    for index, option in ipairs(options) do
      if index > 1 then ImGui.SameLine(ctx, 0, 4) end
      local label = option.label .. "##" .. id .. "-" .. index
      local clicked
      if option.id == selected then
        clicked = styled_button(label, k.accent_bg, k.accent_bg, k.accent_bg, k.accent, k.accent)
      else
        clicked = ImGui.Button(ctx, label)
      end
      if clicked then chosen = option.id end
    end
    return chosen
  end

  -- Review details ---------------------------------------------------------------

  function c.begin_group(id, label, detail, level, default_open)
    local flags = ImGui.TreeNodeFlags_SpanAvailWidth
    if default_open then flags = flags | ImGui.TreeNodeFlags_DefaultOpen end
    local open = ImGui.TreeNodeEx(ctx, id, label, flags)
    if detail then
      c.same_line_right(ImGui.CalcTextSize(ctx, detail))
      ImGui.TextColored(ctx, level_color(level), detail)
    end
    return open
  end

  function c.end_group() ImGui.TreePop(ctx) end

  -- Draws only visible rows; every row must be one text line high.
  function c.clipped(count, draw_row)
    local clipper = ImGui.CreateListClipper(ctx)
    ImGui.ListClipper_Begin(clipper, count)
    while ImGui.ListClipper_Step(clipper) do
      local first, last = ImGui.ListClipper_GetDisplayRange(clipper)
      for index = first + 1, last do draw_row(index) end
    end
  end

  -- Pages ----------------------------------------------------------------------

  -- A centered, width-capped scrolling region. With a footer it leaves room
  -- for c.footer below it.
  function c.begin_page(id, has_footer)
    local available = ImGui.GetContentRegionAvail(ctx)
    local width = math.min(available, PAGE_MAX_WIDTH)
    local indent = math.max(0, (available - width) / 2)
    ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx) + indent)
    ImGui.PushStyleColor(ctx, ImGui.Col_ChildBg, colors().bg)
    local visible = ImGui.BeginChild(ctx, id, width, has_footer and -FOOTER_HEIGHT or 0)
    ImGui.PopStyleColor(ctx)
    table.insert(pages, { visible = visible, indent = indent, width = width, id = id })
    return visible
  end

  function c.end_page()
    local page = table.remove(pages)
    if page.visible then ImGui.EndChild(ctx) end
    return page
  end

  function c.review_header(title, summary)
    local back = c.icon_button("page-back", "back", "Back")
    ImGui.SameLine(ctx, 0, 6)
    c.title(title)
    if summary then c.muted(summary) end
    ImGui.Dummy(ctx, 0, 4)
    return back
  end

  function c.footer(page, summary, level, label, enabled)
    ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx) + page.indent)
    ImGui.PushStyleColor(ctx, ImGui.Col_ChildBg, colors().bg)
    local visible = ImGui.BeginChild(ctx, page.id .. "-footer", page.width, 0, 0,
      ImGui.WindowFlags_NoScrollbar)
    ImGui.PopStyleColor(ctx)
    local clicked = false
    if visible then
      ImGui.Separator(ctx)
      ImGui.AlignTextToFramePadding(ctx)
      ImGui.TextColored(ctx, level_color(level), summary)
      c.same_line_right(c.button_width(label))
      if enabled then clicked = c.button(label, "primary") else c.disabled_button(label) end
      ImGui.EndChild(ctx)
    end
    return clicked
  end

  function c.stale(title, text, label)
    ImGui.Dummy(ctx, 0, 24)
    c.icon("warning", colors().warning)
    c.heading(title)
    c.muted(text)
    return c.button(label, "primary")
  end

  return c
end

return M
```

- [ ] **Step 5: Run core tests to verify they pass**

Run: **Run core tests**. Expected: `PASS`, count up by 2.

- [ ] **Step 6: Commit**

```bash
git add ReaProjectLink/lib/reaprojectlink/ui/icons.lua ReaProjectLink/lib/reaprojectlink/ui/components.lua tests/ui_modules_spec.lua tests/specs.lua
git commit -m "feat(ui): add drawn icons and shared components"
```

---

### Task 7: Adapter selection, workflow helpers, checks, shared views

**Files:**
- Modify: `ReaProjectLink/lib/reaprojectlink/reaper_adapter.lua` (after `M.selected_items`)
- Create: `ReaProjectLink/lib/reaprojectlink/ui/workflow.lua`
- Create: `ReaProjectLink/lib/reaprojectlink/ui/checks.lua`
- Create: `ReaProjectLink/lib/reaprojectlink/ui/views/card.lua`
- Create: `ReaProjectLink/lib/reaprojectlink/ui/views/header.lua`
- Modify: `tests/ui_modules_spec.lua`

- [ ] **Step 1: Extend the modules spec**

In `tests/ui_modules_spec.lua`, add these entries to `MODULES`:

```lua
  "reaprojectlink.ui.workflow",
  "reaprojectlink.ui.checks",
  "reaprojectlink.ui.views.card",
  "reaprojectlink.ui.views.header",
```

and add these tests before the runner loop:

```lua
function tests.workflow_formats_publish_results()
  local workflow = require("reaprojectlink.ui.workflow")
  local message, is_error = workflow.publish_message("Delivery", 13, {})
  equal(message, "Published Delivery r13.", "plain message")
  equal(is_error, false, "plain result")
  message, is_error = workflow.publish_message("Reference", 2, {
    project_save_error = "Save failed.", lock_release_error = "Lock stuck.",
  })
  equal(message, "Published Reference r2. Save failed. Publish lock cleanup failed: Lock stuck.",
    "follow-up errors")
  equal(is_error, true, "follow-up errors are errors")
end

function tests.workflow_detects_stale_reviews()
  local workflow = require("reaprojectlink.ui.workflow")
  local env = { adapter = { project_change_count = function() return 5 end } }
  equal(workflow.is_stale(env, { project_change_count = 4 }), true, "changed project")
  equal(workflow.is_stale(env, { project_change_count = 5 }), false, "unchanged project")
  equal(workflow.is_stale(env, {}), false, "untracked review")
end

function tests.checks_store_pointer_results()
  local checks = require("reaprojectlink.ui.checks")
  local app = require("reaprojectlink.ui.app_state").new(function() return 0 end)
  local env = {
    app = app,
    fs = {},
    adapter = {
      get_project_value = function()
        return '[{"sourceProjectId":"a","pointerPath":"A"},{"sourceProjectId":"b","pointerPath":"B"}]'
      end,
    },
    services = {
      reference_subscription = {
        peek = function() return nil, "Couldn't reach shared storage.", "unreachable" end,
      },
      delivery_update = {
        peek = function(_, entry)
          if entry.sourceProjectId == "a" then
            return { latest_revision = 4, reviewed_reference_revision = 8 }
          end
          return nil, "bad", "invalid"
        end,
      },
    },
  }
  checks.run_source(env)
  equal(app.checks.reference.state, "unreachable", "reference failure kind")
  checks.run_master(env)
  equal(app.checks.deliveries.a.latest, 4, "delivery latest")
  equal(app.checks.deliveries.a.reviewed_reference, 8, "delivery reviewed Reference")
  equal(app.checks.deliveries.b.state, "invalid", "delivery failure kind")
  equal(app.checks.deliveries.b.error, "bad", "delivery failure message")
end
```

- [ ] **Step 2: Run core tests to verify the failure**

Run: **Run core tests**. Expected: `FAIL` with `module 'reaprojectlink.ui.workflow' not found`.

- [ ] **Step 3: Add `select_items` to the adapter**

In `ReaProjectLink/lib/reaprojectlink/reaper_adapter.lua`, insert after the `end` of `function M.selected_items()`:

```lua
function M.select_items(items)
  reaper.SelectAllMediaItems(project(), false)
  for _, item in ipairs(items) do
    if reaper.ValidatePtr2(project(), item, "MediaItem*") then
      reaper.SetMediaItemSelected(item, true)
    end
  end
  reaper.UpdateArrange()
end
```

- [ ] **Step 4: Create the workflow helpers**

Create `ReaProjectLink/lib/reaprojectlink/ui/workflow.lua`:

```lua
-- Helpers shared by views. `env` is the table built in ui/app.lua.
local M = {}

function M.metadata()
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

function M.choose_json(reaper_api, title)
  local ok, path = reaper_api.GetUserFileNameForRead("", title, "json")
  return ok and path or nil
end

function M.confirm(reaper_api, title, text)
  return reaper_api.ShowMessageBox(text, title, 1) == 1
end

function M.is_stale(env, data)
  return data.project_change_count ~= nil and
    data.project_change_count ~= env.adapter.project_change_count()
end

-- Shows a toast for a service result. `success` is a string or a function of
-- the result.
function M.report(env, result, err, success)
  if result then
    env.app:notify(type(success) == "function" and success(result) or success)
  else
    env.app:notify(err, true)
  end
  return result
end

function M.publish_message(noun, revision, result)
  local message = string.format("Published %s r%d.", noun, revision)
  if result.project_save_error then message = message .. " " .. result.project_save_error end
  if result.lock_release_error then
    message = message .. " Publish lock cleanup failed: " .. result.lock_release_error
  end
  return message, result.project_save_error ~= nil or result.lock_release_error ~= nil
end

function M.inspect_lock(env, package_root)
  local info = env.fs.read_lock(package_root)
  env.app.lock = info and { info = info, package_root = package_root } or nil
end

function M.unlock(env)
  local app = env.app
  if not M.confirm(env.reaper, "Unlock publishing",
      "Unlock publishing only if no other user or computer is publishing to this package.") then
    return
  end
  local removed, err = env.fs.remove_lock(app.lock.package_root, app.lock.info.token)
  if removed then
    app.lock = nil
    app:notify("Publishing unlocked. Review again before publishing.")
  else
    app:notify(err, true)
  end
end

function M.choose_reference(env)
  local path = M.choose_json(env.reaper, "Select published reference.json")
  if not path then return end
  local result, err = env.services.reference_subscription.subscribe(env.adapter, env.fs, path)
  if result then
    env.app:notify("Connected to the Reference.")
    env.app:request_check()
  else
    env.app:notify(err, true)
  end
end

-- Unsaved-project and lock banners, then the toast. Views call this directly
-- under their header.
function M.draw_notices(env, state)
  local c, app = env.c, env.app
  if state and state.path == "" then
    c.notice("unsaved", "blocked", "Save this project in REAPER to use ReaProjectLink.")
  end
  if app.lock then
    local lock = app.lock.info
    local text = string.format("Publishing is locked by %s on %s since %s.",
      lock.user or "an unknown user", lock.machine or "an unknown computer",
      lock.started_at or "an unknown time")
    if c.notice("publish-lock", "blocked", text, { "Unlock publishing..." }) == 1 then
      M.unlock(env)
    end
  end
  local toast = app:visible_toast()
  if toast and c.toast(toast) then app:dismiss_toast() end
end

return M
```

- [ ] **Step 5: Create the check runner**

Create `ReaProjectLink/lib/reaprojectlink/ui/checks.lua`:

```lua
local constants = require("reaprojectlink.constants")
local json = require("reaprojectlink.json")

local M = {}

function M.subscriptions(adapter)
  local stored = adapter.get_project_value(constants.PROJECT_KEYS.delivery_subscriptions)
  if not stored or stored == "" then return {} end
  local ok, value = pcall(json.decode, stored)
  return ok and value or {}
end

function M.run_source(env)
  local status, err, kind = env.services.reference_subscription.peek(env.adapter, env.fs)
  if status then
    env.app.checks.reference = { state = "done", latest = status.latest_revision }
  elseif kind == "unsubscribed" then
    env.app.checks.reference = { state = "idle" }
  else
    env.app.checks.reference = { state = kind, error = err }
  end
end

function M.run_master(env)
  local results = {}
  for _, entry in ipairs(M.subscriptions(env.adapter)) do
    local status, err, kind = env.services.delivery_update.peek(env.fs, entry)
    if status then
      results[entry.sourceProjectId] = {
        state = "done",
        latest = status.latest_revision,
        reviewed_reference = status.reviewed_reference_revision,
      }
    else
      results[entry.sourceProjectId] = { state = kind or "invalid", error = err }
    end
  end
  env.app.checks.deliveries = results
end

return M
```

- [ ] **Step 6: Create the card and header views**

Create `ReaProjectLink/lib/reaprojectlink/ui/views/card.lua`:

```lua
-- Draws one card view model from ui/view_models.lua. Returns the id of the
-- chosen card action or menu entry.
local M = {}

function M.draw(env, id, icon, title, card, highlighted, width, menu_entries)
  local c = env.c
  local chosen
  if c.begin_card(id, width, highlighted) then
    c.card_header(icon, title)
    if menu_entries then chosen = c.menu(id .. "-menu", menu_entries) end
    c.status(card.status, card.level)
    for _, row in ipairs(card.rows or {}) do c.key_value(row[1], row[2]) end
    if card.note then c.small(card.note) end
    if card.action and c.button(card.action.label .. "##" .. id, highlighted and "primary" or nil) then
      chosen = card.action.id
    end
  end
  c.end_card()
  return chosen
end

return M
```

Create `ReaProjectLink/lib/reaprojectlink/ui/views/header.lua`:

```lua
local view_models = require("reaprojectlink.ui.view_models")
local workflow = require("reaprojectlink.ui.workflow")

local M = {}

function M.draw(env, state, badge, status_text)
  local ImGui, ctx, c, app, theme = env.ImGui, env.ctx, env.c, env.app, env.theme
  c.title(view_models.project_name(state.path))
  ImGui.SameLine(ctx, 0, 8)
  c.badge(badge)

  local label = app.check_phase and "Checking..." or
    view_models.checked_text(app:seconds_since_check()) or "Not checked yet"
  if status_text then label = status_text .. "  ·  " .. label end
  ImGui.PushFont(ctx, theme.fonts.small)
  local label_width = ImGui.CalcTextSize(ctx, label)
  ImGui.PopFont(ctx)
  c.same_line_right(label_width + 8 + c.button_width("Check now") + 8 + ImGui.GetFrameHeight(ctx))
  ImGui.AlignTextToFramePadding(ctx)
  ImGui.PushFont(ctx, theme.fonts.small)
  ImGui.TextColored(ctx, theme.colors.muted, label)
  ImGui.PopFont(ctx)
  ImGui.SameLine(ctx, 0, 8)
  if c.button("Check now") then app:request_check() end
  ImGui.SameLine(ctx, 0, 8)
  if c.icon_button("open-settings", "gear", "Settings") then app:open_settings() end

  ImGui.Separator(ctx)
  workflow.draw_notices(env, state)
end

return M
```

- [ ] **Step 7: Run core tests to verify they pass**

Run: **Run core tests**. Expected: `PASS`, count up by 3.

- [ ] **Step 8: Commit**

```bash
git add ReaProjectLink/lib/reaprojectlink/reaper_adapter.lua ReaProjectLink/lib/reaprojectlink/ui/workflow.lua ReaProjectLink/lib/reaprojectlink/ui/checks.lua ReaProjectLink/lib/reaprojectlink/ui/views/card.lua ReaProjectLink/lib/reaprojectlink/ui/views/header.lua tests/ui_modules_spec.lua
git commit -m "feat(ui): add workflow helpers, checks, card and header views"
```

---

### Task 8: Source Reviews

**Files:**
- Create: `ReaProjectLink/lib/reaprojectlink/ui/views/reference_update_review.lua`
- Create: `ReaProjectLink/lib/reaprojectlink/ui/views/delivery_publish_review.lua`
- Modify: `tests/ui_modules_spec.lua`

- [ ] **Step 1: Register the modules in the spec**

Add to `MODULES` in `tests/ui_modules_spec.lua`:

```lua
  "reaprojectlink.ui.views.reference_update_review",
  "reaprojectlink.ui.views.delivery_publish_review",
```

- [ ] **Step 2: Run core tests to verify the failure**

Run: **Run core tests**. Expected: `FAIL` with `module 'reaprojectlink.ui.views.reference_update_review' not found`.

- [ ] **Step 3: Create the Reference Update Review**

Create `ReaProjectLink/lib/reaprojectlink/ui/views/reference_update_review.lua`:

```lua
local view_models = require("reaprojectlink.ui.view_models")
local workflow = require("reaprojectlink.ui.workflow")

local M = {}

-- The full check hashes Reference media, so it only runs when the user opens
-- this Review.
function M.open(env)
  local status, err = env.services.reference_subscription.check(env.adapter, env.fs)
  if not status then
    env.app:notify(err, true)
    return
  end
  env.app.checks.reference = { state = "done", latest = status.latest_revision }
  env.app.media_error = not status.available and status.video_error or nil
  env.app:open_review("reference_update", { status = status, shift_entire_project = false })
end

function M.draw(env)
  local ImGui, ctx, c, app = env.ImGui, env.ctx, env.c, env.app
  local review = app.review
  local status = review.status
  local snapshot = status.snapshot or {}
  local back = false
  if c.begin_page("reference-update", true) then
    back = c.review_header(string.format("Update Reference to r%d", status.latest_revision),
      string.format("Synchronized r%d", status.synchronized_revision))
    workflow.draw_notices(env)
    if not status.available then c.notice("reference-media", "blocked", status.video_error) end
    if status.can_shift_entire_project then
      c.section("Decision")
      local changed, value = ImGui.Checkbox(ctx,
        string.format("Shift the entire project by %.3f seconds", status.shift_seconds),
        review.shift_entire_project)
      if changed then review.shift_entire_project = value end
      c.small("The whole Reference moved. Shift your project with it to stay in sync.")
    end
    c.section("In this revision")
    c.key_value("Tracks", #(snapshot.lanes or {}))
    c.key_value("Markers", #(snapshot.markers or {}))
    c.key_value("Regions", #(snapshot.regions or {}))
    c.key_value("Alignment", status.alignment_mode == "relative" and
      "Relative to Reference Start" or "Mirror Master timeline")
  end
  local page = c.end_page()

  local pending = status.latest_revision ~= status.synchronized_revision
  local ready = status.available and pending
  local summary
  if not status.available then
    summary = view_models.blocked_summary(1, "synchronize")
  elseif pending then
    summary = string.format("Brings Reference r%d into this project", status.latest_revision)
  else
    summary = "Already up to date"
  end
  local synchronize = c.footer(page, summary, status.available and "neutral" or "blocked",
    "Synchronize", ready)

  if back then
    app:back()
  elseif synchronize then
    local result, err = env.services.reference_subscription.synchronize(env.adapter, status, {
      shift_entire_project = review.shift_entire_project,
    })
    if result then
      app:back()
      app:notify(string.format("Synchronized Reference r%d.", status.latest_revision))
      app:request_check()
    else
      app:notify(err, true)
    end
  end
end

return M
```

- [ ] **Step 4: Create the Delivery Publish Review**

Create `ReaProjectLink/lib/reaprojectlink/ui/views/delivery_publish_review.lua`:

```lua
local view_models = require("reaprojectlink.ui.view_models")
local workflow = require("reaprojectlink.ui.workflow")

local M = {}

local function build(env, options)
  return env.services.delivery_publish.review(env.adapter, env.fs, options)
end

function M.open(env)
  local options = { publish_anyway = false }
  local review, err = build(env, options)
  if not review then
    env.app:notify(err, true)
    return
  end
  env.app:open_review("delivery_publish", { data = review, options = options })
end

local function refresh(env)
  local current = env.app.review
  local review, err = build(env, current.options)
  if review then current.data = review else env.app:notify(err, true) end
end

local function item_count(data)
  local count = 0
  for _, lane in ipairs(data.lanes) do count = count + #lane.clips end
  return count
end

-- Returns true when a decision changed and the Review must be rebuilt.
local function draw_issues(env, data, options)
  local c = env.c
  local changed = false
  if data.reference_blocker then c.notice("reference-blocker", "blocked", data.reference_blocker) end
  if data.save_as_blocker then
    local choice = c.notice("save-as", "warning",
      "This project was moved or saved under a new name. Is this the same delivery?",
      { "Continue existing", "Start new" })
    if choice then
      options.save_as_decision = choice == 1 and "continue" or "new"
      changed = true
    end
  end
  if data.has_unprocessed_fx and not options.publish_anyway then
    local choice = c.notice("unprocessed-fx", "warning",
      "Track or Take FX were found. Published audio won't include them.",
      { "Publish without FX..." })
    if choice == 1 and workflow.confirm(env.reaper, "Publish unprocessed media",
        "Detected Track FX or Take FX will not be included in the published media. Continue?") then
      options.publish_anyway = true
      changed = true
    end
  elseif data.has_unprocessed_fx then
    c.notice("unprocessed-fx-accepted", "warning", "Detected FX won't be included in the published audio.")
  end
  for _, lane in ipairs(data.lanes) do
    if lane.fx_blocked then
      c.notice("lane-fx-" .. lane.lane_id, "blocked", lane.display_name .. " has Track FX.")
    end
    for index, row in ipairs(lane.clips) do
      for blocker_index, blocker in ipairs(row.blockers) do
        local id = string.format("clip-%s-%d-%d", lane.lane_id, index, blocker_index)
        local text = string.format("%s: %s", row.display_name or "Unnamed item", blocker)
        if c.notice(id, "blocked", text, { "Select item" }) == 1 and row.clip.item_ref then
          env.adapter.select_items({ row.clip.item_ref })
        end
      end
    end
  end
  return changed
end

local function draw_declaration(env, data, options)
  if data.synchronized_reference_revision == 0 then return false end
  local c = env.c
  c.section("Checked against Reference")
  local choices = view_models.reference_declaration_options(
    data.synchronized_reference_revision, data.last_declared_reference_revision
  )
  local chosen = c.segmented("declared-reference", choices, data.reviewed_reference_revision)
  if chosen ~= data.reviewed_reference_revision then
    options.declared_reference_revision = chosen
    return true
  end
  return false
end

local function draw_details(env, data)
  local c, ImGui, ctx, colors = env.c, env.ImGui, env.ctx, env.theme.colors
  c.section("Items")
  for _, lane in ipairs(data.lanes) do
    local blocked = 0
    for _, row in ipairs(lane.clips) do
      if #row.blockers > 0 then blocked = blocked + 1 end
    end
    local detail = view_models.count(#lane.clips, "item")
    if blocked > 0 then detail = blocked .. " blocked · " .. detail end
    if c.begin_group("lane-" .. lane.lane_id, lane.display_name, detail,
        blocked > 0 and "blocked" or "neutral", blocked > 0 or lane.fx_blocked) then
      c.clipped(#lane.clips, function(index)
        local row = lane.clips[index]
        ImGui.TextColored(ctx, #row.blockers > 0 and colors.blocked or colors.text,
          row.display_name or "Unnamed item")
      end)
      c.end_group()
    end
  end
end

function M.draw(env)
  local c, app = env.c, env.app
  local review = app.review
  local data, options = review.data, review.options
  local stale = workflow.is_stale(env, data)
  local back, changed, refresh_clicked = false, false, false
  if c.begin_page("delivery-publish", true) then
    back = c.review_header(string.format("Publish Delivery r%d", data.delivery_revision),
      view_models.count(#data.lanes, "track") .. " · " .. view_models.count(item_count(data), "item"))
    workflow.draw_notices(env)
    if stale then
      refresh_clicked = c.stale("Project changed",
        "The project was edited after this review was made.", "Refresh review")
    else
      changed = draw_issues(env, data, options)
      changed = draw_declaration(env, data, options) or changed
      draw_details(env, data)
    end
  end
  local page = c.end_page()

  local summary, level = string.format("Publishes %s as Delivery r%d",
    view_models.count(item_count(data), "item"), data.delivery_revision), "neutral"
  if stale then
    summary = "Refresh the review to continue"
  elseif data.blocker_count > 0 then
    summary, level = view_models.blocked_summary(data.blocker_count, "publish"), "blocked"
  end
  local publish = c.footer(page, summary, level, "Publish", not stale and data.blocker_count == 0)

  if back then
    app:back()
  elseif changed or refresh_clicked then
    refresh(env)
  elseif publish then
    local result, err = env.services.delivery_publish.publish(data, env.adapter, env.fs, workflow.metadata())
    if result then
      local message, is_error = workflow.publish_message("Delivery", result.delivery_revision, result)
      app:back()
      app:notify(message, is_error)
    else
      app:notify(err, true)
      workflow.inspect_lock(env, data.package_root)
    end
  end
end

return M
```

- [ ] **Step 5: Run core tests to verify they pass**

Run: **Run core tests**. Expected: `PASS`.

- [ ] **Step 6: Commit**

```bash
git add ReaProjectLink/lib/reaprojectlink/ui/views/reference_update_review.lua ReaProjectLink/lib/reaprojectlink/ui/views/delivery_publish_review.lua tests/ui_modules_spec.lua
git commit -m "feat(ui): add Reference update and Delivery publish reviews"
```

---

### Task 9: Master Reviews

**Files:**
- Create: `ReaProjectLink/lib/reaprojectlink/ui/views/reference_publish_review.lua`
- Create: `ReaProjectLink/lib/reaprojectlink/ui/views/delivery_sync_review.lua`
- Modify: `tests/ui_modules_spec.lua`

- [ ] **Step 1: Register the modules in the spec**

Add to `MODULES` in `tests/ui_modules_spec.lua`:

```lua
  "reaprojectlink.ui.views.reference_publish_review",
  "reaprojectlink.ui.views.delivery_sync_review",
```

- [ ] **Step 2: Run core tests to verify the failure**

Run: **Run core tests**. Expected: `FAIL` with `module 'reaprojectlink.ui.views.reference_publish_review' not found`.

- [ ] **Step 3: Create the Reference Publish Review**

Create `ReaProjectLink/lib/reaprojectlink/ui/views/reference_publish_review.lua`:

```lua
local view_models = require("reaprojectlink.ui.view_models")
local workflow = require("reaprojectlink.ui.workflow")

local M = {}

local function build(env, options)
  return env.services.reference_publish.review(env.adapter, env.fs, options)
end

function M.open(env)
  local options = { publish_anyway = false }
  local review, err = build(env, options)
  if not review then
    env.app:notify(err, true)
    return
  end
  env.app:open_review("reference_publish", { data = review, options = options })
end

local function refresh(env)
  local current = env.app.review
  local review, err = build(env, current.options)
  if review then current.data = review else env.app:notify(err, true) end
end

local function draw_issues(env, data, options)
  local c = env.c
  local changed = false
  if data.save_as_blocker then
    local choice = c.notice("save-as", "warning",
      "This project was moved or saved under a new name. Is this the same Reference?",
      { "Continue existing", "Start new" })
    if choice then
      options.save_as_decision = choice == 1 and "continue" or "new"
      changed = true
    end
  end
  for index, blocker in ipairs(data.blockers or {}) do
    if blocker ~= data.save_as_blocker then c.notice("blocker-" .. index, "blocked", blocker) end
  end
  if data.unchanged and not options.publish_anyway then
    local choice = c.notice("unchanged", "warning",
      string.format("This Reference is identical to Reference r%d.", data.base_revision),
      { "Publish anyway..." })
    if choice == 1 and workflow.confirm(env.reaper, "Publish unchanged Reference",
        "Publish a new unchanged Reference revision? Source projects will still need to synchronize it.") then
      options.publish_anyway = true
      changed = true
    end
  end
  return changed
end

local function draw_details(env, data)
  local c = env.c
  c.section("Contents")
  if c.begin_group("reference-tracks", "Tracks", view_models.count(#data.lanes, "track"), "neutral", false) then
    for _, lane in ipairs(data.lanes) do
      c.key_value(lane.displayName, view_models.count(#(lane.items or {}), "item"))
    end
    c.end_group()
  end
  if c.begin_group("reference-markers", "Markers", view_models.count(#data.markers, "marker"), "neutral", false) then
    for _, marker in ipairs(data.markers) do c.muted(marker.name ~= "" and marker.name or "Unnamed marker") end
    c.end_group()
  end
  if c.begin_group("reference-regions", "Regions", view_models.count(#data.regions, "region"), "neutral", false) then
    for _, region in ipairs(data.regions) do c.muted(region.name ~= "" and region.name or "Unnamed region") end
    c.end_group()
  end
end

function M.draw(env)
  local c, app = env.c, env.app
  local review = app.review
  local data, options = review.data, review.options
  local stale = workflow.is_stale(env, data)
  local back, changed, refresh_clicked = false, false, false
  if c.begin_page("reference-publish", true) then
    back = c.review_header(string.format("Publish Reference r%d", data.reference_revision),
      view_models.count(#data.lanes, "track") .. " · " ..
        view_models.count(#data.markers + #data.regions, "marker"))
    workflow.draw_notices(env)
    if stale then
      refresh_clicked = c.stale("Project changed",
        "The project was edited after this review was made.", "Refresh review")
    else
      changed = draw_issues(env, data, options)
      draw_details(env, data)
    end
  end
  local page = c.end_page()

  local issues = data.blocker_count + (data.unchanged_blocker and 1 or 0)
  local summary, level = string.format("Publishes Reference r%d", data.reference_revision), "neutral"
  if stale then
    summary = "Refresh the review to continue"
  elseif issues > 0 then
    summary, level = view_models.blocked_summary(issues, "publish"), "blocked"
  end
  local publish = c.footer(page, summary, level, "Publish", not stale and issues == 0)

  if back then
    app:back()
  elseif changed or refresh_clicked then
    refresh(env)
  elseif publish then
    local result, err = env.services.reference_publish.publish(data, env.adapter, env.fs, workflow.metadata())
    if result then
      local message, is_error = workflow.publish_message("Reference", result.reference_revision, result)
      app:back()
      app:notify(message, is_error)
    else
      app:notify(err, true)
      workflow.inspect_lock(env, data.package_root)
    end
  end
end

return M
```

- [ ] **Step 4: Create the Delivery Import/Update Review**

Create `ReaProjectLink/lib/reaprojectlink/ui/views/delivery_sync_review.lua`:

```lua
local view_models = require("reaprojectlink.ui.view_models")
local workflow = require("reaprojectlink.ui.workflow")

local M = {}

local PARENTS = {
  { id = "top", label = "Top level" },
  { id = "selected", label = "Selected folder track" },
}

function M.open_import(env)
  local path = workflow.choose_json(env.reaper, "Select Source delivery.json")
  if not path then return end
  local review, err = env.services.delivery_import.review(env.adapter, env.fs, path)
  if not review then
    env.app:notify(err, true)
    return
  end
  env.app:open_review("delivery_import", {
    data = review, mappings = {}, row_errors = {}, allow_reference = false,
  })
end

-- On failure the current Review, if any, stays open.
function M.open_update(env, source_project_id, target_revision)
  local review, err = env.services.delivery_update.review(
    env.adapter, env.fs, source_project_id, target_revision
  )
  if not review then
    env.app:notify(err, true)
    return
  end
  env.app:open_review("delivery_update", {
    data = review, mappings = {}, rebindings = {}, row_errors = {},
    allow_reference = false, target_input = review.target_revision,
  })
end

local function draw_parent_choice(env, review)
  local ImGui, ctx, c = env.ImGui, env.ctx, env.c
  ImGui.AlignTextToFramePadding(ctx)
  c.inline_muted("New tracks go under")
  ImGui.SameLine(ctx)
  local chosen = c.segmented("parent", PARENTS, review.parent and "selected" or "top")
  if chosen == "selected" and not review.parent then
    local selected = env.adapter.selected_tracks()
    if #selected == 1 then
      review.parent, review.parent_error = selected[1], nil
    else
      review.parent_error = "Select exactly one folder track in REAPER first."
    end
  elseif chosen == "top" then
    review.parent, review.parent_error = nil, nil
  end
  if review.parent_error then c.notice("parent-error", "warning", review.parent_error) end
end

local function draw_mapping_table(env, lanes, review, default_kind)
  local ImGui, ctx, c, colors = env.ImGui, env.ctx, env.c, env.theme.colors
  c.section("Lanes")
  draw_parent_choice(env, review)
  local column = ImGui.GetContentRegionAvail(ctx) * 0.45
  for _, lane in ipairs(lanes) do
    ImGui.Separator(ctx)
    ImGui.AlignTextToFramePadding(ctx)
    ImGui.Text(ctx, lane.display_name)
    ImGui.SameLine(ctx, 0, 6)
    c.inline_muted(tostring(#lane.clips))
    ImGui.SameLine(ctx, column)
    local mapping = review.mappings[lane.lane_id]
    local chosen = c.dropdown("lane-" .. lane.lane_id,
      view_models.lane_mapping_label(mapping, default_kind, env.adapter.track_name),
      view_models.lane_mapping_options(lane))
    if chosen then
      local next_mapping, err = view_models.mapping_from_option(chosen, env.adapter.selected_tracks())
      if next_mapping then
        review.mappings[lane.lane_id] = next_mapping
        review.row_errors[lane.lane_id] = nil
      else
        review.row_errors[lane.lane_id] = err
      end
    end
    if lane.orphaned then c.small("Its target track was deleted. Map it again to restore its items.") end
    if review.row_errors[lane.lane_id] then c.colored(review.row_errors[lane.lane_id], colors.warning) end
  end
end

local function collect_mappings(lanes, review, default_kind)
  local mappings = {}
  for _, lane in ipairs(lanes) do
    mappings[lane.lane_id] = review.mappings[lane.lane_id] or { kind = default_kind }
  end
  return view_models.with_parent(mappings, review.parent)
end

local function draw_reference_issue(env, data, review, verb)
  local c = env.c
  if data.reference_error then c.notice("reference-error", "blocked", data.reference_error) end
  if not data.reference_warning then return end
  if review.allow_reference then
    c.notice("reference-warning", "warning",
      "Made against a different Reference revision. Continuing anyway.")
  elseif c.notice("reference-warning", "warning",
      "This delivery was made against a different Reference revision.", { verb .. " anyway" }) == 1 then
    review.allow_reference = true
  end
end

local function draw_clip_issue(env, id, lane_name, clip)
  if clip.blocked then
    env.c.notice(id, "blocked", string.format("%s: %s", lane_name, clip.error))
  end
end

local function draw_import(env, review)
  local c, app = env.c, env.app
  local data = review.data
  local back = false
  if c.begin_page("delivery-import", true) then
    back = c.review_header("Add " .. data.snapshot.sourceProjectName,
      string.format("Delivery r%d · made against Reference r%d",
        data.pointer.latestDeliveryRevision, data.snapshot.reference.reviewedRevision))
    workflow.draw_notices(env)
    draw_reference_issue(env, data, review, "Import")
    for lane_index, lane in ipairs(data.lanes) do
      for clip_index, clip in ipairs(lane.clips) do
        draw_clip_issue(env, "clip-" .. lane_index .. "-" .. clip_index, lane.display_name, clip)
      end
    end
    draw_mapping_table(env, data.lanes, review, "create")
  end
  local page = c.end_page()

  local ready = data.blocker_count == 0 and (not data.reference_warning or review.allow_reference)
  local summary, level = view_models.mapping_summary(data.lanes, review.mappings, "create"), "neutral"
  if data.blocker_count > 0 then
    summary, level = view_models.blocked_summary(data.blocker_count, "import"), "blocked"
  end
  local import = c.footer(page, summary, level, "Import", ready)

  if back then
    app:back()
  elseif import then
    local result, err = env.services.delivery_import.apply(data, env.adapter, {
      mappings = collect_mappings(data.lanes, review, "create"),
      allow_reference_revision_mismatch = review.allow_reference,
    })
    if result then
      app:back()
      app:notify(string.format("Imported %s on %s.",
        view_models.count(result.created_items, "item"),
        view_models.count(result.created_tracks, "new track")))
      app:request_check()
    else
      app:notify(err, true)
    end
  end
end

local function draw_target(env, review)
  local ImGui, ctx, c = env.ImGui, env.ctx, env.c
  c.section("Revision")
  ImGui.SetNextItemWidth(ctx, 120)
  local changed, value = ImGui.InputInt(ctx, "##target-revision", review.target_input)
  if changed then review.target_input = value end
  ImGui.SameLine(ctx)
  local load = c.button("Load")
  c.small(string.format("Latest is r%d", review.data.latest_revision))
  return load
end

local function draw_bound_lanes(env, review)
  local ImGui, ctx, c = env.ImGui, env.ctx, env.c
  local lanes = review.data.bound_lanes
  if #lanes == 0 then return end
  c.section("Mapped lanes")
  local column = ImGui.GetContentRegionAvail(ctx) * 0.45
  for _, lane in ipairs(lanes) do
    ImGui.Separator(ctx)
    ImGui.AlignTextToFramePadding(ctx)
    ImGui.Text(ctx, lane.display_name)
    ImGui.SameLine(ctx, column)
    local rebound = review.rebindings[lane.lane_id]
    local preview = rebound and env.adapter.track_name(rebound) or lane.track_name
    local chosen = c.dropdown("bound-" .. lane.lane_id, preview, {
      { id = "current", label = "Keep " .. lane.track_name },
      { id = "selected", label = "Selected track" },
    })
    if chosen and chosen.id == "current" then
      review.rebindings[lane.lane_id] = nil
      review.row_errors[lane.lane_id] = nil
    elseif chosen then
      local mapping, err = view_models.mapping_from_option(chosen, env.adapter.selected_tracks())
      review.rebindings[lane.lane_id] = mapping and mapping.track_ref or rebound
      review.row_errors[lane.lane_id] = err
    end
    if review.row_errors[lane.lane_id] then
      c.colored(review.row_errors[lane.lane_id], env.theme.colors.warning)
    end
  end
end

local function draw_update(env, review)
  local c, app = env.c, env.app
  local data = review.data
  local back, load = false, false
  if c.begin_page("delivery-update", true) then
    back = c.review_header(string.format("Sync %s to r%d",
      data.target_snapshot.sourceProjectName, data.target_revision),
      string.format("Replaces %s with %s",
        view_models.count(data.replacement_count, "item"),
        view_models.count(data.source_item_count, "item")))
    workflow.draw_notices(env)
    draw_reference_issue(env, data, review, "Sync")
    for index, clip in ipairs(data.additions) do
      draw_clip_issue(env, "addition-" .. index, clip.lane_display_name, clip)
    end
    for lane_index, lane in ipairs(data.unmapped_lanes) do
      for clip_index, clip in ipairs(lane.clips) do
        draw_clip_issue(env, "unmapped-" .. lane_index .. "-" .. clip_index, lane.display_name, clip)
      end
    end
    load = draw_target(env, review)
    if #data.unmapped_lanes > 0 then draw_mapping_table(env, data.unmapped_lanes, review, "unmapped") end
    draw_bound_lanes(env, review)
  end
  local page = c.end_page()

  local ready = data.blocker_count == 0 and (not data.reference_warning or review.allow_reference)
  local summary, level = string.format("Syncs Delivery r%d", data.target_revision), "neutral"
  if data.blocker_count > 0 then
    summary, level = view_models.blocked_summary(data.blocker_count, "sync"), "blocked"
  elseif data.pending_count == 0 then
    summary = "Nothing to sync"
  end
  local sync = c.footer(page, summary, level, "Sync", ready)

  if back then
    app:back()
  elseif load then
    M.open_update(env, data.source_project_id, review.target_input)
  elseif sync then
    local result, err = env.services.delivery_update.apply(data, env.adapter, {
      lane_mappings = collect_mappings(data.unmapped_lanes, review, "unmapped"),
      lane_rebindings = review.rebindings,
      allow_reference_revision_mismatch = review.allow_reference,
    })
    if result then
      app:back()
      app:notify(string.format("Synced Delivery r%d: replaced %s with %s.", data.target_revision,
        view_models.count(result.deleted_items, "item"), view_models.count(result.new_items, "item")))
      app:request_check()
    else
      app:notify(err, true)
    end
  end
end

function M.draw(env)
  local review = env.app.review
  if review.kind == "delivery_import" then draw_import(env, review) else draw_update(env, review) end
end

return M
```

- [ ] **Step 5: Run core tests to verify they pass**

Run: **Run core tests**. Expected: `PASS`.

- [ ] **Step 6: Commit**

```bash
git add ReaProjectLink/lib/reaprojectlink/ui/views/reference_publish_review.lua ReaProjectLink/lib/reaprojectlink/ui/views/delivery_sync_review.lua tests/ui_modules_spec.lua
git commit -m "feat(ui): add Reference publish and Delivery sync reviews"
```

---

### Task 10: Main panels, setup, and settings

**Files:**
- Create: `ReaProjectLink/lib/reaprojectlink/ui/views/setup.lua`
- Create: `ReaProjectLink/lib/reaprojectlink/ui/views/settings.lua`
- Create: `ReaProjectLink/lib/reaprojectlink/ui/views/source_main.lua`
- Create: `ReaProjectLink/lib/reaprojectlink/ui/views/master_main.lua`
- Modify: `tests/ui_modules_spec.lua`

- [ ] **Step 1: Register the modules in the spec**

Add to `MODULES` in `tests/ui_modules_spec.lua`:

```lua
  "reaprojectlink.ui.views.setup",
  "reaprojectlink.ui.views.settings",
  "reaprojectlink.ui.views.source_main",
  "reaprojectlink.ui.views.master_main",
```

- [ ] **Step 2: Run core tests to verify the failure**

Run: **Run core tests**. Expected: `FAIL` with `module 'reaprojectlink.ui.views.setup' not found`.

- [ ] **Step 3: Create the first-run setup view**

Create `ReaProjectLink/lib/reaprojectlink/ui/views/setup.lua`:

```lua
local workflow = require("reaprojectlink.ui.workflow")

local M = {}

local function choice(env, id, width, title, text, label)
  local c = env.c
  local clicked = false
  if c.begin_card(id, width, false) then
    c.heading(title)
    c.muted(text)
    clicked = c.button(label .. "##" .. id)
  end
  c.end_card()
  return clicked
end

function M.draw(env, state)
  local ImGui, ctx, c, app = env.ImGui, env.ctx, env.c, env.app
  local service = env.services.project_service
  c.title("Set up ReaProjectLink")
  c.muted("Choose what this REAPER project is.")
  workflow.draw_notices(env, state)
  local width, side_by_side = c.card_width()
  local source = choice(env, "setup-source", width, "This is a department project",
    "Dialogue, music, or sound design. You publish bounced audio for the mix project.",
    "Set up as Source")
  if side_by_side then ImGui.SameLine(ctx, 0, 12) end
  local master = choice(env, "setup-master", width, "This is the mix project",
    "You publish the Reference and bring in deliveries from each department.",
    "Set up as Master")
  if source then
    local result, err = service.initialize_source(env.adapter)
    workflow.report(env, result, err, "Source project set up.")
  elseif master then
    local result, err = service.initialize_master(env.adapter)
    workflow.report(env, result, err, "Master project set up.")
  end
  if source or master then app:request_check() end
end

return M
```

- [ ] **Step 4: Create the settings view**

Create `ReaProjectLink/lib/reaprojectlink/ui/views/settings.lua`:

```lua
local constants = require("reaprojectlink.constants")
local view_models = require("reaprojectlink.ui.view_models")
local workflow = require("reaprojectlink.ui.workflow")

local M = {}

local THEMES = {
  { id = "auto", label = "Auto" },
  { id = "light", label = "Light" },
  { id = "dark", label = "Dark" },
}

local function draw_reference(env, state)
  local ImGui, ctx, c, adapter = env.ImGui, env.ctx, env.c, env.adapter
  c.section("Reference")
  c.copy_value("reference-path", "reference.json", state.reference_manifest_path or "Not connected")
  if c.button("Change...") then workflow.choose_reference(env) end
  local mode = adapter.get_project_value(constants.PROJECT_KEYS.reference_alignment_mode) or "mirror"
  local changed, mirror = ImGui.Checkbox(ctx, "Mirror Master timeline", mode ~= "relative")
  if changed then
    local result, err = env.services.reference_subscription.set_alignment_mode(
      adapter, mirror and "mirror" or "relative"
    )
    workflow.report(env, result, err, mirror and "Mirroring the Master timeline." or
      "Aligning relative to Reference Start.")
  end
end

function M.draw(env, state)
  local ImGui, ctx, c, theme, adapter = env.ImGui, env.ctx, env.c, env.theme, env.adapter
  local source = state.project_type == constants.PROJECT_TYPES.source
  local back = false
  if c.begin_page("settings", false) then
    back = c.review_header("Settings")
    workflow.draw_notices(env)
    c.section("Project")
    c.copy_value("project-name", "Name", view_models.project_name(state.path))
    c.copy_value("project-path", "Project file", state.path ~= "" and state.path or "Not saved")
    c.copy_value("project-id", "Project ID", state.project_id or "Not assigned")
    if source then
      c.copy_value("delivery-id", "Delivery ID",
        adapter.get_project_value(constants.PROJECT_KEYS.delivery_id) or "Not assigned")
      draw_reference(env, state)
    else
      c.copy_value("reference-id", "Reference ID", state.reference_id or "Not published")
    end
    c.section("Appearance")
    ImGui.AlignTextToFramePadding(ctx)
    c.inline_muted("Theme")
    ImGui.SameLine(ctx, 130)
    local chosen = c.segmented("theme", THEMES, theme.preference)
    if chosen ~= theme.preference then theme:set_preference(chosen) end
    c.section("About")
    local _, _, reaimgui_version = ImGui.GetVersion()
    c.key_value("ReaProjectLink", env.version)
    c.key_value("REAPER", env.reaper.GetAppVersion())
    c.key_value("ReaImGui", tostring(reaimgui_version))
  end
  c.end_page()
  if back then env.app:back() end
end

return M
```

- [ ] **Step 5: Create the Source main panel**

Create `ReaProjectLink/lib/reaprojectlink/ui/views/source_main.lua`:

```lua
local view_models = require("reaprojectlink.ui.view_models")
local workflow = require("reaprojectlink.ui.workflow")
local card = require("reaprojectlink.ui.views.card")
local header = require("reaprojectlink.ui.views.header")
local reference_update_review = require("reaprojectlink.ui.views.reference_update_review")
local delivery_publish_review = require("reaprojectlink.ui.views.delivery_publish_review")

local M = {}

local REFERENCE_MENU = {
  { id = "detach_items", label = "Detach selected items..." },
  { id = "detach_tracks", label = "Detach selected tracks..." },
}

local DELIVERY_MENU = {
  { id = "register_tracks", label = "Register selected tracks" },
  { id = "unregister_tracks", label = "Unregister selected tracks..." },
}

local function input(env, state)
  local lanes = env.services.project_service.delivery_tracks(env.adapter)
  local items = 0
  for _, lane in ipairs(lanes) do items = items + lane.item_count end
  return {
    subscribed = state.reference_manifest_path ~= nil and state.reference_manifest_path ~= "",
    synchronized = state.synchronized_reference_revision,
    check = env.app.checks.reference,
    media_error = env.app.media_error,
    track_count = #lanes,
    item_count = items,
    delivery_revision = state.delivery_revision,
  }
end

local function handle(env, action)
  local services, adapter, app = env.services, env.adapter, env.app
  if action == "choose_reference" then
    workflow.choose_reference(env)
  elseif action == "retry" then
    app:request_check()
  elseif action == "review_update" then
    reference_update_review.open(env)
  elseif action == "review_publish" then
    delivery_publish_review.open(env)
  elseif action == "register_tracks" then
    local result, err = services.project_service.register_selected_tracks(adapter)
    workflow.report(env, result, err, function(value)
      return string.format("Registered %s.", view_models.count(value.added, "track"))
    end)
  elseif action == "unregister_tracks" then
    if workflow.confirm(env.reaper, "Unregister delivery tracks",
        "Stop publishing the selected tracks? Their items stay in the project.") then
      local result, err = services.project_service.unregister_selected_tracks(adapter)
      workflow.report(env, result, err, function(value)
        return string.format("Unregistered %s.", view_models.count(value.removed, "track"))
      end)
    end
  elseif action == "detach_items" then
    if workflow.confirm(env.reaper, "Detach Reference items",
        "Detach the selected Reference items? Later Reference updates won't change them.") then
      local result, err = services.reference_subscription.detach_selected_reference_items(adapter)
      workflow.report(env, result, err, function(value)
        return string.format("Detached %s.", view_models.count(value.detached, "item"))
      end)
    end
  elseif action == "detach_tracks" then
    if workflow.confirm(env.reaper, "Detach Reference tracks",
        "Detach the selected Reference tracks? Later Reference updates won't change them.") then
      local result, err = services.reference_subscription.detach_selected_reference_tracks(adapter)
      workflow.report(env, result, err, function(value)
        return string.format("Detached %s.", view_models.count(value.detached, "track"))
      end)
    end
  end
end

function M.draw(env, state)
  local ImGui, ctx, c = env.ImGui, env.ctx, env.c
  local values = input(env, state)
  local cards = view_models.source_cards(values)
  header.draw(env, state, "Source")
  local width, side_by_side = c.card_width()
  local reference_action = card.draw(env, "source-reference", "film", "Reference", cards.reference,
    cards.highlight == "reference", width, values.subscribed and REFERENCE_MENU or nil)
  if side_by_side then ImGui.SameLine(ctx, 0, 12) end
  local delivery_action = card.draw(env, "source-delivery", "upload", "Delivery", cards.delivery,
    cards.highlight == "delivery", width, values.track_count > 0 and DELIVERY_MENU or nil)
  local action = reference_action or delivery_action
  if action then handle(env, action) end
end

return M
```

- [ ] **Step 6: Create the Master main panel**

Create `ReaProjectLink/lib/reaprojectlink/ui/views/master_main.lua`:

```lua
local view_models = require("reaprojectlink.ui.view_models")
local workflow = require("reaprojectlink.ui.workflow")
local checks = require("reaprojectlink.ui.checks")
local card = require("reaprojectlink.ui.views.card")
local header = require("reaprojectlink.ui.views.header")
local reference_publish_review = require("reaprojectlink.ui.views.reference_publish_review")
local delivery_sync_review = require("reaprojectlink.ui.views.delivery_sync_review")

local M = {}

local REFERENCE_MENU = {
  { id = "register_tracks", label = "Register selected tracks" },
  { id = "unregister_tracks", label = "Unregister selected tracks" },
  { separator = true },
  { id = "register_markers", label = "Register selected markers/regions" },
  { id = "unregister_markers", label = "Unregister selected markers/regions" },
  { id = "set_start", label = "Set selected marker as Reference Start" },
  { separator = true },
  { id = "reset_items", label = "Treat selected items as new..." },
  { id = "reset_tracks", label = "Treat selected tracks as new..." },
}

local ROW_MENU = {
  { id = "sync_other", label = "Sync to another revision..." },
  { id = "remove", label = "Remove subscription..." },
}

local function input(env, state)
  local services, adapter, app = env.services, env.adapter, env.app
  local tracks = services.reference_publish.reference_tracks(adapter)
  local markers = 0
  for _, entry in ipairs(services.reference_publish.timeline_entries(adapter) or {}) do
    if entry.registered then markers = markers + 1 end
  end
  local rows = {}
  for _, entry in ipairs(checks.subscriptions(adapter)) do
    local unmapped = 0
    for _, binding in ipairs(entry.lanes or {}) do
      if binding.unmapped then unmapped = unmapped + 1 end
    end
    table.insert(rows, {
      id = entry.sourceProjectId,
      name = view_models.subscription_name(entry),
      accepted = entry.acceptedDeliveryRevision or 0,
      unmapped_count = unmapped,
      check = app.checks.deliveries[entry.sourceProjectId],
    })
  end
  return {
    track_count = #tracks,
    marker_count = markers,
    reference_revision = state.reference_revision,
    rows = rows,
  }
end

-- Moving a managed Item away from its bound Track prompts once (D083).
local function confirm_moved_items(env)
  local adapter, app = env.adapter, env.app
  local change_count = adapter.project_change_count()
  if change_count == app.moved_items_change_count then return end
  app.moved_items_change_count = change_count
  local moved = env.services.delivery_update.moved_instances(adapter)
  if #moved == 0 then return end
  local confirmed = env.reaper.ShowMessageBox(
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
    local result, err = env.services.delivery_update.detach_many(adapter, moved)
    workflow.report(env, result, err, function(value)
      return string.format("Kept %s as local content.", view_models.count(value.detached, "moved item"))
    end)
    app.moved_items_change_count = adapter.project_change_count()
  end
end

local function run(env, result, err, success)
  workflow.report(env, result, err, success)
end

local function handle_reference(env, action)
  local publish, adapter = env.services.reference_publish, env.adapter
  if action == "review_publish" then
    reference_publish_review.open(env)
  elseif action == "register_tracks" then
    local result, err = publish.register_selected_tracks(adapter)
    run(env, result, err, function(value)
      return "Registered " .. view_models.count(value.added, "Reference track") .. "."
    end)
  elseif action == "unregister_tracks" then
    local result, err = publish.unregister_selected_tracks(adapter)
    run(env, result, err, function(value)
      return "Unregistered " .. view_models.count(value.removed, "Reference track") .. "."
    end)
  elseif action == "register_markers" then
    local result, err = publish.register_selected_timeline_entries(adapter)
    run(env, result, err, function(value)
      return string.format("Registered %d markers/regions.", value.added)
    end)
  elseif action == "unregister_markers" then
    local result, err = publish.unregister_selected_timeline_entries(adapter)
    run(env, result, err, function(value)
      return string.format("Unregistered %d markers/regions.", value.removed)
    end)
  elseif action == "set_start" then
    local result, err = publish.set_selected_reference_start(adapter)
    run(env, result, err, "Reference Start set.")
  elseif action == "reset_items" then
    if workflow.confirm(env.reaper, "Treat Reference items as new",
        "Assign new identities? Source projects will see these as new Reference items.") then
      local result, err = publish.reset_selected_reference_items(adapter)
      run(env, result, err, function(value)
        return "Assigned new identities to " .. view_models.count(value.reset, "item") .. "."
      end)
    end
  elseif action == "reset_tracks" then
    if workflow.confirm(env.reaper, "Treat Reference tracks as new",
        "Assign new identities? Source projects will see these as new Reference tracks.") then
      local result, err = publish.reset_selected_reference_tracks(adapter)
      run(env, result, err, function(value)
        return "Assigned new identities to " .. view_models.count(value.reset, "track") .. "."
      end)
    end
  end
end

local function handle_delivery(env, action)
  local app = env.app
  if action.id == "add_delivery" then
    delivery_sync_review.open_import(env)
  elseif action.id == "sync" or action.id == "map_lanes" or action.id == "sync_other" then
    delivery_sync_review.open_update(env, action.row.id)
  elseif action.id == "retry" then
    app:request_check()
  elseif action.id == "remove" then
    if workflow.confirm(env.reaper, "Remove subscription",
        string.format("Stop following %s? Its tracks and items stay in this project.", action.row.name)) then
      local result, err = env.services.delivery_import.remove_subscription(env.adapter, action.row.id)
      run(env, result, err, "Subscription removed. Tracks and items were kept.")
      app:request_check()
    end
  end
end

local function draw_row(env, row, primary)
  local ImGui, ctx, c = env.ImGui, env.ctx, env.c
  local chosen
  ImGui.Separator(ctx)
  ImGui.AlignTextToFramePadding(ctx)
  ImGui.Text(ctx, row.name)
  local width = c.status_width(row.status) + 8 + ImGui.GetFrameHeight(ctx)
  if row.action then width = width + c.button_width(row.action.label) + 8 end
  c.same_line_right(width)
  c.inline_status(row.status, row.level)
  if row.action then
    ImGui.SameLine(ctx, 0, 8)
    if c.button(row.action.label .. "##" .. row.id, primary and "primary" or nil) then
      chosen = { id = row.action.id, row = row }
    end
  end
  ImGui.SameLine(ctx, 0, 8)
  local menu = c.menu("row-menu-" .. row.id, ROW_MENU, false)
  if menu then chosen = { id = menu, row = row } end
  if row.note then env.c.small(row.note) end
  return chosen
end

local function draw_deliveries(env, cards, width)
  local ImGui, ctx, c = env.ImGui, env.ctx, env.c
  local highlighted = cards.highlight == "deliveries"
  local chosen
  if c.begin_card("master-deliveries", width, highlighted) then
    c.card_header("download", "Deliveries")
    c.same_line_right(ImGui.GetFrameHeight(ctx))
    if c.icon_button("add-delivery", "plus", "Add delivery") then chosen = { id = "add_delivery" } end
    if #cards.rows == 0 then
      local empty = cards.deliveries_empty
      c.status(empty.status, empty.level)
      c.small(empty.note)
      if c.button(empty.action.label, highlighted and "primary" or nil) then
        chosen = { id = empty.action.id }
      end
    end
    local primary_used = false
    for _, row in ipairs(cards.rows) do
      local primary = highlighted and row.attention and not primary_used
      primary_used = primary_used or primary
      chosen = draw_row(env, row, primary) or chosen
    end
  end
  c.end_card()
  return chosen
end

function M.draw(env, state)
  local ImGui, ctx, c = env.ImGui, env.ctx, env.c
  confirm_moved_items(env)
  local cards = view_models.master_cards(input(env, state))
  header.draw(env, state, "Master", cards.all_current and "All up to date" or nil)
  local width, side_by_side = c.card_width()
  local reference_action = card.draw(env, "master-reference", "film", "Reference", cards.reference,
    cards.highlight == "reference", width, REFERENCE_MENU)
  if side_by_side then ImGui.SameLine(ctx, 0, 12) end
  local delivery_action = draw_deliveries(env, cards, width)
  if reference_action then handle_reference(env, reference_action) end
  if delivery_action then handle_delivery(env, delivery_action) end
end

return M
```

Note: each subscription row always has a `···` menu, and rows that need attention also have an action button. The spec says "either an action button or a `···` menu"; Task 12 updates the spec line, because otherwise a broken subscription could never be removed.

- [ ] **Step 7: Run core tests to verify they pass**

Run: **Run core tests**. Expected: `PASS`.

- [ ] **Step 8: Commit**

```bash
git add ReaProjectLink/lib/reaprojectlink/ui/views/setup.lua ReaProjectLink/lib/reaprojectlink/ui/views/settings.lua ReaProjectLink/lib/reaprojectlink/ui/views/source_main.lua ReaProjectLink/lib/reaprojectlink/ui/views/master_main.lua tests/ui_modules_spec.lua
git commit -m "feat(ui): add main panels, setup and settings views"
```

---

### Task 11: App shell, new entry point, smoke scenarios

**Files:**
- Create: `ReaProjectLink/lib/reaprojectlink/ui/app.lua`
- Rewrite: `ReaProjectLink/ReaProjectLink.lua`
- Delete: `ReaProjectLink/lib/reaprojectlink/ui.lua`
- Create: `tests/ui_smoke_scenarios.lua`
- Rewrite: `tests/run_ui_smoke.lua`
- Modify: `tests/ui_modules_spec.lua`

- [ ] **Step 1: Register the shell in the spec**

Add to `MODULES` in `tests/ui_modules_spec.lua`:

```lua
  "reaprojectlink.ui.app",
```

- [ ] **Step 2: Run core tests to verify the failure**

Run: **Run core tests**. Expected: `FAIL` with `module 'reaprojectlink.ui.app' not found`.

- [ ] **Step 3: Create the shell**

Create `ReaProjectLink/lib/reaprojectlink/ui/app.lua`:

```lua
local constants = require("reaprojectlink.constants")
local theme_module = require("reaprojectlink.ui.theme")
local components = require("reaprojectlink.ui.components")
local app_state = require("reaprojectlink.ui.app_state")
local checks = require("reaprojectlink.ui.checks")
local setup = require("reaprojectlink.ui.views.setup")
local settings = require("reaprojectlink.ui.views.settings")
local source_main = require("reaprojectlink.ui.views.source_main")
local master_main = require("reaprojectlink.ui.views.master_main")

local REVIEWS = {
  reference_update = require("reaprojectlink.ui.views.reference_update_review"),
  delivery_publish = require("reaprojectlink.ui.views.delivery_publish_review"),
  reference_publish = require("reaprojectlink.ui.views.reference_publish_review"),
  delivery_import = require("reaprojectlink.ui.views.delivery_sync_review"),
  delivery_update = require("reaprojectlink.ui.views.delivery_sync_review"),
}

local M = {}

-- deps: ImGui, ctx, reaper, adapter, fs, services, version.
function M.create(deps)
  local ImGui, ctx, adapter = deps.ImGui, deps.ctx, deps.adapter
  local theme = theme_module.create(ImGui, ctx, deps.reaper)
  local env = {
    ImGui = ImGui,
    ctx = ctx,
    reaper = deps.reaper,
    adapter = adapter,
    fs = deps.fs,
    services = deps.services,
    version = deps.version,
    theme = theme,
    c = components.create(ImGui, ctx, theme),
    app = app_state.new(deps.reaper.time_precise),
  }
  local shell = { open = true, env = env }
  local project_token = adapter.project_token()
  local fixed_width
  env.app:request_check()

  local function run_due_check(state)
    if not env.app:check_due() then return end
    if state.project_type == constants.PROJECT_TYPES.source then
      checks.run_source(env)
    elseif state.project_type == constants.PROJECT_TYPES.master then
      checks.run_master(env)
    end
    env.app:finish_check()
  end

  local function draw_body(state)
    local app = env.app
    if not state.project_type or state.project_type == "" then
      setup.draw(env, state)
    elseif app.view == "settings" then
      settings.draw(env, state)
    elseif app.review and REVIEWS[app.review.kind] then
      REVIEWS[app.review.kind].draw(env, state)
    elseif state.project_type == constants.PROJECT_TYPES.source then
      source_main.draw(env, state)
    elseif state.project_type == constants.PROJECT_TYPES.master then
      master_main.draw(env, state)
    else
      ImGui.TextWrapped(ctx, "Unsupported project type: " .. tostring(state.project_type))
    end
  end

  function shell.draw()
    local token = adapter.project_token()
    if token ~= project_token then
      project_token = token
      env.app:reset()
      env.app:request_check()
    end
    theme:refresh()
    if fixed_width then
      ImGui.SetNextWindowSize(ctx, fixed_width, 720, ImGui.Cond_Always)
    else
      ImGui.SetNextWindowSize(ctx, 1040, 720, ImGui.Cond_FirstUseEver)
    end
    theme:push()
    local visible
    visible, shell.open = ImGui.Begin(ctx, "ReaProjectLink", shell.open)
    if visible then
      ImGui.PushFont(ctx, theme.fonts.body)
      local state = deps.services.project_service.project_state(adapter)
      run_due_check(state)
      draw_body(state)
      ImGui.PopFont(ctx)
      -- ReaImGui only accepts End() when Begin() returned true, unlike Dear ImGui.
      ImGui.End(ctx)
    end
    theme:pop()
  end

  -- Prepares one smoke-test frame: project type, theme, width, and view.
  function shell.apply_smoke(scenario)
    deps.reaper.SetProjExtState(0, constants.EXTENSION_NAME,
      constants.PROJECT_KEYS.project_type, scenario.project_type)
    theme:use(scenario.theme)
    fixed_width = scenario.width
    env.app:reset()
    if scenario.view == "settings" then
      env.app:open_settings()
    elseif scenario.review then
      env.app:open_review(scenario.review.kind, scenario.review.fields())
    end
  end

  return shell
end

return M
```

- [ ] **Step 4: Rewrite the entry point**

Replace the entire contents of `ReaProjectLink/ReaProjectLink.lua` with:

```lua
-- @description ReaProjectLink
-- @version 0.1.0
-- @author ReaProjectLink contributors
-- @changelog
--   Initial release.
-- @about
--   Source-Master project coordination for REAPER on shared storage.
--
--   Requires REAPER 7.74 or newer and ReaImGui 0.9 or newer (install ReaImGui
--   through ReaPack).
-- @link GitHub https://github.com/SounDoer/ReaProjectLink
-- @provides
--   [nomain] lib/reaprojectlink/*.lua
--   [nomain] lib/reaprojectlink/ui/*.lua
--   [nomain] lib/reaprojectlink/ui/views/*.lua

local source = debug.getinfo(1, "S").source:sub(2)
local script_dir = source:match("^(.*)[/\\]")
if not script_dir then
  reaper.ShowMessageBox("Could not resolve the script path.", "ReaProjectLink", 0)
  return
end
package.path = script_dir .. "/lib/?.lua;" .. package.path
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

local function script_version()
  local file = io.open(source, "r")
  if not file then return "unknown" end
  local header = file:read(512) or ""
  file:close()
  return header:match("@version%s+(%S+)") or "unknown"
end

local ctx = ImGui.CreateContext("ReaProjectLink")
local shell = require("reaprojectlink.ui.app").create({
  ImGui = ImGui,
  ctx = ctx,
  reaper = reaper,
  adapter = require("reaprojectlink.reaper_adapter"),
  fs = require("reaprojectlink.filesystem").create(reaper),
  version = script_version(),
  services = {
    project_service = require("reaprojectlink.project_service"),
    reference_subscription = require("reaprojectlink.reference_subscription"),
    reference_publish = require("reaprojectlink.reference_publish").create(),
    delivery_publish = require("reaprojectlink.delivery_publish").create(),
    delivery_import = require("reaprojectlink.delivery_import"),
    delivery_update = require("reaprojectlink.delivery_update"),
  },
})

-- tests/run_ui_smoke.lua sets REAPROJECTLINK_SMOKE_SCENARIOS before loading
-- this script; each scenario is rendered for one frame.
local smoke_path = os.getenv("REAPROJECTLINK_UI_SMOKE_RESULT")
local smoke_scenarios = REAPROJECTLINK_SMOKE_SCENARIOS or {}
local smoke_frame = 0

local function finish_smoke(ok, err)
  local file = io.open(smoke_path, "w")
  if file then
    file:write(ok and string.format("PASS ReaProjectLink UI frames (%d scenarios)\n", #smoke_scenarios) or
      ("FAIL\n" .. tostring(err) .. "\n"))
    file:close()
  end
  shell.open = false
  reaper.Main_OnCommand(40004, 0)
end

local function loop()
  if smoke_path then
    smoke_frame = smoke_frame + 1
    local scenario = smoke_scenarios[smoke_frame]
    if scenario then shell.apply_smoke(scenario) end
  end
  local ok, err = xpcall(shell.draw, debug.traceback)
  if smoke_path then
    if not ok or smoke_frame > #smoke_scenarios then
      finish_smoke(ok, err)
      return
    end
  elseif not ok then
    reaper.ShowConsoleMsg("ReaProjectLink error:\n" .. tostring(err) .. "\n")
    reaper.ShowMessageBox(tostring(err), "ReaProjectLink error", 0)
    return
  end
  if shell.open then reaper.defer(loop) end
end

reaper.atexit(function()
  if ctx and reaper.ImGui_DestroyContext then reaper.ImGui_DestroyContext(ctx) end
  ctx = nil
end)
reaper.defer(loop)
```

- [ ] **Step 5: Delete the old UI helper**

```bash
git rm ReaProjectLink/lib/reaprojectlink/ui.lua
```

Confirm nothing else requires it: `git grep -n 'require("reaprojectlink.ui")' -- ReaProjectLink tests` returns no matches.

- [ ] **Step 6: Create the smoke scenarios**

Create `tests/ui_smoke_scenarios.lua`:

```lua
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
```

- [ ] **Step 7: Rewrite the smoke runner**

Replace the entire contents of `tests/run_ui_smoke.lua` with:

```lua
local source = debug.getinfo(1, "S").source:sub(2)
local tests_dir = assert(source:match("^(.*)[/\\]"))
local root = assert(tests_dir:match("^(.*)[/\\]tests$"))

-- Read by ReaProjectLink.lua only when REAPROJECTLINK_UI_SMOKE_RESULT is set.
REAPROJECTLINK_SMOKE_SCENARIOS = dofile(root .. "/tests/ui_smoke_scenarios.lua")
dofile(root .. "/ReaProjectLink/ReaProjectLink.lua")
```

- [ ] **Step 8: Run core tests**

Run: **Run core tests**. Expected: `PASS`.

- [ ] **Step 9: Run the UI smoke test**

Run: **Run UI smoke**. Expected: `PASS ReaProjectLink UI frames (40 scenarios)`.

If it prints `FAIL` with a traceback, fix the view named in the traceback. Common causes: an unbalanced Push/Pop (count every `PushStyleColor`/`PushStyleVar`/`PushFont` against its pop) or a fixture missing a field the view reads (add the field to the fixture only if the real domain Review also returns it; otherwise fix the view).

- [ ] **Step 10: Manual check in REAPER**

Start REAPER normally, open a saved empty project, and run `ReaProjectLink/ReaProjectLink.lua` from the Action List. Verify:

1. The setup view shows two cards side by side; narrowing the window below ~560 px stacks them.
2. `Set up as Source` shows the Source main panel with `Not connected` highlighted in the Reference card.
3. The gear opens Settings; Theme `Light`/`Dark` switches colors immediately; `Auto` follows REAPER's theme; Back returns.
4. Dock the window narrow (~320 px): cards stack, the header's right side wraps under the title, no horizontal scrollbar.
5. Card heights fit their content (no clipped last line). If a card is cut off, ReaImGui did not honor `CHILD_AUTO_RESIZE_Y`; report it before changing the card implementation.

Report anything that fails to the user with a screenshot rather than guessing a fix.

- [ ] **Step 11: Commit**

```bash
git add ReaProjectLink/lib/reaprojectlink/ui/app.lua ReaProjectLink/ReaProjectLink.lua tests/ui_smoke_scenarios.lua tests/run_ui_smoke.lua tests/ui_modules_spec.lua
git commit -m "feat(ui): switch to the single-panel app shell"
```

(`git rm` in Step 5 already staged the deletion of `ui.lua`.)

---

### Task 12: Documentation

**Files:**
- Modify: `docs/decisions.md` (append D085, D086; amend D070 and the D075 sentence)
- Modify: `docs/architecture.md:325-327`
- Rewrite: `docs/ui-spec.md`
- Modify: `docs/ui-implementation-plan.md` (top)
- Modify: `docs/superpowers/specs/2026-09-22-ui-redesign-design.md` (two lines)
- Modify: `docs/development.md` (UI smoke description)

- [ ] **Step 1: Append the decisions**

Append to `docs/decisions.md`:

```markdown

### D085 — Single-panel UI with next-step highlighting

The UI has three layers: a main panel with one card per domain (Source:
Reference and Delivery; Master: Reference and Deliveries), full-panel Reviews
entered from card actions, and Settings entered from the header. There is no
navigation rail. At most one card is highlighted as the next step; it carries the
view's only primary button. Setup and low-frequency operations live in each
card's `···` menu or in Settings, and first-time setup is reached through card
empty states. Pointer files (never media) are read when the window opens, when
the active project changes, and on `Check now`; there is no periodic polling.
The UI offers Light and Dark themes plus Auto, which follows the brightness of
the REAPER theme. Details: `docs/ui-spec.md`.

### D086 — The checked Reference revision is declared at Delivery Publish

Amends D070 and D074. Source projects no longer have a separate Mark Reference
Reviewed step. Delivery Publish Review asks which Reference revision the audio
was checked against, defaulting to the Synchronized Reference Revision and
offering the revision declared by the previous Publish when it differs. The
declared revision is written to the Delivery Manifest's existing
`reference.reviewedRevision` field and stored in the project as the next
default. Publishing requires a Synchronized Reference Revision rather than a
Reviewed one. The manifest schema and Master behavior are unchanged.
```

In D070, replace

```text
The public revision states on a Source Project are Latest Revision,
Synchronized Revision, and Reviewed Revision. Synchronization materializes a
Reference revision in the Source Project. Review is a separate explicit user
confirmation. A Source Delivery records the Reviewed Revision.
```

with

```text
The public revision states on a Source Project are Latest Revision and
Synchronized Revision. Synchronization materializes a Reference revision in the
Source Project. A Source Delivery records the Reference revision its user
declared at Publish (D086).
```

In D075, replace

```text
Reference Revision in a Source Project. Reference synchronization remains
distinct from Mark Reference Reviewed.
```

with

```text
Reference Revision in a Source Project. The checked Reference revision is
declared at Delivery Publish (D086).
```

- [ ] **Step 2: Update the architecture note**

In `docs/architecture.md`, replace

```text
Source projects may automatically detect a new reference revision, but they do not
automatically adopt it. A source project records separate synchronized and
reviewed states. Delivery Publish records the Reviewed Reference Revision.
```

with

```text
Source projects may automatically detect a new reference revision, but they do not
automatically adopt it. Delivery Publish records the Reference revision the user
declares in the Review, defaulting to the synchronized revision (D086).
```

- [ ] **Step 3: Fix the two spec lines that the implementation refined**

In `docs/superpowers/specs/2026-09-22-ui-redesign-design.md`:

Replace `One row per subscription: name, status text, then either an action button or a` + next line `` `···` menu.`` with:

```text
One row per subscription: name, status text, an action button when the row
needs attention, and a `···` menu.
```

Replace the section 8.4 icon list sentence

```text
Drawn with the ImGui DrawList in the current text/token color and scaled with
the font size: more (`···`), refresh, gear, back arrow, chevron right/down,
plus, check, cross, warning triangle, dot. No icon font.
```

with

```text
Drawn with the ImGui DrawList in the current text/token color and scaled with
the font size: more (`···`), gear, back arrow, plus, check, cross, warning
triangle, dot, film, upload, download. Tree and dropdown arrows are ImGui's own.
No icon font.
```

- [ ] **Step 4: Rewrite `docs/ui-spec.md`**

Replace the entire file with a title and purpose followed by sections 2-8 of the design spec copied verbatim (after the Step 3 edits):

```markdown
# ReaProjectLink UI specification

ReaProjectLink is a workflow tool embedded in REAPER. The UI shows each
domain's state and the one next step, keeps setup and rare operations out of
the way, and routes every mutation through a Review. Decisions: D085, D086.
```

Then paste, in order, the sections `## 2. Information architecture` through `## 8. Visual system` from `docs/superpowers/specs/2026-09-22-ui-redesign-design.md`, renumbering their headings to `## 1.` … `## 7.` (and subsections to match, for example `### 2.1 Header` becomes `### 1.1 Header`).

- [ ] **Step 5: Mark the old implementation plan as superseded**

Insert after the first heading line of `docs/ui-implementation-plan.md`:

```markdown

> Superseded by the UI redesign (D085):
> `docs/superpowers/plans/2026-09-22-ui-redesign.md`. Kept for history.
```

- [ ] **Step 6: Update the development note about the UI smoke test**

In `docs/development.md`, after the paragraph that starts with `` `tests/run_in_reaper.lua` runs the same suite without interaction`` add:

```markdown

`tests/run_ui_smoke.lua` renders one frame for every scenario in
`tests/ui_smoke_scenarios.lua` (each view and Review, both themes, 320 px and
1040 px wide) and writes the result to the file named by
`REAPROJECTLINK_UI_SMOKE_RESULT`.
```

- [ ] **Step 7: Verify no stale references remain**

Run: `git grep -n -i "mark reference reviewed\|mark_reviewed\|navigation rail" -- docs README.md ReaProjectLink tests ':!docs/superpowers' ':!docs/ui-implementation-plan.md'`
Expected: exactly one match, the D085 line starting with `navigation rail.` in `docs/decisions.md`. (D086's "Mark Reference Reviewed" is wrapped across two lines, so it does not match.)

- [ ] **Step 8: Run both test suites**

Run: **Run core tests**, then **Run UI smoke**. Expected: both `PASS`.

- [ ] **Step 9: Commit**

```bash
git add docs
git commit -m "docs(ui): document the single-panel UI and publish-time Reference declaration"
```

---

## Self-review notes

- Spec 2.2 highlight priorities: `view_models.source_cards` / `master_cards`, Task 2 tests.
- Spec 2.3 responsive stacking and 720 px page cap: `components.card_width`, `begin_page`; smoke at 320 and 1040 px.
- Spec 2.4 first run: `views/setup.lua`.
- Spec 3 card tables: Task 2 tests cover every row; menus in `source_main`/`master_main`.
- Spec 4 update checks: `app_state` scheduling (Task 3), pointer `peek` (Task 4), `checks.lua` (Task 7), shell request on open/project change (Task 11).
- Spec 5 Review skeleton and 5.1 inventory: Tasks 8-9; stale state via `workflow.is_stale`. Reference Update Review shows revision contents (tracks/markers/regions counts) because the domain check does not compute a per-entry diff.
- Spec 5.2 Lane Mapping: `delivery_sync_review.draw_mapping_table`, `view_models` mapping helpers; no preselection (default `New track` for import, `Don't import` for update, matching today's update behavior).
- Spec 6 Settings, 7 notifications: Task 10 settings, `workflow.draw_notices`.
- Spec 8 visual system: Task 1 tokens, Task 6 components/icons.
- Spec 9.1: Task 5. Spec 9.2: Tasks 4 and 7.
- Spec 10-12: file map, specs, Task 12.
