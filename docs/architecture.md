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

Each `.rpp` is initialized in one explicit MVP mode. Source mode owns Delivery
Tracks, Picture subscription, and audio Publish. Mix mode owns Picture Publish,
source subscriptions, first import, and revision updates.

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

A mix project uses the same managed-root convention for Picture publication:

```text
<mix-rpp-directory>\
  CIN_030_MIX.rpp

  _Delivery\
    CIN_030_MIX\
      picture.json
      picture-history\
```

A source project manually selects `picture.json` on first subscription and then
tracks its stable Picture ID and manifest path.

Publication should be atomic:

1. prepare copied media and metadata in a staging location;
2. validate every output's file size and content hash;
3. write an immutable history manifest;
4. move completed media into its final location;
5. replace the stable pointer (`delivery.json` or `picture.json`) last, using a
   temporary file and same-filesystem rename.

Until the last step succeeds, consumers continue to see the previous successful
revision. Interrupted staging data is never treated as published data; the tool
may report and safely clean it up later.

## Publish concurrency

A managed delivery package has a short-lived Publish lock. Lock acquisition must
be atomic on the shared filesystem and covers only the Publish transaction, not
ordinary `.rpp` editing. Lock metadata identifies the user, machine, and start
time so a blocked publisher can understand who owns it.

After acquiring the lock, the publisher rereads the stable manifest and compares
its revision with the revision used by the Publish review. A mismatch aborts the
transaction and requires a fresh scan and review. Normal completion and handled
failure release the lock. A lock left by a crash is never stolen or expired
automatically; the UI offers an explicit stale-lock removal action.

## Retention

The MVP retains every published manifest and managed WAV revision indefinitely.
This is necessary because historical Takes in any consuming Mix project may
still reference those files, while ReaDelivery has no global consumer registry
that could prove a revision is unused. The tool may report package size but does
not offer automatic or manual garbage collection within its UI.

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

Durable authoring state is stored inside the `.rpp`, not in a sibling sidecar.
Project extension state holds the project mode, project identity, subscriptions,
accepted revision pointers, and Mix bindings. Source Tracks carry Lane IDs;
source Items carry Clip IDs. A linked Mix Item carries its upstream Clip ID plus
a distinct local Instance ID. Historical manifests provide three-way-comparison
baselines without embedding full prior snapshots in the project.

Copy and split operations in a Mix retain Clip identity but produce distinct
Instance identities. A duplicate Clip ID discovered among Source Items is not
silently repaired: Publish review requires the user to classify the relationship.

After review resolves any new or ambiguous identities, Source and Picture
Publish save the `.rpp` before touching the managed package. This guarantees that
the IDs behind a published manifest survive reopening the project. A save
failure aborts publication; IDs saved before a later package failure remain safe
to reuse on retry. Normal REAPER Save is not a publication action. Mix import and
update operations follow normal REAPER editing semantics and leave the project
dirty for the user to save.

Publication is not part of REAPER's undo history. Once the stable manifest points
to a successful immutable revision, ReaDelivery does not delete, overwrite, or
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

The Publish review classifies changes as Added, Audio Changed, Placement Changed,
Metadata Changed, Unchanged, Retired, Needs Decision, or Blocked. An unresolved
item blocks publication until the user classifies it or removes it from the
delivery surface. Filename, duration, and audio similarity are never
authoritative identity signals.

The MVP presents this as a table grouped by Delivery Lane. The header shows the
outgoing publish revision, reviewed Picture revision, output path, and blocker
count. Row labels are Added, Audio Changed, Placement Changed, Metadata Changed,
Unchanged, Retired, Needs Decision, and Blocked; Unchanged is collapsed by
default. Users resolve new or ambiguous identities and any FX override in this
review, but cannot select only part of the set. The final action is `Save &
Publish` for the complete snapshot.

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

Every successful source Publish increments `publishRevision`. Each Clip's
`mediaRevision` increments only when its WAV content hash changes. Metadata-only
changes reuse the previous media revision. Picture publication maintains its own
independent `pictureRevision`; there is no `clipRevision` in the MVP.

`delivery.json` is a small stable entry point that references the latest
immutable, complete history manifest. Historical manifests are snapshots rather
than deltas. See `manifest-schema.md` for the current field-level draft.

Each Publish scans all registered Delivery Tracks and uses every item's active
take. Track and item mute state are playback choices and do not affect delivery
membership. Empty items and non-audio media are ineligible; missing or offline
audio blocks publication. The resulting manifest is a complete snapshot even
though unchanged clips reuse their existing media revisions. Partial publication
is outside the MVP.

## Mix-side bindings

The MVP assumes a new mix workflow initialized through ReaDelivery. It does not
scan legacy mix projects to infer bindings for previously imported WAVs.

The mix project owns all integration mappings:

```text
Delivery Lane ID <-> Mix Track GUID
Delivery Clip ID <-> one or more Mix Item Instance GUIDs
```

A source project never stores mix-project paths or target-track GUIDs. This makes
one source publish reusable by multiple mix projects and guarantees that only
the active mix project process modifies its `.rpp`.

On first import, the mix user maps each delivery lane to an existing track, asks
the tool to create a corresponding track under a selected folder, or skips it.
One lane to one track is the default suggestion, but multiple lanes may target
the same track. Name matching may suggest an initial mapping but requires user
confirmation; the persisted binding uses Lane ID and Track GUID.

The tool then creates and tags items using the published media, timeline
position, source offset, duration, display metadata, Clip ID, media revision, and
picture revision. Initial item state also includes fades, item gain, and basic
non-plug-in take parameters. It does not copy source-project FX, Track
Volume/Pan, routing, automation, Take FX, track layout, or the full source folder
hierarchy. Those properties are owned by the mix project after import.

The first-import screen presents this as a compact Lane mapping table. Bulk
controls create new tracks under one selected Folder Track, offer name-based
mapping suggestions, or skip selected rows. Created tracks follow Lane order and
display names. One confirmed operation creates Tracks, Items, bindings, and the
accepted revision as a single undo point. Removing a subscription later leaves
imported project content intact.

The screen compares the Source's reviewed Picture identity and revision with the
Mix's authoritative Picture. Different Picture IDs block import. The same ID at
different revisions produces a prominent warning that the mix user may
explicitly override.

A Delivery Lane added by a later Publish remains unmapped until the mix user
chooses or creates its target track. A retired source lane does not cause its
bound mix track or items to be deleted.

## Revision update

For an existing delivery clip, an accepted update should:

1. locate every still-linked mix instance by internal Delivery Clip ID;
2. let the user include or exclude individual instances from the update;
3. duplicate each included instance's current active take where appropriate;
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

The update screen compares three states per Mix Instance: its last handled
delivery baseline, the latest upstream publish, and its current local state. A
Source-only change defaults to Use Source, a Mix-only change remains local, and
an equal result is accepted. When both changed a field differently, the field is
a conflict defaulting to Keep Mix. Position, length, source offset, fades, item
gain, and supported Take parameters each offer only Keep Mix or Use Source in the
MVP.

Audio-content acceptance remains independent and offers Accept as New Take or
Skip This Instance. Bulk actions accept all new audio, keep all Mix edits, or use
Source for unmodified Items. Applying the chosen updates creates one undo point.
Each Instance stores its accepted media revision separately from its last handled
Source-state revision, allowing some Instances or media changes to remain
pending without losing their comparison baseline.

Copying or splitting a managed mix item creates multiple instances of the same
Delivery Clip. Each remains eligible for later updates until the user explicitly
detaches it. A detached instance becomes an ordinary REAPER item.

The MVP copies basic take parameters when creating the new revision take: source
offset, volume, pan, playback rate, pitch, channel mode, and polarity. Item-level
state and track-level mix state remain in place. Take FX, take envelopes, stretch
markers, take markers, and complex source wrappers are outside automatic
migration; detecting any of them requires a warning and an explicit skip or
replace-anyway decision.

## Picture dependency

The mix project's authoritative video item is assigned a stable Picture ID. An
explicit picture Publish creates a manifest containing at least:

- picture revision;
- media path and content hash;
- timeline position;
- source offset;
- duration and playback rate;
- frame rate and project timecode offset.

For the initial design, the authoritative picture item's left edge defines
Picture Start. Source projects synchronize this reference, and delivery clip
placement is expressed as an integer sample offset from Picture Start. On import,
the mix project adds that offset to its own Picture Start. This avoids depending
on identical absolute REAPER project positions while retaining sub-frame audio
precision.

Source projects may automatically detect a new picture revision, but they do not
automatically adopt it. A source project records separate synchronized and
reviewed states. Audio Publish records the reviewed picture revision.

Picture Publish references the authoritative video file at its existing NAS path
and records a content hash; it does not duplicate the video under `_Delivery`.
Video-file retention and historical recovery remain the responsibility of the
external picture-asset workflow.

Each successful Picture Publish adds an immutable
`picture-history/picture-NNNN.json`; these small records are retained
indefinitely and `picture.json` points to the latest one. Consumers revalidate
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
