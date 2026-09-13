# Development

## Runtime

- REAPER with embedded Lua 5.4;
- ReaImGui 0.9-compatible API or newer, installed through ReaPack.

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

- `scripts/ReaDelivery.lua` opens the current development UI;
- `scripts/ReaDelivery_RunTests.lua` runs the Lua unit tests and reports the
  result in both the REAPER console and a message box.

The test action creates and closes an isolated temporary Project Tab. It does not
run adapter mutation tests against the user's active project.

The entry points resolve modules relative to the repository, so the checkout
does not need to be copied into REAPER's resource directory during development.

## Verification

The automated suite exercises pure domain behavior, in-memory transaction
failures, the real Windows filesystem, real REAPER Track/Item/Take APIs, and a
ReaImGui frame. Run `ReaDelivery - Run Tests` from the Action List after changing
workflow, manifest, filesystem, or adapter behavior.
