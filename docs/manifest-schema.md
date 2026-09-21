# Delivery Manifest schema

This is the implemented MVP field-level schema. It is not yet published as a
separate machine-readable JSON Schema document.

## Stable entry point

The Master Project repeatedly reads `_ReaProjectLink/<project-name>/delivery.json`:

```json
{
  "schemaVersion": 1,
  "sourceProjectId": "24703b21-...",
  "deliveryId": "8aa9cb40-...",
  "latestDeliveryRevision": 18,
  "manifest": "history/delivery-0018.json"
}
```

Publish replaces this file atomically only after media and the immutable history
manifest are complete and validated.

## Complete publish snapshot

`history/delivery-0018.json` contains the complete effective Delivery state:

```json
{
  "schemaVersion": 1,
  "sourceProjectId": "24703b21-...",
  "deliveryId": "8aa9cb40-...",
  "sourceProjectName": "CIN_030_DX",
  "sourceProjectFile": "../../../CIN_030_DX.rpp",
  "deliveryRevision": 18,
  "publishedAt": "2026-09-13T10:30:00+08:00",
  "publishedBy": "Alice",
  "reference": {
    "referenceId": "cin030-reference",
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
          "mediaRevision": 1,
          "mediaFile": "../media/clip-014/Commander_Radio_Close.wav",
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
- Every Delivery Revision creates new revision-local Clips. Their
  `mediaRevision` is `1`, and each Clip owns a new immutable managed WAV.
- Media paths are relative to the history manifest.
- A Delivery `mediaFile` must use the canonical `../media/...` form and resolve
  inside the current managed package. Absolute paths and directory traversal are
  rejected. Reference `videoFile` remains an intentional external NAS reference.
- Position, duration, source offset, and fades use integer samples.
- `displayName` and `order` support presentation only and never establish
  identity.
- `sourceProjectFile` is informational and is not part of synchronization.
- Source REAPER Track and Item GUIDs remain in source-project metadata and are not
  exposed as cross-project identity.
- `publishedAt` and `publishedBy` are audit metadata.

## Reference Manifest

The stable Reference entry point is
`_ReaProjectLink/<master-project-name>/reference.json`:

```json
{
  "schemaVersion": 2,
  "masterProjectId": "f962b473-...",
  "referenceId": "cin030-reference",
  "latestReferenceRevision": 12,
  "manifest": "history/reference-0012.json"
}
```

The referenced immutable Reference Manifest records registered video
Tracks, Items, Markers, Regions, and their shared timing context:

```json
{
  "schemaVersion": 2,
  "masterProjectId": "f962b473-...",
  "referenceId": "cin030-reference",
  "referenceRevision": 12,
  "masterProjectName": "CIN_030_MASTER",
  "publishedAt": "2026-09-13T10:30:00+08:00",
  "publishedBy": "Alice",
  "alignmentMode": "mirror",
  "timeline": {
    "sampleRate": 48000,
    "projectTimecodeOffsetSamples": 172800000,
    "referenceStartSamples": 172800000,
    "referenceStartMarkerId": "marker-reference-start",
    "frameRate": {
      "numerator": 24000,
      "denominator": 1001,
      "dropFrame": false
    }
  },
  "lanes": [{
    "laneId": "reference-lane-main",
    "displayName": "Reference Main",
    "order": 0,
    "items": [{
      "itemId": "reference-item-12",
      "displayName": "CIN_030 v12",
      "videoFile": "\\\\nas\\project\\reference\\CIN_030_v0012.mov",
      "videoHash": "sha256:...",
      "startSamples": 172800000,
      "sourceOffsetSamples": 0,
      "durationSamples": 14400000,
      "playbackRate": 1.0
    }]
  }],
  "markers": [{
    "entryId": "marker-reference-start",
    "name": "FFOP",
    "startSamples": 172800000
  }],
  "regions": []
}
```

Every `videoFile` references its original NAS asset and is not copied into
`_ReaProjectLink`. Consumers verify each `videoHash`; the historical manifest remains
valid as a record even when external video is no longer available. The
unpublished single-video Reference schema is unsupported; development builds must
regenerate their Reference package using schema version 2.

`referenceStartMarkerId` is optional. It identifies one registered Marker as
the Reference Start without assigning meaning to the Marker's name. When it is
absent, `referenceStartSamples` is zero and project zero is the Reference Start.

## Schema compatibility

`schemaVersion` is an integer. Additive optional fields do not require a new
version, and readers ignore fields they do not recognize. Removing fields or
changing their type or meaning requires a new version.

Historical manifests remain immutable and are never migrated in place. A newer
tool may convert a supported older manifest into its current in-memory model. An
unsupported newer version blocks import, update, and Publish and tells the user
to upgrade ReaProjectLink. Before publishing, a writer checks the package's current
schema and must not overwrite it with an older schema version.

Readers validate pointer paths, required field types, package identity, revision
identity, and unique Lane, Clip, Item, Marker, and Region IDs before using a
Manifest. A malformed or mismatched historical Manifest blocks the operation
rather than being interpreted as another Source or Reference.
