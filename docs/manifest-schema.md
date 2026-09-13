# Delivery Manifest schema

This is the current MVP field-level draft. It records confirmed semantics but is
not yet a formal JSON Schema.

## Stable entry point

The mix project repeatedly reads `_Delivery/<project-name>/delivery.json`:

```json
{
  "schemaVersion": 1,
  "sourceProjectId": "24703b21-...",
  "deliverySetId": "8aa9cb40-...",
  "latestPublishRevision": 18,
  "manifest": "history/publish-0018.json"
}
```

Publish replaces this file atomically only after media and the immutable history
manifest are complete and validated.

## Complete publish snapshot

`history/publish-0018.json` contains the complete effective delivery state:

```json
{
  "schemaVersion": 1,
  "sourceProjectId": "24703b21-...",
  "deliverySetId": "8aa9cb40-...",
  "sourceProjectName": "CIN_030_DX",
  "sourceProjectFile": "../../../CIN_030_DX.rpp",
  "publishRevision": 18,
  "publishedAt": "2026-09-13T10:30:00+08:00",
  "publishedBy": "Alice",
  "picture": {
    "pictureId": "cin030-picture",
    "reviewedRevision": 12
  },
  "sampleRate": 48000,
  "lanes": [
    {
      "laneId": "lane-a",
      "displayName": "DX Main",
      "order": 0,
      "clips": [
        {
          "clipId": "clip-014",
          "displayName": "Commander Radio Close",
          "mediaRevision": 4,
          "mediaFile": "../media/clip-014/Commander_Radio_Close_r0004.wav",
          "mediaHash": "sha256:...",
          "mediaSampleRate": 48000,
          "channelCount": 1,
          "startOffsetSamples": 720000,
          "sourceOffsetSamples": 0,
          "lengthSamples": 183360,
          "itemGain": 1.0,
          "fadeInSamples": 0,
          "fadeOutSamples": 480,
          "take": {
            "volume": 1.0,
            "pan": 0.0,
            "playbackRate": 1.0,
            "pitch": 0.0,
            "channelMode": 0,
            "polarityInverted": false
          }
        }
      ]
    }
  ]
}
```

## Semantics

- A history manifest is a full snapshot, never a delta.
- An unchanged Clip reuses its prior `mediaRevision` and managed WAV.
- Media paths are relative to the history manifest.
- Position, duration, source offset, and fades use integer samples.
- `displayName` and `order` support presentation only and never establish
  identity.
- `sourceProjectFile` is informational and is not part of synchronization.
- Source REAPER Track and Item GUIDs remain in source-project metadata and are not
  exposed as cross-project identity.
- `publishedAt` and `publishedBy` are audit metadata.

## Picture Manifest

The stable Picture entry point is
`_Delivery/<mix-project-name>/picture.json`:

```json
{
  "schemaVersion": 1,
  "pictureId": "cin030-picture",
  "latestPictureRevision": 12,
  "manifest": "picture-history/picture-0012.json"
}
```

The referenced immutable Picture manifest records the externally managed video
and its timing context:

```json
{
  "schemaVersion": 1,
  "pictureId": "cin030-picture",
  "pictureRevision": 12,
  "mixProjectName": "CIN_030_MIX",
  "publishedAt": "2026-09-13T10:30:00+08:00",
  "publishedBy": "Alice",
  "videoFile": "\\\\nas\\project\\picture\\CIN_030_v0012.mov",
  "videoHash": "sha256:...",
  "sampleRate": 48000,
  "pictureStartSamples": 0,
  "sourceOffsetSamples": 0,
  "durationSamples": 14400000,
  "playbackRate": 1.0,
  "frameRate": {
    "numerator": 24000,
    "denominator": 1001,
    "dropFrame": false
  },
  "projectTimecodeOffsetSamples": 0
}
```

`videoFile` references the original NAS asset and is not copied into `_Delivery`.
Consumers verify `videoHash`; the historical manifest remains valid as a record
even when its external video is no longer available.

## Schema compatibility

`schemaVersion` is an integer. Additive optional fields do not require a new
version, and readers ignore fields they do not recognize. Removing fields or
changing their type or meaning requires a new version.

Historical manifests remain immutable and are never migrated in place. A newer
tool may convert a supported older manifest into its current in-memory model. An
unsupported newer version blocks import, update, and Publish and tells the user
to upgrade ReaDelivery. Before publishing, a writer checks the package's current
schema and must not overwrite it with an older schema version.
