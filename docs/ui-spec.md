# ReaProjectLink UI specification

ReaProjectLink is a workflow tool embedded in REAPER. The UI shows each
domain's state and the one next step, keeps setup and rare operations out of
the way, and routes every mutation through a Review. Decisions: D085, D086.

## 1. Information architecture

The former left-hand navigation sidebar and the Overview/Reference/Delivery/Settings pages are
removed. The UI has three layers:

| Layer | Content | Enter / leave |
|---|---|---|
| Main panel | Header + two domain cards | Always present |
| Review | Full-panel workflow view | Entered from a card action; leaves on Back, on completion, or when the project changes |
| Settings | Full-panel project information and preferences | Entered from the header gear; leaves on Back |

Source cards: **Reference**, **Delivery**.
Master cards: **Reference**, **Deliveries**.

### 1.1 Header

Left: project name, `Source` / `Master` badge.
Right: `Checked N min ago` text, `Check now` text button, gear icon button.

Blocking global conditions (project not saved, Publishing Is Locked) appear as a
banner directly under the header. The banner carries its own action (for
example `Unlock publishing…`).

### 1.2 Next-step highlight

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

1. No Reference Tracks registered
2. Reference never published
3. No Delivery subscriptions
4. Any subscription with a newer Delivery Revision, unmapped Lanes, or a read failure
5. Otherwise nothing is highlighted and the header shows `All up to date`

### 1.3 Responsive layout

- Content width < 560 px: cards stack vertically.
- ≥ 560 px: cards sit side by side with equal width.
- Review and Settings content is capped at a readable maximum width (~720 px)
  and centered in wide windows.
- Long paths wrap; nothing forces horizontal scrolling.

### 1.4 First run

An uninitialized project shows only a setup view with two large choices:

- "This is a department project" → Initialize as Source Project
- "This is the mix project" → Initialize as Master Project

Each has one sentence of explanation. After initialization the main panel
appears and card empty states guide the remaining setup.

## 2. Cards

Every card has the same anatomy: icon + title + optional `···` menu; one status
line (colored dot + text); up to two key/value lines; at most one button.

### 2.1 Source · Reference

| State | Status line | Info | Button |
|---|---|---|---|
| Not subscribed | `Not connected` (warning) | "Choose the reference.json your mix project published." | `Choose reference.json` |
| Checking | `Checking…` (neutral) | Last known revision | — |
| Unreachable | `Couldn't reach shared storage` (blocked) | Last known revision | `Retry` |
| Invalid (pointer unreadable or identity changed) | `Couldn't read the Reference` (blocked) | Error detail | `Retry` |
| Blocked (e.g. media missing) | Condition text per D080 (blocked) | Last known revision | `Review update` |
| Newer available | `Reference rN available` (warning) | `Synchronized rM` | `Review update` |
| Up to date | `Up to date` (ready) | `Reference rN` | — |

The "synchronized but not reviewed" state no longer exists (D086).

`···` menu: `Detach selected items…`, `Detach selected tracks…`.

### 2.2 Source · Delivery

| State | Status line | Info | Button |
|---|---|---|---|
| No tracks | `No delivery tracks` (warning) | "Select tracks in REAPER first." | `Register selected tracks` |
| Never published | `Not published yet` (neutral) | `N tracks · M items` | `Review and publish` |
| Published | `Last published rN` (neutral) | `N tracks · M items` | `Review and publish` |

When the Delivery card is not highlighted because a newer Reference is pending,
the button stays enabled and a hint reads `Will record Reference rN`.

`···` menu: `Register selected tracks`, `Unregister selected tracks…`.

### 2.3 Master · Reference

| State | Status line | Info | Button |
|---|---|---|---|
| No tracks | `No reference tracks` (warning) | "Select video tracks in REAPER first." | `Register selected tracks` |
| Never published | `Not published yet` (warning) | `N tracks · M markers` | `Review and publish` |
| Published | `Published rN` (neutral) | `N tracks · M markers` | `Review and publish` |

`···` menu, grouped with separators:

- Tracks: `Register selected tracks`, `Unregister selected tracks`
- Markers: `Register selected markers/regions`, `Unregister selected markers/regions`,
  `Set selected marker as Reference Start`
- Advanced: `Treat selected items as new…`, `Treat selected tracks as new…`

### 2.4 Master · Deliveries

Title bar has a `+` icon button: `Add delivery…` (file dialog for
`delivery.json`, then the Delivery Import Review). With no subscriptions the card
shows an empty state with a primary `Add delivery` button.

One row per subscription: name, status text, an action button when the row
needs attention, and a `···` menu.

| Row state | Status text | Row action |
|---|---|---|
| Newer revision | `rN available · have rM` (warning) | `Sync` |
| Unmapped Lanes | `N lanes not imported` (neutral) | `Map lanes` |
| Unreachable | `Couldn't reach` (blocked) | `Retry` |
| Invalid | `Couldn't read delivery` (blocked) | `Retry` |
| Older Reference | `Made against Reference rN` (warning) | `···` |
| Up to date | `Up to date · rN` (ready) | `···` |

When several states apply, the row shows the first in this order: Unreachable,
Invalid, Newer revision, Unmapped Lanes, Older Reference, Up to date.

Row `···` menu: `Sync to another revision…`, `Remove subscription…`.

## 3. Update checks

- Reference and Delivery pointers (small JSON files only, never media) are read
  once when the window opens and once when the active REAPER project changes,
  plus on `Check now` and `Retry`.
- The first frame renders `Checking…`; the read happens on the next frame.
- A read failure sets that card or row to Unreachable (the pointer file is
  missing, for example the share is offline) or Invalid (the file can't be
  parsed or its identity changed); it never opens an error dialog.
- Known limitation: Lua file I/O has no timeout, so an unreachable SMB share can
  stall the UI for a few seconds during a check. Accepted.
- No periodic polling.

## 4. Review pattern

All Reviews share one skeleton. Empty sections are omitted.

1. **Header** — Back arrow, verb-first title with the target revision
   (for example `Publish Delivery r13`), one summary line.
2. **Issues** — blockers (red) and warnings (amber). Each item carries an inline
   fix or acknowledgment action (for example `Select item` selects the offending
   Item in REAPER; `Publish unprocessed media`; `Allow Reference revision
   difference`; Save As identity as two buttons `Continue existing` /
   `Start new`).
3. **Decisions** — choices the operation needs (Reference declaration, Lane
   Mapping table, target revision, parent for new tracks).
4. **Details** — collapsible groups per Lane or Track, collapsed by default,
   auto-expanded when the group contains an issue. Long lists use clipping.
5. **Footer** — fixed at the bottom: one-sentence effect summary and the only
   primary button. With blockers the button is disabled and the text reads
   `Fix N issues to publish` (or the matching verb).

**Stale state:** when the project changes after the Review was built, the whole
body is replaced by `Project changed` + explanation + `Refresh review`. Stale
decisions are never actionable (existing D067 behavior).

### 4.1 Review inventory

| Review | Title | Decisions | Details | Primary |
|---|---|---|---|---|
| Reference Update (Source) | `Update Reference to rN` | Whole-project shift toggle, only when the start changed | Track, Marker, and Region counts and alignment mode | `Synchronize` |
| Reference Publish (Master) | `Publish Reference rN` | Unchanged-publish confirmation when nothing changed | Registered Tracks, Markers/Regions | `Publish` |
| Delivery Publish (Source) | `Publish Delivery rN` | Checked against Reference (D086); Save As identity | Clips per Lane | `Publish` |
| Delivery Import / Update (Master) | `Add <name>` / `Sync <name> to rN` | Lane Mapping table; target revision; parent for new tracks | Mapped Lanes with editable target | `Import` / `Sync` |

Reference Update is a new Review view; today its controls sit inline on the
Reference page. The separate Reference-review confirmation step is removed
(D086).

### 4.2 Lane Mapping table

Replaces the per-Lane button rows.

- One row per Lane: Lane name, Clip count, one dropdown.
- Dropdown groups: suggested Tracks (name match) first; then `New track`,
  `Selected track`; then `Don't import`.
- Default is `New track`. Suggestions are never preselected (D054 unchanged).
- In the Delivery Update Review, Lanes that are not yet mapped default to
  `Don't import`, preserving the existing update behavior; the user maps them
  explicitly.
- Header control `New tracks go under: Top level | Selected folder track`
  replaces `Create All Under Selected Folder Track`.
- `Selected track` with zero or several selected tracks shows an inline issue
  on that row instead of a toast.
- Already-mapped Lanes (Update Review) list their current target in the same
  dropdown so a Lane can be re-bound.

## 5. Settings

| Group | Source | Master |
|---|---|---|
| Project | Name, `.rpp` path, Project ID, Delivery ID (copyable) | Name, `.rpp` path, Project ID, Reference ID (copyable) |
| Reference | `reference.json` path + `Change…`; Mirror Master Timeline toggle | — |
| Appearance | Theme: Auto / Light / Dark | Same |
| About | ReaProjectLink, REAPER, ReaImGui versions | Same |

`Unlock publishing…` lives in the lock banner, not in Settings.

## 6. Notifications

- Transient toast at the top of the content area.
- Success toasts disappear after ~4 s; error toasts stay until dismissed.
- Errors that belong to a Review are shown as Review issues, not toasts.

## 7. Visual system

### 7.1 Color tokens

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

### 7.2 Typography

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

### 7.3 Spacing and shape

4 px base unit. Card padding 12; gap between cards 12; gap between sections 16;
list row height 28; corner radius 6; 1 px borders.

### 7.4 Icons

Drawn with the ImGui DrawList in the current text/token color and scaled with
the font size: more (`···`), gear, back arrow, plus, check, cross, warning
triangle, dot, film, upload, download. Tree and dropdown arrows are ImGui's own.
No icon font.

### 7.5 Component inventory

All in the UI layer; none contains domain or REAPER mutation logic.

- Shell: Header, Banner, Toast
- Cards: Card (normal / highlighted), StatusLine, KeyValue, EmptyState
- Buttons: Button (primary / secondary / danger), IconButton
- Selection: Menu (with separators), Dropdown, Segmented
- Review: IssueItem, GroupRow (collapsible), ListRow, FooterBar, StaleState
