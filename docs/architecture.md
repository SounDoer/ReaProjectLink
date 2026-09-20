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

Changed audio referenced by a source Active Take is copied into `media` during
Publish. The managed copy is immutable and remains valid if the original bounce
is moved, renamed, or deleted. Unchanged content reuses its existing managed
revision rather than being copied again.

This is a byte-for-byte copy of the Active Take's original file-backed WAV. The
Publish operation does not render, transcode, or bake item, take, track, or FX
processing into that media revision.

Publish validation detects Delivery Track FX and Take FX. Either condition blocks
by default with guidance to bounce the processing, while an explicit `Publish
Anyway` override remains available. The warning must state that the copied media
does not include those effects.

Each Clip ID owns its media-revision directory. A sanitized, length-limited Item
or Active Take display name may make the file readable, for example
`Commander_Radio_Close_r0001.wav`; an unnamed item uses `clip_r0001.wav`.
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
- **Delivery Clip:** one persistent deliverable represented by an item.
- **Media Revision:** one bounced WAV version of that clip.

REAPER project, track, item, and take GUIDs may be recorded as implementation
handles, but they are not the cross-project domain identity. ReaProjectLink IDs are
stored in REAPER extension data and repeated in manifests.

Durable authoring state is stored inside the `.rpp`, not in a sibling sidecar.
Project extension state holds the Project Type, Project ID, Subscriptions,
revision pointers, and Lane Bindings. Source Tracks carry Lane IDs; Source Items
carry Clip IDs. A Linked Item carries its upstream Clip ID plus a distinct
internal Instance ID. Historical Manifests provide three-way-comparison
baselines without embedding full prior snapshots in the project.

Copy and split operations in a Master Project retain Clip identity but produce
distinct internal Instance IDs. A duplicate Clip ID discovered among Source Items is not
silently repaired: Delivery Publish Review requires the user to classify the relationship.

After review resolves any new or ambiguous identities, Source and Reference
Publish save the `.rpp` before touching the managed package. This guarantees that
the IDs behind a published manifest survive reopening the project. A save
failure aborts publication; IDs saved before a later package failure remain safe
to reuse on retry. Normal REAPER Save is not a publication action. Delivery import and
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

On Publish, the tool compares the current delivery-track snapshot with the last
published snapshot:

- an item with an existing Delivery Clip ID is an existing logical delivery;
- an unregistered item may be a new delivery or a new revision of an old one;
- track and timeline overlap may be used to suggest a relationship, but not to
  decide an ambiguous relationship silently;
- a previously published clip that is absent becomes a removal candidate and is
  not automatically deleted downstream.

The Delivery Publish Review classifies changes as Added, Audio Changed,
Placement Changed, Metadata Changed, Unchanged, Retired, Needs Classification,
or Blocked. An unresolved Item blocks publication until the user classifies it or removes it from the
delivery surface. Filename, duration, and audio similarity are never
authoritative identity signals.

The MVP presents this as a table grouped by Delivery Lane. The header shows the
outgoing Delivery Revision, Reviewed Reference Revision, output path, and blocker
count. Row labels are Added, Audio Changed, Placement Changed, Metadata Changed,
Unchanged, Retired, Needs Classification, and Blocked; Unchanged is collapsed by
default. Users resolve new or ambiguous identities and any FX override in this
Review, but cannot select only part of the set. The final action is `Save &
Publish Delivery` for the complete snapshot.

Identity matching is advisory rather than score-driven. For an untagged current
Item, the candidate set contains only prior Clips missing from the current scan.
Same-Lane candidates sort first, followed by visible evidence such as timeline
proximity and overlap, duration similarity, identical media hash, and name
similarity. The user always chooses Create New Clip or Link as New Revision; no
candidate is accepted automatically. A prior Clip that is still present cannot
be selected, which prevents duplicate identity.

One-to-many and many-to-one replacements are structural changes. The initial
model retires the old logical clips and creates new clips; it does not collapse
those changes into a routine revision or automatically delete downstream items.

Every successful source Publish increments `deliveryRevision`. Each Clip's
`mediaRevision` increments only when its WAV content hash changes. Metadata-only
changes reuse the previous media revision. Reference publication maintains its own
independent `referenceRevision`; there is no `clipRevision` in the MVP.

`delivery.json` is a small stable entry point that references the latest
immutable, complete history manifest. Historical manifests are snapshots rather
than deltas. See `manifest-schema.md` for the implemented MVP fields.

Each Delivery Publish scans all registered Delivery Tracks and uses every Item's
active Take. Track and Item mute state are playback choices and do not affect
Delivery membership. Empty Items and non-audio media are ineligible; Media File
Not Found blocks publication. The resulting Manifest is a complete snapshot even
though unchanged clips reuse their existing media revisions. Partial publication
is outside the MVP.

## Master-side bindings

The MVP assumes a new Master Project workflow initialized through ReaProjectLink. It does not
scan legacy Master Projects to infer bindings for previously imported WAVs.

The Master Project owns all integration mappings:

```text
Delivery Lane ID <-> Master Track GUID
Delivery Clip ID <-> one or more Linked Item Instance IDs
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

The tool then creates and tags items using the published media, timeline
position, source offset, duration, display metadata, Clip ID, media revision, and
reference revision. Initial item state also includes fades, item gain, and basic
non-plug-in take parameters. It does not copy source-project FX, Track
Volume/Pan, routing, automation, Take FX, track layout, or the full source folder
hierarchy. Those properties are owned by the Master Project after import.

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
chooses or creates its target track. A retired source lane does not cause its
bound Master Track or items to be deleted.

## Revision update

For an existing delivery clip, an accepted update should:

1. locate every Linked Item by Delivery Clip ID and internal Instance ID;
2. let the user make decisions for each Linked Item;
3. add a new Take to each selected Linked Item where appropriate;
4. replace only the duplicate take's PCM source with the new WAV;
5. label the new take with its delivery revision;
6. make it active;
7. retain all older takes;
8. create an undo point and update the accepted dependency revision.

This keeps the track and item stable while preserving track routing, track FX,
automation, item placement, and previous audio revisions. Old takes are removed
only by an explicit user action.

Changes to duration, timeline position, source offset, channel layout, or sample
rate require a warning and explicit handling policy. The tool must not silently
delete items when a source clip disappears from a later publish.

The Delivery Update Review compares Baseline, Delivery, and Local state for each
Linked Item. A
Delivery-only change defaults to Use Delivery, a Local-only change remains local, and
an equal result is accepted. When both changed a field differently, the field is
a conflict defaulting to Keep Local. Position, length, source offset, fades, item
gain, and supported Take parameters each offer only Keep Local or Use Delivery in the
MVP.

Audio-content acceptance remains independent and offers Add New Take or Keep
Current Media. Bulk actions use Add All as New Takes, Keep All Local Changes, or
Use Delivery for Unmodified Items. Applying the chosen updates creates one undo
point. Each Linked Item stores its Accepted Media Revision separately from its
Handled Delivery Revision, allowing some Linked Items or media changes to remain
pending without losing their comparison baseline.

Copying or splitting a managed Linked Item creates multiple Linked Items for the same
Delivery Clip. Each remains eligible for later updates until the user explicitly
detaches it. A detached Linked Item becomes an ordinary REAPER Item.

The MVP copies basic take parameters when creating the new revision take: source
offset, volume, pan, playback rate, pitch, channel mode, and polarity. Item-level
state and Track-level local state remain in place. Take FX, Take envelopes, stretch
markers, take markers, and complex source wrappers are outside automatic
migration. Add New Take requires explicit confirmation when unsupported Take
data is detected; Keep Current Media remains available.

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
automatically adopt it. A source project records separate synchronized and
reviewed states. Delivery Publish records the Reviewed Reference Revision.

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
