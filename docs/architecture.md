# Architecture

## High-level data flow

```text
Dialogue.rpp --Publish--\
Music.rpp    --Publish----> Delivery manifests/WAVs --> Mix dependency manager
SFX.rpp      --Publish--/                                  |
                                                            v
                                                     Cinematic Mix.rpp

Cinematic Mix.rpp --Publish picture revision--> Dialogue/Music/SFX projects
```

The NAS is shared storage. No cloud service or central database is required for
the initial design.

## Managed delivery package

The source project's location is unrestricted. Its publish root is derived from
the saved `.rpp` location:

```text
<source-rpp-directory>\
  CIN_030_DX.rpp

  _Delivery\
    CIN_030_DX\
      delivery.json
      media\
      history\
```

`_Delivery` indicates that the directory is managed by the tool. The project-name
level prevents collisions if multiple `.rpp` files share a directory.

The stable `delivery.json` entry point identifies the latest successful publish.
Historical publish manifests and immutable media revisions remain available
under `history` and `media`.

Publication should be atomic:

1. render into a staging location;
2. validate every output;
3. write an immutable history manifest;
4. move completed media into its final location;
5. replace `delivery.json` last, using a temporary file and same-filesystem
   rename.

## Identity hierarchy

External names are for display only. The tool creates and persists internal
identities:

```text
Source Project ID
  -> Delivery Set ID
       -> Delivery Lane ID
            -> Delivery Clip ID
                 -> Media Revision
```

- **Source Project:** one logical authoring project, independent of its filename
  or path.
- **Delivery Set:** an atomic group published together.
- **Delivery Lane:** a designated source track and its logical counterpart in a
  mix project.
- **Delivery Clip:** one persistent deliverable represented by an item.
- **Media Revision:** one bounced WAV version of that clip.

REAPER project, track, item, and take GUIDs may be recorded as implementation
handles, but they are not the cross-project domain identity. ReaDelivery IDs are
stored in REAPER extension data and repeated in manifests.

## Delivery shapes

The hierarchy supports all agreed layouts:

```text
one lane / one long item
one lane / multiple independent items
multiple lanes / multiple independent items
```

Dedicated delivery tracks form the publication boundary. Their location and
visible names are not prescribed, but only registered delivery items on those
tracks participate in synchronization.

## Mix-side bindings

The mix project owns all integration mappings:

```text
Delivery Lane ID <-> Mix Track GUID
Delivery Clip ID <-> Mix Item GUID
```

A source project never stores mix-project paths or target-track GUIDs. This makes
one source publish reusable by multiple mix projects and guarantees that only
the active mix project process modifies its `.rpp`.

On first import, the mix user maps each delivery lane to an existing track or asks
the tool to create one. The tool then creates and tags the corresponding items.

## Revision update

For an existing delivery clip, an accepted update should:

1. locate the bound mix item by internal Delivery Clip ID;
2. duplicate the current active take where appropriate;
3. replace only the duplicate take's PCM source with the new WAV;
4. label the new take with its delivery revision;
5. make it active;
6. retain all older takes;
7. create an undo point and update the accepted dependency revision.

This keeps the track and item stable while preserving track routing, track FX,
automation, item placement, and previous audio revisions. Old takes are removed
only by an explicit user action.

Changes to duration, timeline position, source offset, channel layout, or sample
rate require a warning and explicit handling policy. The tool must not silently
delete items when a source clip disappears from a later publish.

## Picture dependency

The mix project's authoritative video item is assigned a stable Picture ID. An
explicit picture Publish creates a manifest containing at least:

- picture revision;
- media path and content hash;
- timeline position;
- source offset;
- duration and playback rate;
- frame rate and project timecode offset.

Source projects may automatically detect a new picture revision, but they do not
automatically adopt it. A source project records separate synchronized and
reviewed states. Audio Publish records the reviewed picture revision.

## Suggested REAPER integration

The first prototype can use ReaScript for UI, project metadata, rendering actions,
manifest generation, and source replacement. A native C++ extension can be
considered later if continuous monitoring, stronger filesystem integration, or
more reliable lifecycle hooks are required.
