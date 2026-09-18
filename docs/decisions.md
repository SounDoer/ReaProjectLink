# Decision log

This file records decisions reached during product discovery. The current MVP
product baseline has no remaining open product questions.

## Confirmed decisions

### D001 — Local NAS architecture

The first version is entirely local. Existing NAS storage is the shared exchange
medium. Cloud services are out of scope.

### D002 — Source folder autonomy

Dialogue, music, and sound-effects teams keep their own directory structures and
working conventions. ReaDelivery does not infer roles or relationships from NAS
paths or filenames.

### D003 — Tool-managed publish directory

Each saved source `.rpp` publishes beneath:

```text
<source-rpp-directory>\_Delivery\<source-project-name>\
```

The underscore marks the directory as tool-managed.

### D004 — Explicit Publish boundary

Saving a source project does not create a delivery update. Only an explicit,
successful Publish operation creates a new published revision.

### D005 — Manifest-based consumption

Mix projects consume a small published Manifest and rendered WAV files. They do
not parse or open a foreign source `.rpp` as the synchronization mechanism.

### D006 — Mix project is the dependency hub

The mix project actively adds, browses, imports, and updates source deliveries.
Source projects do not directly modify or target the mix project.

### D007 — Internal identity, not naming conventions

The tool generates stable Source, Set, Lane, and Clip IDs. Names and paths are
display metadata and are not used as the authoritative update match.

### D008 — Dedicated delivery tracks

Source users manually register and remove designated delivery/print tracks
through the tool. Their names and locations are flexible, but only registered
delivery items on these tracks are eligible for publication.

### D009 — Supported delivery topology

The model must support:

1. one track containing one long item;
2. one track containing multiple independent items;
3. multiple tracks containing multiple independent items.

### D010 — Updates use new takes

An accepted WAV revision is added as a new take on the existing bound mix item.
The track and item are not recreated for routine updates.

### D011 — Manual take cleanup

The tool never automatically deletes old takes. Cleanup may be assisted by the
tool but must be explicitly initiated by the user.

### D012 — Picture authority

The mix project owns the sole authoritative picture track. It explicitly
publishes picture revisions for source projects to detect, synchronize, and
review.

### D013 — No automatic picture adoption

No picture update is semantically safe merely because its duration, start,
offset, and frame rate are unchanged. Source users must confirm synchronization
and review.

### D014 — Picture revision traceability

Every source audio Publish records the picture revision against which the source
was reviewed. The mix project warns about deliveries based on an older picture.

### D015 — Source identity survives rename and move

Source Project ID is generated on first Publish and is independent of `.rpp`
filename and path. A Save As operation must distinguish continuing the same
logical source from creating a new source project.

### D016 — Bounce method is not prescribed

Source users may create bounced WAVs and items using any REAPER workflow. The
tool begins managing content only after the resulting item is placed on a
designated delivery track and included in an explicit Publish.

### D017 — Delivery tracks represent current state

Items on designated delivery tracks represent the source project's current
effective delivery state. Historical bounce items should not be laid out beside
current items on those tracks; history belongs in takes, non-delivery tracks, or
the managed `_Delivery` package.

### D018 — Publish resolves item lineage

Publish compares the current delivery-track snapshot with the previous published
snapshot. Existing internal Clip IDs identify known deliveries. For unregistered
items, the tool may suggest an existing clip using track and timeline context,
but the user must confirm ambiguous update-versus-new relationships.

### D019 — Identity outranks matching heuristics

An existing Delivery Clip ID is the only authoritative proof of continuity.
Track, position, overlap, duration, filename, and audio similarity may support a
suggestion but must not silently establish identity.

### D020 — Unresolved Publish changes block publication

Publish presents additions, updates, position changes, removals, and ambiguous
items before writing a new revision. Every ambiguous item must be classified as a
new clip, an update to an existing clip, or removed from the delivery surface
before Publish can complete.

### D021 — Structural replacements are not routine revisions

One-to-many and many-to-one replacements are structural changes. For the initial
design, retire the previous clip or clips and create new ones rather than
pretending that the result is an ordinary one-to-one media revision. Downstream
items are not automatically deleted.

### D022 — The mix project owns first-import mapping

On first import, the mix user maps each source Delivery Lane to an existing mix
track, creates a corresponding track under a selected folder, or skips the lane.
One source lane to one mix track is the default suggestion, not a restriction.
The confirmed binding uses internal Lane ID and mix Track GUID rather than names.

### D023 — First import copies delivery data, not source structure

First import creates mix items from published media, timeline placement, source
offset, duration, display metadata, Clip ID, media revision, and picture revision.
It does not copy source-project FX, routing, automation, track layout, or the full
folder hierarchy. After import, mix properties are owned by the mix project.

### D024 — Later lane topology changes require mapping

A newly published Delivery Lane remains unmapped until the mix user selects or
creates a target track. Retiring a source lane never automatically deletes its
bound mix track or items.

### D025 — Picture Start is the timeline anchor

For the initial design, the left edge of the authoritative picture item is the
Picture Start. Delivery clip positions are stored as integer sample offsets
relative to Picture Start rather than as absolute REAPER project positions.
Frame rate and displayed timecode are validation and presentation metadata.

### D026 — A delivery clip may have multiple mix instances

A Delivery Clip may bind to one or more mix items after the mixer copies or
splits an imported item. Routine updates can add the new media revision to every
still-linked instance while preserving each instance's local edit state.

### D027 — Media and placement updates are separate

Accepting a new audio revision creates a new take without implicitly accepting
upstream position or duration changes. Upstream placement changes are presented
and applied separately. For a locally edited item, preserving local placement is
the default.

### D028 — Bindings support explicit detach

A copied or split mix item remains linked to its Delivery Clip by default. The
user may explicitly detach an instance, after which it becomes an ordinary
REAPER item and receives no later delivery revisions.

### D029 — Picture is the domain term

The synchronization domain object is named Picture because it includes revision,
timeline, timecode, and review state in addition to a media file. Concrete media
fields use names such as `videoFile`; Chinese UI may display “参考视频” or
“画面版本”.

### D030 — Picture media is referenced, not copied

Picture Publish records the authoritative NAS video path and content hash. It
does not copy the video file into the managed `_Delivery` package. Historical
picture manifests do not guarantee recovery if an externally managed video file
is overwritten or removed.

### D031 — Picture Manifest location and subscription

The mix project publishes Picture state beneath:

```text
<mix-rpp-directory>\_Delivery\<mix-project-name>\picture.json
```

Historical manifests live under `picture-history`. A source project manually
selects `picture.json` on first subscription and subsequently follows the stable
Picture ID and manifest path.

### D032 — MVP take-state boundary

When creating a new mix take, the MVP preserves item- and track-level state and
copies basic take parameters: source offset, volume, pan, playback rate, pitch,
channel mode, and polarity. Take FX, take envelopes, stretch markers, take
markers, and complex source wrappers are not migrated automatically. Detection
of these advanced states produces a warning and requires the user to skip or
explicitly replace anyway.

### D033 — MVP starts with new projects

The MVP supports projects initialized and first-imported through ReaDelivery. It
does not adopt or infer bindings for WAVs and items already present in legacy mix
projects.

### D034 — Projects have one explicit MVP mode

On first use, a `.rpp` is initialized as either a Source Project or a Mix
Project. Source mode manages delivery tracks, Picture subscription, and audio
Publish. Mix mode manages authoritative Picture publication and source-delivery
imports and updates. The MVP does not combine both modes in one project.

### D035 — Delivery Tracks are registered manually

The MVP does not provide or inspect template markers for Delivery Tracks. A
Source user selects tracks and explicitly adds or removes them through the tool;
Lane IDs are generated during registration.

### D036 — Publish scans the complete delivery surface

The MVP scans every registered Delivery Track on each Publish and publishes the
active take of every delivery item. Track and item mute state do not exclude
content. Only audio media is eligible; missing or offline media blocks Publish.
Each manifest is a complete current snapshot, while only changed clips receive a
new media revision. The MVP has no partial `Publish Selected` operation.

### D037 — Published audio is copied into managed storage

Publish copies each changed Active Take's audio into `_Delivery/media` as an
immutable media revision. Manifests do not depend on the original bounce path
remaining available. Unchanged content is not copied again. This differs from
Picture media, which is referenced in place.

### D038 — User names are preserved as display metadata

An Item or Active Take name is preserved as `displayName` for UI, search, and a
readable managed filename, but never determines identity. Managed media uses a
single-underscore revision suffix such as
`Commander_Radio_Close_r0001.wav`; unnamed content uses `clip_r0001.wav`.
Renaming without an audio hash change does not create a new media revision.

### D039 — Audio Publish performs a byte-for-byte copy

Publish copies the Active Take's original file-backed WAV without rendering or
transcoding it. Delivery-track or item processing is not baked into the managed
media copy.

### D040 — First import reproduces basic item presentation

First import applies the published source offset and item length together with
item fades, item gain, and basic non-plug-in take parameters. It does not copy
source Track FX, Track Volume/Pan, Track Automation, or Take FX.

### D041 — Unbaked FX block Publish by default

Because Audio Publish copies the original WAV, Delivery Track FX and Take FX are
not included. Detecting either blocks Publish by default and tells the user to
bounce the processing. The user may explicitly choose `Publish Anyway`; the tool
must not silently imply that the copied WAV matches processed playback.

### D042 — The MVP uses two audio revision levels

Every successful source Publish increments the set-level `publishRevision`.
An individual Clip increments `mediaRevision` only when its WAV content hash
changes. Metadata-only changes may therefore advance `publishRevision` without
creating a new media revision. The MVP has no separate `clipRevision`.

### D043 — Delivery Manifest uses a stable pointer and full snapshots

The stable `delivery.json` contains schema and source identity plus a pointer to
the latest immutable `history/publish-NNNN.json`. Every historical manifest is a
complete delivery snapshot, not a delta. Media paths are relative to the history
manifest, timing values are integer samples, and source REAPER Track/Item GUIDs
remain private to the source `.rpp`.

### D044 — Publish becomes visible atomically

Publish prepares new media and the immutable history manifest in staging, then
validates file size and content hashes before moving them to their final managed
paths. It replaces the stable `delivery.json` pointer only as the final
same-filesystem atomic operation. A failed or interrupted Publish therefore
leaves consumers on the previous successful revision. Incomplete staging data is
not a published revision and may be reported and safely cleaned up later.

### D045 — Lock only the Publish transaction

ReaDelivery does not lock a Source `.rpp` during ordinary editing and does not
replace the team's existing REAPER save discipline. A short-lived lock in the
managed delivery package serializes Publish transactions. If another publisher
holds it, Publish is blocked and the lock owner, machine, and start time are
shown. After acquiring the lock, the tool rereads `delivery.json` and aborts for
a fresh review if its reviewed base revision is no longer current. The lock is
released after success or failure. An apparently stale lock is never removed
automatically; removing it requires an explicit user action.

### D046 — MVP retains all published audio revisions

The MVP never automatically deletes published manifests or managed WAV
revisions and provides no garbage-collection command. Old Mix Takes may still
reference any historical WAV, and the tool has no complete registry of all Mix
consumers from which to prove that a revision is unused. The UI may report
storage usage, but users should not manually remove files from `_Delivery`.

### D047 — Schema evolution is additive or explicitly versioned

Manifest `schemaVersion` is an integer. A schema version may gain optional
fields, and readers ignore unknown fields. Removing a field or changing its
meaning or type requires a new version. Historical manifests are immutable and
are never migrated in place. Newer tools may read supported older versions by
converting them into the current internal model. A tool encountering a newer,
unsupported version blocks import, update, and Publish with an upgrade message;
an older tool must not downgrade-write a package already published with a newer
schema.

### D048 — Picture history preserves records, not video media

Every Picture Publish writes an immutable
`picture-history/picture-NNNN.json`, while stable `picture.json` points to the
latest successful revision. Picture manifests are retained indefinitely. The
tool rechecks the referenced video's content hash, so replacement at the same
path is reported as a mismatch rather than silently accepted. A missing or moved
historical video is shown as unavailable; ReaDelivery preserves the version
record but cannot restore media that the external picture-asset workflow did not
retain.

### D049 — Durable project state lives inside the `.rpp`

ReaDelivery stores project mode and project-level identity and revision pointers
in REAPER project extension state. Lane identity is attached to its source Track,
and Clip identity is attached to its source Item. Mix projects store source
subscriptions and Lane-to-Track bindings in their own project state; linked Mix
Items carry both the upstream Clip ID and a distinct local Instance ID. No
project sidecar file is introduced beside the `.rpp`. Historical baselines are
loaded from the accepted immutable manifest revision instead of duplicating full
snapshots inside the project.

Copying or splitting a Mix Item retains its Clip ID but requires a new Instance
ID. Duplicate Clip IDs found in a Source project are ambiguous and must be
resolved during Publish review as either a new Clip or an intentional
replacement relationship.

### D050 — Publish saves durable identity before external commit

After Publish review resolves identities, Source and Picture Publish first save
the current `.rpp` and then begin the atomic package transaction. A project-save
failure aborts before publication. IDs saved before a later publication failure
remain valid for retry. Ordinary REAPER Save never triggers Publish. Mix import
and update operations modify and dirty the Mix project, but saving those changes
remains the mix user's decision.

### D051 — Published history is corrected by a later revision

A successful Publish is an external append-only event and cannot be reversed by
REAPER Undo. The MVP does not delete or overwrite a published revision or point
the stable manifest back to an older one. An accidental publication is corrected
by fixing the Source and publishing a new revision; revision numbers are never
reused. Mix projects do not automatically accept a publish. If the Source is
undone after Publish, the tool reports that its current state differs from the
latest published snapshot.

### D052 — Publish Review presents one complete change set

Publish Review is a table grouped by Delivery Lane, with the outgoing publish
revision, reviewed Picture revision, output path, and blocker count visible. Its
Clip states are Added, Audio Changed, Placement Changed, Metadata Changed,
Unchanged, Retired, Needs Decision, and Blocked. Unchanged rows are collapsed by
default. Retired Clips remain downstream and unresolved identity, missing media,
or unreadable media blocks Publish. Detected FX blocks by default but retains the
explicit Publish Anyway override. The MVP has no per-Clip selection: confirmation
publishes the complete Delivery Set through a `Save & Publish` action.

### D053 — Identity suggestions are transparent and never automatic

For an untagged current Item, candidates are limited to Clips present in the
previous snapshot but absent from the current scan. Candidates from the same
Lane rank first, followed by explainable signals such as timeline proximity and
overlap, duration similarity, identical audio hash, and display-name similarity.
The UI shows these reasons rather than a synthetic confidence score. Even a
single strong candidate requires the user to choose either Create New Clip or
Link as New Revision. A Clip still present in the current scan is ineligible as
a candidate, preventing duplicate identity.

### D054 — First import uses a compact Lane mapping table

Mix adds a Source by selecting its `delivery.json`, then maps each Lane to Create
New Track, Map to Existing Track, or Skip for Now. Bulk actions create all lanes
under a selected Folder Track, suggest existing tracks by name, or skip selected
lanes. Suggestions always require confirmation; multiple Lanes may target one
Track. New tracks use Lane display names and preserve Lane order. Confirmation
creates Tracks, Items, bindings, and the accepted revision in one undo point.
Skipped Lanes remain available for later mapping. Removing a Source subscription
does not delete imported Tracks or Items.

The screen shows Source identity and path, publish revision, Clip counts, and the
Source-reviewed versus current Mix Picture revision. A Picture ID mismatch blocks
import. Matching Picture IDs with different revisions produce a prominent but
explicitly overridable warning.

### D055 — Mix update resolves state per field and per Instance

The update screen compares each linked Mix Instance's last handled Baseline,
latest Source state, and current Mix state. Source-only changes default to Use
Source; Mix-only changes remain local; equal results are accepted; divergent
changes are conflicts defaulting to Keep Mix. Position, length, source offset,
fades, item gain, and supported Take parameters each offer only Keep Mix or Use
Source in the MVP.

Media acceptance is independent and offers Accept as New Take or Skip This
Instance. Multiple copied or split Instances are handled separately. Bulk actions
accept all new audio, keep all Mix edits, or use Source for unmodified Items. One
Apply operation creates one REAPER undo point. Each Instance records its accepted
media revision separately from its last handled Source-state revision so partial
updates remain trackable.

### D056 — MVP uses Lua ReaScript and ReaImGui

The MVP is implemented as Lua 5.4 ReaScripts with ReaImGui as an accepted runtime
dependency. Pure-Lua domain and manifest logic remains separated from the REAPER
adapter and ReaImGui presentation layers. Python, a standalone desktop app, and
a native C++ REAPER extension are outside the initial implementation. A native
extension may be reconsidered later if continuous monitoring or stronger
filesystem and lifecycle integration becomes necessary.

### D057 — An unchanged Picture does not publish a new revision by default

Picture Publish Review compares the selected Item against the latest published
snapshot across every manifest field except the revision number and publication
metadata. An identical Picture blocks Publish and offers an explicit
`Publish Anyway` override, because D014 makes every source project treat a newer
Picture revision as a mandatory re-synchronize and re-review. This differs from
D042, where each source Publish always advances `publishRevision`.
