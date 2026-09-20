# Development

## Runtime

- REAPER 7.74 or newer with embedded Lua 5.4;
- ReaImGui 0.9-compatible API or newer, installed through ReaPack.

REAPER 7.74 is the minimum because Reference synchronization uses the
ProjectMarker APIs introduced in REAPER 7.62 and `set_config_var_string`, added
in REAPER 7.74, to mirror project timecode and frame-rate state. The main script
checks the REAPER version and required APIs before opening the UI; loading
ReaImGui through its `0.9` compatibility API provides the corresponding UI
version check.

No standalone Lua or Python runtime is required by the REAPER scripts.

## Repository layout

```text
scripts/   REAPER action entry points
src/       Lua modules
tests/     dependency-free Lua tests run inside REAPER
docs/      product and architecture documentation
```

## Development actions

Load these files from REAPER's Action List:

- `scripts/ReaProjectLink.lua` opens the current development UI;
- `scripts/ReaProjectLink_RunTests.lua` runs the Lua unit tests and reports the
  result in both the REAPER console and a message box.

The test action creates and closes an isolated temporary Project Tab. It does not
run adapter mutation tests against the user's active project.

The entry points resolve modules relative to the repository, so the checkout
does not need to be copied into REAPER's resource directory during development.

## Verification

The automated suite exercises pure domain behavior, in-memory transaction
failures, the real Windows filesystem, real REAPER Track/Item/Take APIs, and a
ReaImGui frame. It also injects failures after partial Import, Update, and Reference
synchronization mutations and verifies that REAPER Undo restores Tracks, Items,
Takes, fields, timeline state, and project extension state. Run
`ReaProjectLink - Run Tests` from the Action List after changing workflow, manifest,
filesystem, or adapter behavior.
