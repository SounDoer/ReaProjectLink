# Manual validation

Use disposable Source and Master Projects for the first end-to-end check. Keep
the projects and test media on the team's normal shared-storage arrangement.

## Setup

1. Add `ReaProjectLink/ReaProjectLink.lua` and
   `tests/ReaProjectLink_RunTests.lua` to REAPER's Action List.
2. Run `ReaProjectLink - Run Tests` and confirm that all tests pass.
3. Create and save one new Master Project `.rpp` and one new Source Project
   `.rpp`.

## Project switching and Save As

1. Open a Reference Update Review, Delivery Publish Review, Delivery Import
   Review, Delivery Update Review, or Reference Publish Review.
2. Switch Project Tabs and confirm the panel clears transient Reviews,
   decisions, mappings, overrides, messages, and observed lock data.
3. Edit a project after opening a Publish Review. Confirm the UI shows
   `Review Out of Date` and requires `Refresh Review` before publishing.
4. Use Save As on each Project Type. Confirm Continue Existing Project keeps
   its IDs and package relationship, while Start New Project creates new
   Project and Delivery or Reference identities at the new package location.

## Reference flow

1. Initialize the Master Project and use the Reference card's `Register
   Selected Tracks` button to register one or more Reference Tracks.
2. Use the Reference card's `Register Selected Markers` and `Register Selected
   Regions` buttons to register any required Markers and Regions. Optionally
   assign one registered Marker as the Reference Start from the `···` menu; its
   displayed name may be anything, including an industry label such as FFOP.
3. Open Reference Publish Review and choose `Publish`.
4. Confirm that `_ReaProjectLink/<master-project-name>/reference.json` and
   `history/reference-0001.json` exist beside the Master Project.
5. Initialize the Source Project and subscribe to the Master Project's
   `reference.json`.
6. Keep Mirror Master Timeline enabled and synchronize. Verify all registered
   Reference Tracks, Items, Markers, and Regions use the Master Project's
   absolute positions.
7. Move every stable Reference timeline element by the same amount, publish,
   and confirm the Source Project offers—but never automatically applies—the
   full-project shift. Move only the Reference Start and confirm it is not
   offered.
8. Duplicate a managed Reference Track or Item and confirm synchronization
   blocks until the duplicate is detached or treated as new.
9. Replace Reference media at the same path and confirm Media Content Mismatch.

## Delivery flow

1. Put file-backed WAV Items on Source Project Tracks and register those Tracks
   as Delivery Tracks.
2. Open Delivery Publish Review. Confirm every current Item is listed as Included
   without a Clip identity decision. If FX is intentionally unbaked, confirm
   Publish Unprocessed Media and its warning.
3. Confirm the `Checked Against Reference` choice: it defaults to the
   Synchronized Reference Revision, and offers the previously declared revision
   as an alternative when it differs. Choose `Publish`. Confirm
   `delivery.json`, `history/delivery-0001.json`, and copied Media Revisions
   exist under `_ReaProjectLink/<source-project-name>`, and that the manifest's
   `reference.reviewedRevision` records the revision chosen in the Review.
4. In the Master Project, choose Add Delivery, select that `delivery.json`, and
   map every Delivery Lane using its dropdown: suggested Tracks, `New Track`,
   `Selected Track`, or `Don't Import`. Confirm `New tracks go under: Top
   Level | Selected Folder Track` chooses the parent for lanes mapped to
   `New Track`.
5. Import the Delivery and verify position relative to Reference Start, source
   offset, length, fades, Item gain, and supported Take settings.

## Delivery update

1. Publish changed audio, placement, splits, additions, and removals from the
   Source Project.
2. In Delivery Update Review, confirm the complete target snapshot and Item
   replacement counts are shown without per-Clip or per-field decisions.
3. Synchronize and verify all previous managed Items are replaced by the exact
   target snapshot in one undoable operation while Track FX, routing, and
   automation remain unchanged.
4. Move one Synchronized Item to a different Track. Confirm the prompt keeps it as
   local Master content and later synchronization leaves it untouched.
5. Move another Synchronized Item and decline the prompt. Synchronize and confirm it
   is replaced because it remained Source-managed.
6. Delete or detach a managed Item, then synchronize the currently handled
   Delivery Revision and confirm the complete Source snapshot is restored.
7. Synchronize an older Delivery Revision and confirm it replaces the managed
   snapshot just like a forward update.

## Publish locking

- While Publishing Is Locked, confirm the possible publisher, computer, and
  start time are visible.
- Confirm `Check Now` (header) and `Retry` (card action) do not mutate the
  lock.
- Choose `Unlock Publishing...` only after confirming that no other user or
  computer is publishing; then refresh the Review before retrying.

## Pointer checks

1. Open the window and confirm each card briefly shows `Checking...` before
   settling on its result.
2. Switch Project Tabs and confirm the same `Checking...` then result sequence
   runs again for the newly active project.

## Appearance and layout

1. In Settings, choose each of Light, Dark, and Auto. Confirm Auto follows the
   brightness of the REAPER theme.
2. Dock the window and narrow it to about 320 px. Confirm cards, Reviews, and
   Settings stay usable without horizontal clipping.

## Review interactions

1. In Delivery Publish Review, use `Select Item` on a blocked Item. Confirm it
   selects the Item in REAPER and confirm the Review does not immediately flip
   to `Review Out of Date`.

## Project state reset

1. In an initialized Source or Master Project, open Settings and choose
   `Reset ReaProjectLink State...`. Confirm the project returns to the setup
   view (as if never initialized), while Tracks, Items, and any published
   packages are untouched.
2. Confirm the confirmation dialog states that the reset can't be undone
   (REAPER Undo restores Track and Item keys but not project extension state).

## Master package check

1. On a Master Project with a published Reference, delete the published
   package folder (or just `reference.json` inside it) from shared storage.
2. Choose `Check Now`. Confirm the Reference card shows `Package Missing`
   with a note explaining the published files weren't found, and offers
   `Review and Publish` to restore them.
