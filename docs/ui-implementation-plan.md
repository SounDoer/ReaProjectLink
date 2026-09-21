# UI implementation plan

This plan implements `docs/ui-spec.md` without changing the confirmed workflow
or persisted data model.

## Phase 1 — Shared visual foundation and Source shell

Status: current milestone.

- add a small ReaImGui presentation helper module;
- establish colors, spacing, card surfaces, typography, and button hierarchy;
- add the shared header and Source navigation rail;
- implement Source Overview using lightweight project state;
- move existing Source Reference and Delivery controls into dedicated pages;
- present Delivery Publish Review as a dedicated view;
- add Source Settings for identities and paths;
- preserve the existing Master workflow inside the themed window;
- run the complete automated suite and Source/Master UI smoke frames.

## Phase 2 — Source interaction refinement

- redesign Reference Update as a structured Review rather than an expanding
  control group;
- replace routine message text with contextual notice panels and dismissible
  results where appropriate;
- separate advanced Reference detach actions;
- improve Delivery Lane and Clip presentation with tables and status labels;
- add empty, loading, warning, and blocked states for every Source page;
- verify small dock widths and high-DPI behavior in REAPER.

## Phase 3 — Master shell

- implement Master Overview;
- migrate Reference Publishing to the shared shell;
- implement Delivery Subscription cards;
- redesign first-import Lane Mapping;
- redesign target-revision Delivery synchronization;
- isolate Remove Subscription and identity-reset actions as secondary or
  advanced commands.

## Phase 4 — Review system

- standardize all Publish, Import, Update, and Synchronization Reviews;
- introduce reusable Review summary, blocker, decision, and result components;
- use tables and list clipping for large Delivery snapshots;
- standardize Back, Refresh Review, Apply, Publish, and confirmation behavior;
- verify D067 invalidation across Project Tab and path changes.

## Phase 5 — Packaging and polish

- decide whether to package a font and icon asset set;
- add optional compact and comfortable density if user testing supports it;
- verify Windows, macOS, and Linux rendering where test hosts are available;
- test 100%, 125%, 150%, and 200% display scaling;
- document ReaPack installation and UI dependency versions;
- capture release screenshots and complete manual validation.

## Verification for every phase

- run the dependency-free Lua/REAPER automated suite;
- run Source and Master ReaImGui smoke frames;
- exercise affected workflows in an isolated REAPER Project Tab;
- confirm no unrelated dirty-worktree changes are overwritten;
- update this plan and `docs/ui-spec.md` when a UI decision is confirmed or
  superseded.

