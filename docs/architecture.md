# Architecture

## High-level data flow

```text
Dialogue.rpp --Publish--\
Music.rpp    --Publish----> Delivery manifests/WAVs --> Master Project
SFX.rpp      --Publish--/                                  |
                                                            v
                                                     Cinematic Master.rpp

Cinematic Master.rpp --Publish Reference--> Dialogue/Music/SFX projects
```

The NAS is shared storage. No cloud service or central database is required for
the initial design.

Each `.rpp` is initialized with exactly one Project Type. A Source Project owns
Delivery Tracks, a Reference Subscription, and Delivery Publish. A Master
Project owns Reference Publish, Delivery Subscriptions, first import, and
Delivery updates.

## Managed delivery package

The source project's location is unrestricted. Its publish root is derived from
the saved `.rpp` location:

```text
<source-rpp-directory>\
  CIN_030_DX.rpp

  _ReaProjectLink\
    CIN_030_DX\
      delivery.json
      media\
      history\
```

`_ReaProjectLink` indicates that the directory is managed by the tool. The project-name
level prevents collisions if multiple `.rpp` files share a directory.

The stable `delivery.json` entry point identifies the latest successful publish.
Historical publish manifests and immutable media revisions remain available
under `history` and `media`.

Every audio file referenced by a source Active Take is copied into a new Clip
directory during Publish. The managed copy is immutable and remains valid if
the original bounce is moved, renamed, or deleted. Each Delivery Revision is
self-contained and does not reuse Clip identity from an older Revision.

This is a byte-for-byte copy of the Active Take's original file-backed WAV. The
Publish operation does not render, transcode, or bake item, take, track, or FX
processing into that media revision.

Publish validation detects Delivery Track FX and Take FX. Either condition blocks
by default with guidance to bounce the processing, while an explicit `Publish
Anyway` override remains available. The warning must state that the copied media
does not include those effects.

Each revision-local Clip ID owns its media directory. A sanitized, length-limited Item
or Active Take display name may make the file readable, for example
`Commander_Radio_Close.wav`; an unnamed item uses `clip.wav`.
Identity and revision come from the manifest and Clip ID directory, never from
this filename.

A Master Project uses the same managed-root convention for Reference publication:

```text
<master-rpp-directory>\
  CIN_030_MASTER.rpp

  _ReaProjectLink\
    CIN_030_MASTER\
      reference.json
      history\
```

A source project manually selects `reference.json` on first subscription and then
tracks its stable Reference ID and manifest path.

Publication should be atomic:

1. prepare copied media and metadata in a staging location;
2. validate every output's file size and content hash;
3. write an immutable history manifest;
4. move completed media into its final location;
5. replace the stable pointer (`delivery.json` or `reference.json`) last, using a
   temporary file and same-filesystem rename.

Until the last step succeeds, consumers continue to see the previous successful
revision. Interrupted staging data is never treated as published data; the tool
may report and safely clean it up later. If interruption happens after an
immutable history manifest is moved but before its stable pointer is replaced, a
retry may reuse that orphan only when every semantic field still matches; fresh
publication time and user metadata do not turn an otherwise identical retry into
an immutable collision.

## Publish concurrency

A managed delivery package has a short-lived Publish lock. Lock acquisition must
be atomic on the shared filesystem and covers only the Publish transaction, not
ordinary `.rpp` editing. Lock metadata identifies the user, machine, and start
time so a blocked publisher can understand who owns it.

After acquiring the lock, the publisher rereads the stable manifest and compares
its revision with the revision used by the Publish Review. A mismatch aborts the
transaction and requires a fresh scan and review. Normal completion and handled
failure release the lock. A lock left by a crash is never stolen or expired
automatically. The UI explains Publishing Is Locked and offers the explicitly
confirmed Unlock Publishing action.

## Retention

The MVP retains every published manifest and managed WAV revision indefinitely.
This is necessary because historical Takes in any consuming Master Project may
still reference those files, while ReaProjectLink has no global consumer registry
that could prove a revision is unused. The tool may report package size but does
not offer automatic or manual garbage collection within its UI.

## Identity hierarchy

External names are for display only. The tool creates and persists internal
identities:

```text
Source Project ID
  -> Delivery ID
       -> Delivery Lane ID
            -> Delivery Clip ID
                 -> Media Revision
```

- **Source Project:** one logical authoring project, independent of its filename
  or path.
- **Delivery:** an atomic group published together.
- **Delivery Lane:** a designated source track and its logical counterpart in a
  Master Project.
- **Delivery Clip:** one Item in one immutable Delivery Revision.
- **Media Revision:** retained as a manifest field and always `1` for a
  revision-local Clip.

REAPER project, track, item, and take GUIDs may be recorded as implementation
handles, but they are not the cross-project domain identity. ReaProjectLink IDs are
stored in REAPER extension data and repeated in manifests.

Durable authoring state is stored inside the `.rpp`, not in a sibling sidecar.
Project extension state holds the Project Type, Project ID, Subscriptions,
revision pointers, and Lane Bindings. Source Tracks carry stable Lane IDs;
Source Items receive fresh Clip IDs on each Publish. A synchronized Master Item
carries its Source Project ID, Delivery Lane ID, and revision-local Clip ID. The
Delivery Lane ID lets ReaProjectLink detect when the
Item has been moved away from its bound Master Track.

Source and Reference Publish save the `.rpp` before touching the managed
package. This guarantees that the identities behind a published manifest
survive reopening the project. A save failure aborts publication; IDs saved
before a later package failure remain safe to reuse on retry. Normal REAPER Save is not a publication action. Delivery import and
update operations follow normal REAPER editing semantics and leave the project
dirty for the user to save.

Publication is not part of REAPER's undo history. Once the stable manifest points
to a successful immutable revision, ReaProjectLink does not delete, overwrite, or
rewind it. Corrections are expressed as later revisions. Undoing the Source after
Publish only changes the working project, which the tool then reports as
different from the latest published snapshot.

## Delivery shapes

The hierarchy supports all agreed layouts:

```text
one lane / one long item
one lane / multiple independent items
multiple lanes / multiple independent items
```

Dedicated delivery tracks form the publication boundary. Their location and
visible names are not prescribed, but only registered delivery items on those
tracks participate in synchronization. Source users explicitly add or remove
these tracks through the tool; the MVP has no template-discovery behavior.

The tool does not prescribe how source users create bounced WAVs. A user may use
any REAPER render, apply, record, or custom-action workflow, then move the current
effective bounced item onto a designated delivery track before publishing.

Delivery tracks describe the current effective delivery state, not a timeline of
all historical bounces. Previous versions belong in takes, outside the delivery
tracks, or in the managed delivery package.

On Publish, the tool scans the current Delivery Tracks as one complete snapshot.
Every Item becomes a new revision-local Clip regardless of its prior Clip ID.
Splits, joins, copies, additions, removals, placement changes, and renames need
no lineage classification.

The Delivery Publish Review is grouped by Delivery Lane. The header shows the
outgoing Delivery Revision, Reviewed Reference Revision, output path, and blocker
count. Readable Items are Included; missing or unsupported media is Blocked.
Users may resolve the explicit FX override, but cannot select only part of the
snapshot. The final action is `Save & Publish Delivery`.

Every successful Source Publish increments `deliveryRevision`. Each new Clip has
`mediaRevision` 1 and its WAV is copied into that Clip's unique directory.
Reference publication maintains its own independent `referenceRevision`.

`delivery.json` is a small stable entry point that references the latest
immutable, complete history manifest. Historical manifests are snapshots rather
than deltas. See `manifest-schema.md` for the implemented MVP fields.

Each Delivery Publish scans all registered Delivery Tracks and uses every Item's
active Take. Track and Item mute state are playback choices and do not affect
Delivery membership. Empty Items and non-audio media are ineligible; Media File
Not Found blocks publication. The resulting Manifest is a complete snapshot.
Partial publication is outside the MVP.

## Master-side bindings

The MVP assumes a new Master Project workflow initialized through ReaProjectLink. It does not
scan legacy Master Projects to infer bindings for previously imported WAVs.

The Master Project owns all integration mappings:

```text
Delivery Lane ID <-> Master Track GUID
```

A Source Project never stores Master Project paths or target Track GUIDs. This makes
one source publish reusable by multiple Master Projects and guarantees that only
the active Master Project process modifies its `.rpp`.

On first import, the Master user maps each delivery lane to an existing track, asks
the tool to create a corresponding Track under a selected Folder Track, or
chooses Leave Unmapped.
One lane to one track is the default suggestion, but multiple lanes may target
the same track. Name matching may suggest an initial mapping but requires user
confirmation; the persisted binding uses Lane ID and Track GUID.

The tool then creates and tags Source-managed Items using the published media, timeline
position, source offset, duration, display metadata, Clip ID, media revision, and
reference revision. Initial item state also includes fades, item gain, and basic
non-plug-in take parameters. It does not copy source-project FX, Track
Volume/Pan, routing, automation, Take FX, track layout, or the full source folder
hierarchy. Those Track-level properties are owned by the Master Project. Imported
Item state remains owned by the Source while the Item is managed.

The first-import screen presents this as a compact Lane mapping table. Bulk
controls create new tracks under one selected Folder Track, offer name-based
mapping suggestions, or leave selected Lanes unmapped. Created Tracks follow Lane order and
display names. One confirmed operation creates Tracks, Items, bindings, and the
accepted revision as a single undo point. Removing a subscription later leaves
imported project content intact.

The screen compares the Source's reviewed Reference identity and revision with the
Master Project's authoritative Reference. Different Reference IDs block import. The same ID at
different revisions produces a prominent warning that the Master user may
explicitly override.

A Delivery Lane added by a later Publish remains unmapped until the Master User
chooses or creates its target Track. A Lane absent from a later snapshot leaves
its Master Track and Track-level mixing state intact, but its previous managed
Items are removed during synchronization.

## Revision update

Delivery synchronization is snapshot replacement:

1. validate every WAV and every Lane Mapping in the target Delivery Revision;
2. locate every still-managed Item for the Delivery;
3. delete those Items;
4. import every target Clip onto its bound Delivery Track;
5. persist the handled Delivery Revision;
6. commit the whole operation as one REAPER Undo step.

This preserves Master Track objects and therefore their routing, Track FX,
automation, folder structure, and other Track-level mixing state. Item-level
changes on a managed Item are intentionally replaced by the Source snapshot.
There are no per-Clip, per-field, Take, Retired, or Decline decisions.

The Delivery Update Review shows the target Revision and the counts of managed
Items being replaced and Source Items being imported. Any published Revision can
be targeted. The currently handled Revision can be synchronized again, allowing
the Source snapshot to be restored after a managed Item was deleted or detached.

When a managed Item is moved away from the Master Track bound to its Delivery Lane,
ReaProjectLink asks whether to keep it as local Master content. Confirmation
clears its Delivery ownership without moving it again, and later synchronization
does not touch it. Declining leaves it managed; the next synchronization replaces
it. There is no reattach operation—synchronizing restores a fresh Source-owned
copy on the bound Track.

## Reference dependency

The Master Project publishes one atomic Reference. Its stable Reference ID
identifies the Reference rather than any individual video Item. The publication surface
contains every Item on explicitly registered Reference Tracks plus explicitly
registered Markers and Regions. Tracks, Items, Markers, and Regions receive stable
cross-project identities so later revisions can update or retire the corresponding
managed content without relying on names or REAPER-local GUIDs.

Each immutable Reference manifest contains the complete current surface:

- reference revision and stable lane, Item, Marker, and Region identities;
- each video's external media path and content hash;
- Item position, source offset, duration, and playback rate;
- Marker and Region names, colors, and positions;
- project sample rate, frame rate, and project timecode offset;
- an optional `referenceStartMarkerId` naming one registered Marker.

The Reference Start Marker is optional and independent of the Marker's displayed
name. Without one, project zero is the Reference Start. `FFOP` remains a valid
user-chosen Marker name, not a ReaProjectLink role.

Delivery subscriptions default to Mirror Master Timeline. Synchronization adopts
the Master's timecode offset and frame rate and places managed video Items,
Markers, and Regions at the same absolute timeline positions. It does not force
the Source project's sample rate. Relative Reference remains an explicit
alternative and maps published positions relative to the Source's existing
Reference Start.

If a later revision moves every stable Reference timeline element by the
same amount, the Source UI reports that delta and may explicitly shift the entire
Source project, including all Items, Markers, and Regions, before synchronizing.
This operation is never automatic. Moving only the Reference Start or only part
of the Reference does not offer the full-project shift.

Source projects may automatically detect a new reference revision, but they do not
automatically adopt it. Delivery Publish records the Reference revision the user
declares in the Review, defaulting to the synchronized revision (D086).

Reference Publish references each authoritative video file at its existing NAS path
and records a content hash; it does not duplicate videos under `_ReaProjectLink`.
Video-file retention and historical recovery remain the responsibility of the
external reference-asset workflow.

Each successful Reference Publish adds an immutable
`history/reference-NNNN.json`; these small records are retained
indefinitely and `reference.json` points to the latest one. Consumers revalidate
the referenced video's hash. Replacement at the same path is a mismatch, while
a missing historical file makes that revision unavailable without erasing its
record.

## MVP implementation stack

The MVP uses Lua 5.4 ReaScript for direct REAPER integration and ReaImGui for its
interactive UI. The code is divided into three boundaries:

- pure-Lua domain and manifest logic;
- a REAPER adapter for project inspection, extension state, Items, Takes, Tracks,
  and undo points;
- a ReaImGui presentation layer for Publish Review, first-import mapping, and
  revision-conflict workflows.

ReaImGui is an accepted runtime dependency. Python, a standalone desktop app,
and a native C++ extension are outside the initial implementation. A native
extension may be reconsidered later if continuous monitoring, stronger
filesystem integration, or more reliable lifecycle hooks become necessary.
