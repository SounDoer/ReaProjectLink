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

The entry points resolve modules relative to the repository, so the checkout
does not need to be copied into REAPER's resource directory during development.
