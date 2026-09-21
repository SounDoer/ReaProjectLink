# ReaProjectLink UI specification

## 1. Purpose

ReaProjectLink is a workflow tool embedded in REAPER. Its interface should feel
like a focused delivery console rather than an audio effect plug-in. The UI must
make project state, required action, and the consequences of mutations clear
without exposing implementation identifiers during routine work.

This specification covers the complete application information architecture and
interaction language. The shared shell and components apply to both the Source
Project and Master Project experiences.

## 2. Design principles

1. **Show the next meaningful action.** The Overview prioritizes one contextual
   action instead of presenting every available command at once.
2. **Review before mutation.** Synchronize and Publish operations that change a
   REAPER project or external package are entered through a dedicated Review.
3. **Conditions are not commands.** Status text describes the current condition;
   buttons begin with a verb and describe the user's action.
4. **Progressive disclosure.** Routine views use names and qualified revisions.
   Paths, stable IDs, and implementation diagnostics live in Settings or
   Technical Details.
5. **REAPER remains the workspace.** ReaProjectLink supplements Track and Item
   editing rather than recreating the arrange view.
6. **No expensive ambient work.** Opening or drawing the Overview does not hash
   media, scan historical packages, or repeatedly query the NAS. Exact Publish
   readiness is calculated when a Review is opened.
7. **One vocabulary.** Labels follow `docs/decisions.md`, especially D068-D083.

## 3. Application shell

The primary interface is one resizable ReaImGui window that can float or be
docked in REAPER.

The shell contains:

- a 64-72 px context header;
- a 176-192 px left navigation rail;
- a scrollable content surface;
- contextual notices inside the content surface, not a permanent status bar.

The header displays the `.rpp` project name and a qualified `Source Project` or
`Master Project` badge. The product name belongs in the navigation rail. Full
paths and IDs are excluded from the header.

Recommended default size is 1040 x 720. The minimum useful content width is 680
px. Below that width, two-column card groups may stack vertically. The first
implementation may use a fixed sidebar while preserving horizontal clipping and
vertical scrolling safely.

## 4. Navigation

### 4.1 Source Project

- Overview
- Reference
- Delivery
- Settings

### 4.2 Master Project

- Overview
- Reference
- Deliveries
- Settings

Reviews are workflow destinations rather than permanent navigation entries. A
Review provides an explicit Back action and preserves its transient decisions
until it is applied, refreshed, invalidated, or the REAPER project changes.

## 5. Source Project experience

### 5.1 Overview

The Source Overview answers four questions:

1. Is the Reference current and reviewed?
2. Is the Delivery surface configured?
3. What is the latest published Delivery Revision?
4. What should the user do next?

The page contains:

- page title and one-line description;
- one Next Action panel;
- a Reference summary card;
- a Delivery summary card;
- a compact Project Health card.

Next Action priority is:

1. Subscribe to Reference when no subscription exists;
2. resolve an unavailable or blocked Reference;
3. review and synchronize a newer Reference Revision;
4. mark a synchronized Reference Revision reviewed;
5. register Delivery Tracks when none exist;
6. open Delivery Publish Review.

The Overview may navigate, select a file, refresh a read-only status, or open a
Review. It does not directly synchronize, detach, publish, unregister, unlock,
or reset identities.

The Reference card shows qualified revisions. When all revision values match,
it may collapse to `Reference rN · Synchronized and reviewed`. When they differ,
it shows Latest, Synchronized, and Reviewed separately.

The Delivery card shows the latest Delivery Revision, Delivery Track count, and
current Item count. It uses `Ready to review`, not `Ready to publish`, until the
Publish Review has completed its exact checks.

### 5.2 Reference

The Reference page owns:

- first subscription through selection of `reference.json`;
- explicit Check for Reference Update;
- Latest, Synchronized, and Reviewed Reference Revision state;
- Mirror Master Timeline versus Relative Reference alignment;
- Reference Update Review and optional whole-project shift;
- Synchronize Reference;
- Mark Reference Reviewed;
- advanced detach actions behind a clearly separated section.

Selecting a manifest establishes a subscription but does not silently
synchronize the project. Synchronization remains explicit.

### 5.3 Delivery

The Delivery page owns:

- registered Delivery Track summary;
- Register Selected Delivery Tracks;
- Unregister Selected Delivery Tracks;
- latest published Delivery Revision;
- entry to Delivery Publish Review.

Register is the primary configuration action. Unregister is visually secondary
because it stops management of an existing Track.

### 5.4 Delivery Publish Review

The Review is a dedicated content view. It displays:

- target Delivery Revision and Reviewed Reference Revision;
- package destination in a secondary details area;
- blocker and warning summary;
- one collapsible group per Delivery Lane;
- included Delivery Clips and media blockers;
- explicit Save As identity decisions when required;
- Publish Unprocessed Media confirmation when required;
- `Save & Publish Delivery` only when no blocker remains.

If the project changes after review creation, the Review is replaced by a
`Review Out of Date` state with `Refresh Review`. Stale decisions must not remain
visually actionable.

### 5.5 Settings

Settings contains project-level information and infrequent actions:

- Project Type;
- Project ID and Delivery ID;
- `.rpp` path;
- Reference manifest path;
- alignment mode;
- version/runtime diagnostic information when available.

IDs use complete labels. Values may be shortened in the summary but the full
value must remain available to copy or inspect.

## 6. Master Project experience

The Master shell follows the same hierarchy.

- Overview summarizes Reference publishing and Delivery Subscriptions.
- Reference owns registration and Reference Publish Review.
- Deliveries owns Add Delivery, Lane Mapping, target Delivery Revision, and
  Synchronize Delivery.
- Settings exposes Project and Reference identities, paths, and diagnostics.

Master implementation is a later milestone, but new shared components must not
encode Source-only assumptions.

## 7. Status model

Four presentation levels are used:

- **Neutral:** descriptive information or an inactive state;
- **Ready:** the user may proceed with the recommended operation;
- **Warning:** continuation requires attention or explicit confirmation;
- **Blocked:** the requested operation cannot proceed.

The primary public conditions remain those in D080, including `Review Out of
Date`, `Newer Revision Available`, `Media File Not Found`, `Publishing Is
Locked`, and `ReaProjectLink Update Required`.

Color is supplemental. Every state also has a text label and must remain
understandable without color.

## 8. Visual language

The visual direction is a restrained professional production tool:

- near-black neutral window background;
- slightly raised navigation and card surfaces;
- cool blue primary accent;
- teal/green Ready state;
- amber Warning state;
- red Blocked and destructive state;
- 4 px base spacing with common gaps of 8, 12, 16, and 24 px;
- 6-8 px corner radius;
- one-pixel low-contrast borders;
- compact controls suitable for a docked REAPER utility.

Typography has four levels:

- product/project context: 20-22 px;
- page title: 20 px;
- section/card title: 15-16 px;
- body and metadata: 13-14 px.

The implementation uses ReaImGui's default font at multiple sizes. A packaged
font may be evaluated later, but is not required for the first UI milestone and
must not become an undeclared runtime dependency.

## 9. Component inventory

The UI layer should provide reusable helpers for:

- application header;
- navigation item;
- page title and description;
- card/section surface;
- status label;
- primary and secondary buttons;
- notice/warning/blocker panel;
- label/value row;
- empty state;
- Review header and Back action.

These helpers standardize spacing and style; they must not contain domain or
REAPER mutation logic.

## 10. Responsiveness and performance

- Normal frames perform only lightweight project-state and Track/Item counts.
- Media hashing and package validation begin only through an explicit Review or
  Check action.
- Long paths use wrapping or a detail view and never force the window wider.
- Lists with hundreds of rows should use clipping when the relevant screen is
  implemented.
- Every Begin/End and Push/Pop pair remains balanced when a child or window is
  collapsed.
- UI state is scoped to the active REAPER project and resets with the existing
  project token behavior from D067.

## 11. Accessibility and interaction

- Do not rely on color alone.
- Use stable visible labels and hidden ImGui IDs only for uniqueness.
- Dangerous operations include an ellipsis and confirmation.
- Disabled actions should explain the blocking condition nearby.
- Keyboard activation and normal REAPER docking behavior must continue to work.
- Body copy should remain concise and use the qualified domain terms.

## 12. Current implementation acceptance criteria

The shared workspace milestone is accepted when:

- Source Project navigation switches among Overview, Reference, Delivery, and
  Settings without reopening the script;
- Overview selects the correct next action from available local/cached state;
- no automatic media hashing or NAS review is introduced;
- existing Reference and Delivery actions remain reachable;
- Master Project navigation switches among Overview, Reference, Deliveries, and
  Settings without reopening the script;
- existing Reference Publish, Delivery Import, and Delivery Synchronization
  actions remain reachable from the Master workspace;
- Delivery Publish Review remains invalidated after project changes;
- existing runtime requirements remain unchanged;
- the ReaImGui smoke test opens Source and Master frames successfully;
- the complete existing automated test suite passes.
