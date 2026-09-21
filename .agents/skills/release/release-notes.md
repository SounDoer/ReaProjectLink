## What's changed

{{changelog, one bullet per line}}

## Install

1. Install [ReaPack](https://reapack.com/) and ReaImGui.
2. In REAPER, choose Extensions > ReaPack > Import repositories and add:
   ```
   https://github.com/SounDoer/ReaProjectLink/raw/master/index.xml
   ```
3. Choose Extensions > ReaPack > Browse packages, find ReaProjectLink, and
   install it.
4. Run `Script: ReaProjectLink.lua` from the Action List.

## Update

Choose Extensions > ReaPack > Synchronize packages. To go back to an earlier
version, right-click ReaProjectLink in Browse packages and pick it under
Versions.

{{pre-release only:}}
This is a pre-release. ReaPack installs it only when pre-releases are enabled:
Extensions > ReaPack > Manage repositories > Options > Enable pre-releases
globally.
{{end pre-release only}}

## Requirements

- REAPER {{minimum_reaper_version}} or newer
- ReaImGui {{minimum_reaimgui_api}} or newer
