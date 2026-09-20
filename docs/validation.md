# Manual validation

Use disposable Source and Mix projects for the first end-to-end check. Keep the
projects and test media on the same storage arrangement used by the team.

## Setup

1. Add `scripts/ReaDelivery.lua` and `scripts/ReaDelivery_RunTests.lua` to
   REAPER's Action List.
2. Run `ReaDelivery - Run Tests`; confirm that all tests pass.
3. Create and save one new Mix `.rpp` and one new Source `.rpp`.

## Project switching safety

1. Open a Picture status, Publish Review, Import Review, or Update Review.
2. Switch to another Project Tab and confirm the panel clears the old workflow
   state, mappings, overrides, shift choice, messages, and observed lock.
3. Initialize the second project in the same mode and confirm no Review or
   synchronization record from the first project reappears.
4. Return to the first project and open a fresh Review. Edit the project after
   opening a Source or Master Reference Publish Review; confirm Publish is
   replaced by a stale-review warning until the Review is refreshed.

## Picture flow

1. Open the Mix project and initialize it as a Mix Project.
2. Put video Items on one or more Tracks, select those Tracks, and choose
   `Add Selected Picture Tracks`.
3. Optionally select Markers or Regions and register them. Assign one registered
   Marker as FFOP when the production uses that semantic Reference Start.
4. Open Master Reference Publish Review, then choose `Save & Publish Picture`.
5. Confirm that `_Delivery/<mix-project-name>/picture.json` and one immutable
   `picture-history/picture-0001.json` exist beside the Mix `.rpp`.
6. Open the Source project, initialize it as a Source Project, and select the
   Mix `picture.json`.
7. Keep the default Mirror Master Timeline mode, synchronize, and explicitly
   mark the revision reviewed. Verify all registered Tracks, Items, Markers, and
   Regions use the Master absolute positions.
8. Move the FFOP Marker and the complete Master timeline, publish again, and
   confirm Source offers but does not automatically perform the whole-project
   shift. Then move only FFOP and confirm that the full-project shift is not
   offered.
9. Duplicate a managed Picture Track or Item and confirm synchronization blocks
   until the duplicate is detached or given a new identity.
10. Change or replace a Mix video, publish again, and confirm that the
   Source reports the new revision without adopting or reviewing it
   automatically.

## First audio delivery

1. In the Source project, put one or more file-backed WAV Items on the intended
   delivery Tracks.
2. Select those Tracks and register them as Delivery Tracks.
3. Open Publish Review. Classify each untagged Item as `Create New Clip`; resolve
   all hard blockers. Use the FX override only when the unbaked-FX warning is
   intentional.
4. Choose `Save & Publish` and confirm that `delivery.json`, one immutable
   history Manifest, and copied WAV revisions exist under
   `_Delivery/<source-project-name>`.
5. In the Mix project, add that `delivery.json`, map each Lane to Create, an
   existing Track, or Skip, and confirm the import.
6. Verify position relative to Picture Start, source offset, length, fades,
   Item gain, and supported Take parameters.

## Revision update

1. In the Source project, replace an old delivery Item with the newly bounced
   WAV Item on the same Delivery Track.
2. In Publish Review, use the shown lineage evidence and explicitly choose
   `Link as revision of ...`; publish the complete Delivery Set.
3. In the Mix project, check the Source update. Accept audio for one Instance
   and skip it for another if multiple linked copies exist.
4. Apply the update and confirm that accepted audio appears as the active new
   Take while every old Take remains available.
5. Exercise one placement conflict: move a Mix Item locally and move the Source
   Clip differently, then confirm that the field defaults to `keep_mix` and can
   be changed to `use_source`.
6. Detach one selected Instance and confirm that later updates no longer include
   it.

## Recovery checks

- While a Publish lock exists, confirm that another Publish is blocked and its
  user, machine, and start time are visible. Remove it only through the explicit
  observed-lock action after confirming that no publisher is active.
- Rename or move a Source project with Save As. Confirm that ReaDelivery asks
  whether to continue the logical Source or start a new Source before Publish.
