# Manual validation

Use disposable Source and Master Projects for the first end-to-end check. Keep
the projects and test media on the team's normal shared-storage arrangement.

## Setup

1. Add `scripts/ReaProjectLink.lua` and
   `scripts/ReaProjectLink_RunTests.lua` to REAPER's Action List.
2. Run `ReaProjectLink - Run Tests` and confirm that all tests pass.
3. Create and save one new Master Project `.rpp` and one new Source Project
   `.rpp`.

## Project switching and Save As

1. Open a Reference Update Review, Delivery Publish Review, Delivery Import
   Review, Delivery Update Review, or Reference Publish Review.
2. Switch Project Tabs and confirm the panel clears transient Reviews,
   decisions, mappings, overrides, messages, and observed lock data.
3. Edit a project after opening a Publish Review. Confirm the UI shows Review
   Out of Date and requires Refresh Review before publishing.
4. Use Save As on each Project Type. Confirm Continue Existing Project keeps
   its IDs and package relationship, while Start New Project creates new
   Project and Delivery or Reference identities at the new package location.

## Reference flow

1. Initialize the Master Project and register one or more Reference Tracks.
2. Register any required Markers and Regions. Optionally assign one registered
   Marker as the Reference Start; its displayed name may be anything, including
   an industry label such as FFOP.
3. Open Reference Publish Review and choose Save & Publish Reference.
4. Confirm that `_ReaProjectLink/<master-project-name>/reference.json` and
   `history/reference-0001.json` exist beside the Master Project.
5. Initialize the Source Project and subscribe to the Master Project's
   `reference.json`.
6. Keep Mirror Master Timeline enabled, synchronize, and explicitly mark the
   revision reviewed. Verify all registered Reference Tracks, Items, Markers,
   and Regions use the Master Project's absolute positions.
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
2. Open Delivery Publish Review. Resolve Needs Classification with Create New
   Clip or Continue Existing Clip. If FX is intentionally unbaked, confirm
   Publish Unprocessed Media and its warning.
3. Choose Save & Publish Delivery. Confirm `delivery.json`,
   `history/delivery-0001.json`, and copied Media Revisions exist under
   `_ReaProjectLink/<source-project-name>`.
4. In the Master Project, choose Add Delivery, select that `delivery.json`, and
   map every Delivery Lane with Create New Track, Use Existing Track, or Leave
   Unmapped.
5. Import the Delivery and verify position relative to Reference Start, source
   offset, length, fades, Item gain, and supported Take settings.

## Delivery update

1. Publish changed audio and placement from the Source Project.
2. In Delivery Update Review, confirm comparisons use Baseline, Delivery, and
   Local state; conflicts default to Keep Local and can be changed to Use
   Delivery.
3. Use Add New Take for one Linked Item and Keep Current Media for another.
   Confirm unsupported Take data requires explicit confirmation before a new
   Take is added.
4. Apply Delivery Update and confirm older Takes remain available.
5. Decline a Pending Clip, then use Reconsider Clip and confirm it is offered
   again.
6. Detach a Linked Item and confirm later updates no longer include it.

## Publish locking

- While Publishing Is Locked, confirm the possible publisher, computer, start
  time, and package path are visible.
- Confirm Check Again does not mutate the lock.
- Choose Unlock Publishing only after confirming that no other user or computer
  is publishing; then refresh the Review before retrying.
