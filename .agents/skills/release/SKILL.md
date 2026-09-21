---
name: release
description: Use when publishing a new ReaProjectLink version to ReaPack users, including pre-releases, or when the user asks to release, ship, bump the version, tag, or create a GitHub Release for this repository.
---

# Release ReaProjectLink

## Overview

ReaPack publishes a version when a commit on `master` changes `@version` in
`ReaProjectLink/ReaProjectLink.lua`; the `deploy` workflow then commits
`index.xml`. The Git tag and GitHub Release point at the version-bump commit,
never at the bot's index commit.

Pushing the bump publishes to every ReaPack user and cannot be taken back.
Confirm the version and changelog with the user before pushing.

## Steps

### 1. Preflight

```bash
git switch master && git pull --ff-only && git status --short
```

Stop if the tree is dirty. Find the previous release and what changed:

```bash
git describe --tags --abbrev=0
git log <previous-tag>..HEAD --oneline -- ReaProjectLink/
```

No shipped changes since the previous tag → nothing to release; tell the user.

### 2. Agree on version and changelog

Propose the next version (SemVer: patch = fixes, minor = features, major =
breaking manifest or workflow compatibility) and a changelog drafted from the
commits, written for users rather than developers. Wait for the user's
confirmation.

A version containing letters (`0.2.0-beta1`) is a ReaPack pre-release that
only users with pre-releases enabled receive; its GitHub Release gets
`--prerelease`. The new version must be greater than every indexed version.

### 3. Run the tests (PowerShell)

REAPER must not be running: `Get-Process reaper` returns nothing. If it is
running, ask the user to close it.

```powershell
$root = (git rev-parse --show-toplevel); $reaper = "C:\Program Files\REAPER (x64)\reaper.exe"
Remove-Item "$root\tests\.last-result", "$root\tests\.last-ui-result" -ErrorAction SilentlyContinue
$p = Start-Process $reaper -ArgumentList "-new","-nosplash","`"$root\tests\run_in_reaper.lua`"" -PassThru; $null = $p.WaitForExit(180000)
Get-Content "$root\tests\.last-result"
$env:REAPROJECTLINK_UI_SMOKE_RESULT = "$root\tests\.last-ui-result"
$p = Start-Process $reaper -ArgumentList "-new","-nosplash","`"$root\tests\run_ui_smoke.lua`"" -PassThru; $null = $p.WaitForExit(120000)
Remove-Item Env:REAPROJECTLINK_UI_SMOKE_RESULT; Get-Content "$root\tests\.last-ui-result"
```

Both files must start with `PASS`. Otherwise stop and report the failure.

### 4. Bump and commit

Edit the header of `ReaProjectLink/ReaProjectLink.lua`: set `@version` and
**replace** the `@changelog` body (ReaPack keeps older versions' changelogs
itself). Keep the `--   ` indentation:

```lua
-- @version 0.2.0
-- @changelog
--   Add Delivery rename support.
--   Fix Reference sync when the Master has no Markers.
```

```bash
git commit -am "chore(release): 0.2.0" && git rev-parse HEAD   # record RELEASE_SHA
```

### 5. Push and wait for deploy

Confirm with the user, then:

```bash
git push origin master
gh run list --workflow deploy --commit <RELEASE_SHA>   # get the run id
gh run watch <run-id> --exit-status
git pull --ff-only    # fetch the bot's "index: ..." commit
```

The deploy log must report `1 new version`. `0 new version` means `@version`
did not change or is not greater than an existing one.

### 6. Verify the public index

```bash
curl -sfL https://github.com/SounDoer/ReaProjectLink/raw/master/index.xml | grep -c 'version name="0.2.0"'
```

Must print `1`.

### 7. Tag and GitHub Release

```bash
git tag -a v0.2.0 <RELEASE_SHA> -m "ReaProjectLink 0.2.0"
git push origin v0.2.0
gh release create v0.2.0 --verify-tag --title "ReaProjectLink 0.2.0" --notes-file <notes.md>
```

Write `<notes.md>` from `release-notes.md` in this skill's directory. Fill every
`{{...}}` placeholder: the changelog, and the requirement versions from
`M.minimum_reaper_version` and `M.minimum_reaimgui_api` in
`ReaProjectLink/lib/reaprojectlink/runtime_requirements.lua`. Keep the
pre-release paragraph only for pre-release versions and drop its markers.
Always keep the Install and Update sections. Add `--prerelease` for pre-release
versions.

### 8. Report

Version, release commit, Release URL, and test results.

## Common mistakes

| Mistake | Consequence |
|---|---|
| Tagging `HEAD` after `git pull` | Tag lands on the bot's index commit, not the release |
| Appending to `@changelog` | Old notes get repeated in the new version |
| Skipping `git pull` after deploy | Next push is rejected (bot commit on remote) |
| New spec file missing from `tests/specs.lua` | It never runs; check every `tests/*_spec.lua` is listed |
| Shipped file outside `lib/reaprojectlink/` | Not published unless added to `@provides` |
