# UI redesign — design

Date: 2026-09-22
Status: Draft for review
Supersedes on approval: `docs/ui-spec.md` (sections 3-9), `docs/ui-implementation-plan.md`

## 1. Goals

The first UI works but testing showed three problems:

1. Users cannot tell what to do next.
2. Too many buttons are visible at once, especially on the Master Reference
   page and in Lane Mapping.
3. Layout, hierarchy, and visual polish are weak.

Goals:

- A new Source or Master user can complete the daily loop without training.
- The window works both docked narrow (~320 px) and floating wide (~1040 px).
- Light and dark themes.
- No change to domain behavior except the two items in section 9.

Non-goals: new workflow features, cloud features, REAPER theme color mirroring,
bundled fonts or icon fonts.

The existing "select in REAPER, then click" interaction model is kept.

## 2. Information architecture

The left navigation rail and the Overview/Reference/Delivery/Settings pages are
removed. The UI has three layers:

| Layer | Content | Enter / leave |
|---|---|---|
| Main panel | Header + two domain cards | Always present |
| Review | Full-panel workflow view | Entered from a card action; leaves on Back, on completion, or when the project changes |
| Settings | Full-panel project information and preferences | Entered from the header gear; leaves on Back |

Source cards: **Reference**, **Delivery**.
Master cards: **Reference**, **Deliveries**.

### 2.1 Header

Left: project name, `Source` / `Master` badge.
Right: `Checked N min ago` text, `Check Now` text button, gear icon button.

Blocking global conditions (project not saved, Publishing Is Locked) appear as a
banner directly under the header. The banner carries its own action (for
example `Unlock Publishing…`).

### 2.2 Next-step highlight

Exactly one card at most is highlighted: accent border and the view's only
primary (filled) button. All other card buttons are secondary. This replaces
the separate Next Action panel.

Source priority (first match wins):

1. Reference not subscribed
2. Reference unreachable or blocked (for example media file not found)
3. Newer Reference Revision available
4. No Delivery Tracks registered
5. Delivery (daily publish) — Source always has a highlighted card

Master priority:

1. Nothing registered (no Reference Tracks, Markers, or Regions)
2. Reference never published
3. No Delivery subscriptions
4. Any subscription with a newer Delivery Revision, unmapped Lanes, or a read failure
5. Otherwise nothing is highlighted and the header shows `All Up to Date`

### 2.3 Responsive layout

- Content width < 560 px: cards stack vertically.
- ≥ 560 px: cards sit side by side with equal width.
- Review and Settings content is capped at a readable maximum width (~720 px)
  and centered in wide windows.
- Long paths wrap; nothing forces horizontal scrolling.

### 2.4 First run

An uninitialized project shows only a setup view, titled `Set Up
ReaProjectLink` with the line "Choose the type for this project." and two
cards laid out like the main panel's:

- `Source Project` — "An editing project that publishes Deliveries to the
  Master Project." → `Initialize Source Project`
- `Master Project` — "An integration project that publishes the Reference and
  receives Deliveries." → `Initialize Master Project`

After initialization the main panel appears and card empty states guide the
remaining setup.

## 3. Cards

Every card has the same anatomy: icon + title + optional `···` menu; one status
line (colored dot + text); up to two key/value rows; at most one card-level
button. On a card with registerable content, the rows are followed by one
small muted selection line (`Selected: 2 Tracks, 1 Region` or `Nothing
selected in REAPER`) and two secondary buttons, `Register Selected` and
`Unregister Selected`, that act on whatever is selected in REAPER.

### 3.1 Source · Reference

| State | Status line | Info | Button |
|---|---|---|---|
| Not subscribed | `Not Connected` (warning) | "Choose the reference.json the Master Project published." | `Choose reference.json` |
| Checking | `Checking…` (neutral) | Last known revision | — |
| Unreachable | `Couldn't Reach Shared Storage` (blocked) | Last known revision | `Retry` |
| Invalid (pointer unreadable or identity changed) | `Couldn't Read the Reference` (blocked) | Error detail | `Retry` |
| Blocked (e.g. media missing) | Condition text per D080 (blocked) | Last known revision | `Review Update` |
| Newer available | `Reference rN Available` (warning) | `Synchronized rM` | `Review Update` |
| Up to date | `Up to Date` (ready) | `Reference rN` | — |

The "synchronized but not reviewed" state no longer exists (section 9.1).

`···` menu: `Detach Selected Items…`, `Detach Selected Tracks…`.

### 3.2 Source · Delivery

Below the `Tracks` and `Items` rows, the selection line and the `Register
Selected` / `Unregister Selected` buttons act on whatever Tracks are selected
in REAPER. There is no `···` menu on this card.

| State | Status line | Info | Button |
|---|---|---|---|
| No tracks | `No Delivery Tracks` (warning) | "Select tracks in REAPER first."; rows show `Tracks 0`, `Items 0` | — |
| Never published | `Not Published Yet` (neutral) | `N tracks · M items` | `Review and Publish` |
| Published | `Last Published rN` (neutral) | `N tracks · M items` | `Review and Publish` |

When the Delivery card is not highlighted because a newer Reference is pending,
the button stays enabled and a hint reads `Will record Reference rN`.

### 3.3 Master · Reference

Below the `Tracks`, `Markers`, and `Regions` rows, the selection line and the
`Register Selected` / `Unregister Selected` buttons register or unregister
whatever Tracks, Markers, or Regions are selected in REAPER.

| State | Status line | Info | Button |
|---|---|---|---|
| Nothing registered | `Nothing Registered` (warning) | "Select Tracks, Markers, or Regions in REAPER, then register them." | — |
| Never published | `Not Published Yet` (warning) | `N tracks · M markers · P regions` | `Review and Publish` |
| Published | `Published rN` (neutral) | `N tracks · M markers · P regions` | `Review and Publish` |
| Package Missing | `Package Missing` (blocked) | `N tracks · M markers · P regions`; note explains published files weren't found | `Review and Publish` |

`···` menu:

- `Set Selected Marker as Reference Start`
- Advanced: `Treat Selected Items as New…`, `Treat Selected Tracks as New…`

`Unregister Selected` acts immediately, without a confirmation dialog; the
consequence only becomes real at Publish, where Publish Review blocks on
content removed since the last published revision (D089).

### 3.4 Master · Deliveries

Title bar has a `+` icon button: `Add Delivery` (file dialog for
`delivery.json`, then the Delivery Import Review). With no subscriptions the card
shows an empty state with a primary `Add Delivery` button.

One row per subscription: name, status text, an action button when the row
needs attention, and a `···` menu.

| Row state | Status text | Row action |
|---|---|---|
| Newer revision | `rN Available · Have rM` (warning) | `Sync` |
| Unmapped Lanes | `N Lanes Not Imported` (neutral) | `Map Lanes` |
| Unreachable | `Couldn't Reach` (blocked) | `Retry` |
| Invalid | `Couldn't Read Delivery` (blocked) | `Retry` |
| Older Reference | `Made Against Reference rN` (warning) | `···` |
| Up to date | `Up to Date · rN` (ready) | `···` |

When several states apply, the row shows the first in this order: Unreachable,
Invalid, Newer revision, Unmapped Lanes, Older Reference, Up to date.

Row `···` menu: `Sync to Another Revision…`, `Remove Subscription…`.

## 4. Update checks

- Reference and Delivery pointers (small JSON files only, never media) are read
  once when the window opens and once when the active REAPER project changes,
  plus on `Check Now` and `Retry`.
- The first frame renders `Checking…`; the read happens on the next frame.
- A read failure sets that card or row to Unreachable (the pointer file is
  missing, for example the share is offline) or Invalid (the file can't be
  parsed or its identity changed); it never opens an error dialog.
- Known limitation: Lua file I/O has no timeout, so an unreachable SMB share can
  stall the UI for a few seconds during a check. Accepted.
- No periodic polling.
- On a Master with a published Reference, the same check also confirms its own
  `reference.json` still exists next to the manifest; if not, the Reference
  card shows Package Missing instead of Published (D088).

## 5. Review pattern

All Reviews share one skeleton. Empty sections are omitted.

1. **Header** — Back arrow, verb-first title with the target revision
   (for example `Publish Delivery r13`), one summary line.
2. **Issues** — blockers (red) and warnings (amber). Each item carries an inline
   fix or acknowledgment action (for example `Select Item` selects the offending
   Item in REAPER; `Publish Unprocessed Media`; `Allow Reference revision
   difference`; `Publish Without Them...` for Tracks, Markers, Regions, or
   Lanes removed since the last published revision (D089); Save As identity
   as two buttons `Continue Existing` / `Start New`).
3. **Decisions** — choices the operation needs (Reference declaration, Lane
   Mapping table, target revision, parent for new tracks).
4. **Details** — collapsible groups per Lane or Track, collapsed by default,
   auto-expanded when the group contains an issue. Long lists use clipping.
5. **Footer** — fixed at the bottom: one-sentence effect summary and the only
   primary button. With blockers the button is disabled and the text reads
   `Fix N issues to publish` (or the matching verb).

**Stale state:** when the project changes after the Review was built, the whole
body is replaced by `Review Out of Date` + explanation + `Refresh Review`. Stale
decisions are never actionable (existing D067 behavior).

### 5.1 Review inventory

| Review | Title | Decisions | Details | Primary |
|---|---|---|---|---|
| Reference Update (Source) | `Update Reference to rN` | Whole-project shift toggle, only when the start changed | Track, Marker, and Region counts and alignment mode | `Synchronize` |
| Reference Publish (Master) | `Publish Reference rN` | Unchanged-publish confirmation when nothing changed | Registered Tracks, Markers/Regions | `Publish` |
| Delivery Publish (Source) | `Publish Delivery rN` | Checked Against Reference (9.1); Save As identity | Clips per Lane | `Publish` |
| Delivery Import / Update (Master) | `Add <name>` / `Sync <name> to rN` | Lane Mapping table; target revision; parent for new tracks | Mapped Lanes with editable target | `Import` / `Sync` |

Reference Update is a new Review view; today its controls sit inline on the
Reference page. Mark Reference Reviewed is removed (9.1).

### 5.2 Lane Mapping table

Replaces the per-Lane button rows.

- One row per Lane: Lane name, Clip count, one dropdown.
- Dropdown groups: suggested Tracks (name match) first; then `New Track`,
  `Selected Track`; then `Don't Import`.
- Default is `New Track` in both the Delivery Import and Delivery Update
  Reviews. A Lane the user previously chose not to import stays `Don't Import`
  until they map it. Suggestions are never preselected (D054 unchanged).
- Header control `New tracks go under: Top Level | Selected Folder Track`
  replaces `Create All Under Selected Folder Track`.
- `Selected Track` with zero or several selected tracks shows an inline issue
  on that row instead of a toast.
- Already-mapped Lanes (Update Review) list their current target in the same
  dropdown so a Lane can be re-bound.

## 6. Settings

| Group | Source | Master |
|---|---|---|
| Project | Name, `.rpp` path, Project ID, Delivery ID (copyable) | Name, `.rpp` path, Project ID, Reference ID (copyable) |
| Reference | `reference.json` path + `Change…`; Mirror Master Timeline toggle | — |
| Appearance | Theme: Auto / Light / Dark | Same |
| About | ReaProjectLink, REAPER, ReaImGui versions | Same |
| Reset | `Reset ReaProjectLink State…` button, with a note that Published packages and media Items are kept | Same |

`Unlock Publishing…` lives in the lock banner, not in Settings.

## 7. Notifications

- Transient toast floating over the bottom of the window, so it never moves
  the content underneath. Persistent banners (unsaved project, Publishing Is
  Locked) stay in the layout under the header.
- Success toasts disappear after ~4 s; error toasts stay until dismissed.
- Errors that belong to a Review are shown as Review issues, not toasts.
- A success toast appears only when the result is not already visible in the
  panel: publishing a Reference or a Delivery, synchronizing a Reference,
  importing or synchronizing a Delivery, and keeping moved Items as local
  content. These write outside the panel — a published package, or a batch of
  Items in REAPER — and their toast names the revision or the counts.
- Everything else is silent on success, because the view already shows the
  result: registering and unregistering, detaching, Set Reference Start, Treat
  as New, initializing a project, subscribing to a Reference, removing a
  subscription, the alignment toggle, unlocking, and resetting the project.
- Errors always show a toast, for every operation.

## 8. Visual system

### 8.1 Color tokens

Both themes define the same semantic names. Components reference only names.

| Token | Light | Dark |
|---|---|---|
| bg | `#f3f4f6` | `#16181c` |
| surface | `#ffffff` | `#1f2227` |
| surface_hover | `#eef0f3` | `#272b31` |
| border | `#dadde2` | `#30343c` |
| text | `#1d2025` | `#e6e8eb` |
| muted | `#5f6670` | `#9aa0a8` |
| accent | `#2f6fe0` | `#4c8dff` |
| on_accent | `#ffffff` | `#0b1220` |
| accent_bg | `#e4edfc` | `#1c2a44` |
| ready | `#1f8a63` | `#3fbf8f` |
| warning | `#a86a0c` | `#e0a84a` |
| warning_bg | `#fdf1dc` | `#3a2f1c` |
| blocked | `#c93c46` | `#eb5f68` |
| blocked_bg | `#fbe5e6` | `#3b2224` |

Hover/active shades are derived in `theme.lua`. Status colors are used only for
text, dots, borders, and the tinted issue backgrounds, never large fills. Every
status also has a text label.

Theme preference `Auto | Light | Dark` is stored globally in ExtState (not per
project), default `Auto`. `Auto` reads REAPER's main background theme color and
picks Light or Dark by luminance.

### 8.2 Typography

System sans-serif through ReaImGui; bold through the font flags. No bundled
fonts.

| Use | Size / weight |
|---|---|
| Project name, Review title | 16 bold |
| Card title, group name | 14 bold |
| Body, buttons | 13 regular |
| Metadata (timestamps, counts) | 12 regular |

UI text uses ASCII `...` instead of the `…` character, which the default
font's glyph range does not include.

### 8.3 Spacing and shape

4 px base unit. Card padding 12; gap between cards 12; gap between sections 16;
list row height 28; corner radius 6; 1 px borders.

### 8.4 Icons

Drawn with the ImGui DrawList in the current text/token color and scaled with
the font size: more (`···`), gear, back arrow, plus, check, cross,
warning triangle, dot, film, upload, download. Tree and dropdown arrows are
ImGui's own.
No icon font.

### 8.5 Component inventory

All in the UI layer; none contains domain or REAPER mutation logic.

- Shell: Header, Banner, Toast
- Cards: Card (normal / highlighted), StatusLine, KeyValue, EmptyState
- Buttons: Button (primary / secondary / danger), IconButton
- Selection: Menu (with separators), Dropdown, Segmented
- Review: IssueItem, GroupRow (collapsible), ListRow, FooterBar, StaleState

## 9. Domain changes

### 9.1 Reference review is declared at Delivery Publish

Problem found in testing: users synchronize a Reference Revision, forget
`Mark Reference Reviewed`, and either cannot publish (first Delivery is blocked
by `delivery_publish.lua` when no Reviewed Revision exists) or silently publish
against an older Reviewed Revision.

Change:

- Remove `Mark Reference Reviewed` from the UI.
- Delivery Publish Review shows a `Checked Against Reference` segmented choice.
  Options: the Synchronized Reference Revision (default) and, when different,
  the revision recorded by the previous Delivery.
- The chosen revision is written to the Delivery manifest in the existing
  reviewed-revision field. Manifest schema and Master behavior are unchanged.
- The project value that stored the Reviewed Revision now stores the last
  declared revision and seeds the next default.
- The first-Delivery blocker changes from "no Reviewed Revision" to "no
  Synchronized Reference Revision".
- Source Reference state reduces to Latest and Synchronized.

This amends D070 and D074 and is recorded as a new decision D086.

### 9.2 Automatic pointer check on open

Section 4. Refines the former ui-spec performance principle: reading pointer JSON on open and on
project change is allowed; hashing and package validation remain Review-only.

## 10. Code structure

```
ReaProjectLink/lib/reaprojectlink/ui/
  theme.lua                     palettes, Auto detection, fonts, style push/pop
  icons.lua                     DrawList icons
  components.lua                component inventory (8.5)
  view_models.lua               pure: project state -> card/row view models + highlight
  app_state.lua                 current view, active Review, toasts, check timestamps;
                                reset on project change (D067)
  views/
    setup.lua
    source_main.lua
    master_main.lua
    settings.lua
    reference_update_review.lua
    reference_publish_review.lua
    delivery_publish_review.lua
    delivery_sync_review.lua    import and update share this view
ReaProjectLink/ReaProjectLink.lua   requirements check, context, loop, view dispatch
```

The existing `lib/reaprojectlink/ui.lua` is replaced by the `ui/` directory.
Views call existing domain services; they do not add domain logic.

## 11. Testing

- `view_models.lua` specs in the existing runner: highlight priority for every
  Source and Master state in 2.2; card status/text/button per row of the tables
  in section 3; subscription row states.
- Delivery publish specs for 9.1: declared revision is written; default is the
  Synchronized Revision; first Delivery no longer requires a Reviewed Revision.
- Extend `tests/run_ui_smoke.lua`: render one frame of every view, in both
  themes, at 320 px and 1040 px widths, asserting balanced Begin/End and
  Push/Pop.
- The complete existing suite keeps passing.

## 12. Delivery order

Each step is runnable and tested on its own.

1. Theme, icons, components, view models, and their specs.
2. Source main panel, Settings, first-run setup view.
3. The four Review views and the 9.1 domain change.
4. Master main panel and Delivery Import/Update Review.
5. Remove old pages and navigation; rewrite `docs/ui-spec.md`; add D085 (UI
   information architecture) and D086 (9.1) to `docs/decisions.md`; mark
   `docs/ui-implementation-plan.md` as superseded.
