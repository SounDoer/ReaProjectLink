# Manual validation

Use disposable Source and Mix projects for the first end-to-end check. Keep the
projects and test media on the same storage arrangement used by the team.

## Setup

1. Add `scripts/ReaDelivery.lua` and `scripts/ReaDelivery_RunTests.lua` to
   REAPER's Action List.
2. Run `ReaDelivery - Run Tests`; confirm that all tests pass.
3. Create and save one new Mix `.rpp` and one new Source `.rpp`.

## Picture flow

1. Open the Mix project and initialize it as a Mix Project.
2. Put one reference-video Item in the Mix, select it, choose
   `Review Selected Picture Item`, then `Save & Publish Picture`.
3. Confirm that `_Delivery/<mix-project-name>/picture.json` and one immutable
   `picture-history/picture-0001.json` exist beside the Mix `.rpp`.
4. Open the Source project, initialize it as a Source Project, and select the
   Mix `picture.json`.
5. Check, synchronize, and explicitly mark the Picture revision reviewed.
6. Change or replace the Mix video, publish Picture again, and confirm that the
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
