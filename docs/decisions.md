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

This early design used the left edge of one authoritative picture Item as the
alignment anchor. It was withdrawn before release and is superseded by D063 and
D064; no compatibility path for this unpublished design is maintained.

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

Terminology superseded by D070. The synchronization and review behavior remains,
but the public domain term is now Reference.

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

Terminology superseded by D069. The mutually exclusive single-level project
classification remains part of the product model.

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
replacement relationship. Every Item sharing a duplicated Clip ID requires its
own decision, and at most one of them may keep the ID, because the Item that
keeps it silently replaces the audio of the Mix Item already bound to that Clip.

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

Picture Publish Review compares the complete registered Master Reference surface
against the latest published snapshot across every manifest field except the
revision number and publication metadata. An identical Picture blocks Publish
and offers an explicit
`Publish Anyway` override, because D014 makes every source project treat a newer
Picture revision as a mandatory re-synchronize and re-review. This differs from
D042, where each source Publish always advances `publishRevision`.

### D058 — A Lane binding routes new Clips only

The Lane-to-Track binding of D022 decides where the next new Clip is created; it
never constrains Items that already exist. Clip and Instance identity live on the
Item, so moving an Item to another Mix Track keeps it updatable and does not ask
the mix user to map anything again. Update Review therefore lists every mapped
Lane with its current target Track and allows pointing it at another Track, which
is the only way to make future Clips follow Items that were moved.

### D059 — A Clip is pending until an Item carries it or the mix user declines it

Update Review no longer treats a passing `acceptedPublishRevision` as proof that
a Clip was handled. A Clip of the targeted snapshot is offered for import unless
a Mix Item already carries it or its ID is listed in the subscription's
`declinedClips`. Deleting an Item therefore offers its Clip again, and Skip
becomes a durable decision that the review keeps visible and reversible.

### D060 — Update Review targets any published revision

Because every published snapshot is immutable and its media files are retained,
Update Review accepts a target revision instead of always using the latest one.
Rolling back is the same per-field review as moving forward, so Mix edits are
never overwritten silently, and a media revision that merely differs from the
accepted one counts as pending. The target only governs ReaDelivery-managed
fields; restoring the rest of a Mix project remains REAPER's own concern.

### D061 — Master Reference replaces the single-Item Picture surface

Terminology superseded by D070. The multi-Track, multi-Item, and registered
timeline structure remains part of the Reference model.

The Mix project publishes one authoritative Master Reference Set. Its complete
snapshot may contain multiple registered Picture Tracks, multiple video Items,
registered Markers, and registered Regions. Track, Item, Marker, and Region
continuity uses internal stable IDs rather than names or paths. The existing
`picture.json` location and Picture ID remain the compatibility entry point.

### D062 — Picture Tracks and timeline entries are explicitly registered

Mix users register Picture Tracks, Markers, and Regions through ReaDelivery.
Publish scans every registered Picture Track and includes every video Item on
it. Unregistered timeline annotations remain private to the Mix project. A
deleted registered Marker or Region is retired by the next complete snapshot.

### D063 — FFOP is an optional semantic role

Terminology superseded by D071. The optional anchor behavior remains, but
ReaProjectLink names the role Reference Start rather than FFOP.

A registered Marker may be assigned the unique `FFOP` semantic role. FFOP is
not required, but when present it is the Master Reference Start used for
relative offsets and alignment validation. The tool never infers this role from
the Marker name alone. Without a semantic Reference Start, project zero is the
reference position.

### D064 — Source subscriptions mirror the Master timeline by default

First subscription defaults to Mirror Master Timeline. Source projects adopt
the Master project timecode offset and frame rate, and synchronized video Items,
Markers, and Regions use the same absolute project positions. Project sample
rate is not forced. Relative Reference remains an explicit alternative.

### D065 — Timeline rebases require explicit whole-project confirmation

When every stable element in an already synchronized Master Reference moves by
the same delta, Update Review shows that exact delta. The user may explicitly
shift every Source media Item, Marker, and Region before synchronizing the
managed Master Reference surface. ReaDelivery never performs this project-wide
move silently, and a partial move or an isolated FFOP change does not offer it.

### D066 — Master Reference schema version 2

Multi-track video and timeline annotations use Picture Manifest schema version
2. The unpublished single-video schema is unsupported and has no migration path.
Delivery Manifest schema versioning is independent.

### D067 — Transient workflow state is scoped to one open REAPER project

Picture status, Publish Reviews, Import and Update Reviews, mapping decisions,
warning overrides, whole-project shift choices, and observed Publish locks belong
only to the REAPER project in which they were created. Switching Project Tabs,
loading another project, or changing the project path clears this transient UI
state. Every mutating action also validates its captured runtime project token;
Source and Master Reference Publish Reviews additionally become stale after the
project changes and must be refreshed before Publish.

### D068 — Product name is ReaProjectLink

The product is named ReaProjectLink. It coordinates Delivery and Reference
workflows between independent REAPER projects. Delivery remains the name of one
directional workflow and is no longer the product-level name.

The concise product description is: "Source-Master project coordination for
REAPER." The product name is written exactly as `ReaProjectLink`, without spaces
or hyphens.

### D069 — Source and Master are mutually exclusive Project Types

The MVP keeps its single-level centralized topology. Multiple Source Projects
publish to one Master Project, and the Master Project publishes the shared
Reference back to its Source Projects. Multi-level project dependency chains are
outside the current design.

`Source Project` and `Master Project` are the two public Project Types. They
replace the former Source/Mix mode terminology. One `.rpp` cannot hold both
Project Types. Source User, Source Team, Master User, and Master Team identify
people or organizations only when that distinction is needed.

### D070 — Delivery and Reference are the two directional domains

A Source Project publishes a Delivery to the Master Project. The Master Project
publishes a Reference to its Source Projects. Reference replaces Picture,
Master Reference, and Master Reference Set as the public domain term.

A Reference contains registered reference media, a Reference Timeline of
registered Markers and Regions, and their timing context. The Master Project is
the authority for the Reference, so `authoritative Reference` is explanatory
wording rather than a separate object or routine UI label.

The public revision states on a Source Project are Latest Revision,
Synchronized Revision, and Reviewed Revision. Synchronization materializes a
Reference revision in the Source Project. Review is a separate explicit user
confirmation. A Source Delivery records the Reviewed Revision.

### D071 — Reference Start is optional and generic

FFOP is not a ReaProjectLink domain role. A user may optionally assign one
registered Marker the Reference Start role, regardless of that Marker's name.
`FFOP` remains valid as a user-chosen industry Marker name and as the expansion
"First Frame of Picture", but the tool does not require or infer it.

Without an assigned Reference Start Marker, project zero is the Reference Start.
This has no material effect on Mirror Master Timeline alignment and supplies the
default anchor for Relative Reference alignment.

### D072 — Public Audio Delivery hierarchy

A Source Project publishes one logical Delivery. Every successful audio Publish
creates a Delivery Revision. `Delivery Revision` replaces public use of Publish
Revision and Published Revision. `Delivery Set` is not public terminology.

A registered Source REAPER Track is a Delivery Track. Its stable published route
is a Delivery Lane. A stable logical audio unit is a Delivery Clip, and a
specific WAV-content version of that Clip is a Media Revision.

The Master Project subscribes to a Delivery. A Delivery Clip may be represented
by one or more Linked Items in the Master Project. Instance ID remains an
internal identity; routine UI refers to Linked Items rather than Mix Item
Instances.

### D073 — Subscription, Mapping, Binding, and Link are distinct

A Delivery Subscription is the persistent relationship between a Master Project
and one Source Delivery. Lane Mapping is the user's destination choice during a
review. Confirming it creates or changes a persistent Lane Binding from a
Delivery Lane to a Master Track. A Link associates a Delivery Clip with one
concrete Linked Item.

Lane Mapping offers Create New Track, Use Existing Track, and Leave Unmapped.
`Leave Unmapped` replaces the overloaded `Skip for Now` wording. A Lane Binding
routes future new Clips only and does not constrain existing Linked Items.

Unrepresented Clips are Pending Clips. A user may Import Clip, Decline Clip, or
Reconsider a previously Declined Clip. Detach Linked Item removes its Link while
leaving an ordinary REAPER Item in place.

### D074 — Reviews and update decisions use qualified terms

Workflow reviews are named Delivery Publish Review, Reference Publish Review,
Delivery Import Review, Delivery Update Review, and Reference Update Review.
Reviewed Revision remains the separate semantic confirmation that a Source user
has reviewed a synchronized Reference Revision.

Delivery Publish Review uses Added, Audio Changed, Placement Changed, Metadata
Changed, Unchanged, Retired, Needs Classification, and Blocked. Identity actions
are Create New Clip, Continue Existing Clip, Keep Clip Identity, and Clear
Classification.

Delivery Update Review compares Baseline, Delivery, and Local state. Its
comparison terms are Delivery-only Change, Local-only Change, Same Change,
Conflict, and Unchanged. Field decisions are Use Delivery and Keep Local. Media
actions are Add New Take and Keep Current Media. Bulk actions use Add All as
New Takes, Keep All Local Changes, and Use Delivery for Unmodified Items.

Unregister stops managing a registered object. Remove Subscription removes the
relationship while retaining created REAPER objects. Retire means an upstream
logical object is absent from the current Delivery and does not delete its
downstream representation. Detach removes a Link while retaining the Item.
Delete is reserved for actual object or file deletion.

### D075 — Workflow verbs have one directional meaning

Publish creates a new externally visible immutable revision. Source Projects use
Save & Publish Delivery, and Master Projects use Save & Publish Reference.
Ordinary REAPER Save never means Publish.

Subscribe creates a persistent relationship. Add Delivery creates a Delivery
Subscription in a Master Project, while Subscribe to Reference creates a
Reference Subscription in a Source Project. Stable manifest filenames are file
selection details rather than primary action labels.

Import creates previously unrepresented Delivery Tracks or Items in the Master
Project. Update compares a Delivery Revision with local Master state and applies
selected changes through Apply Delivery Update. Synchronize materializes a
Reference Revision in a Source Project. Reference synchronization remains
distinct from Mark Reference Reviewed.

Apply executes a plan prepared by a Review. It is used for Apply Delivery Update
and Apply Lane Mapping, but not as a synonym for Publish, Import, or Synchronize.

### D076 — The pre-release rename is complete and has no legacy aliases

The implementation will be renamed from ReaDelivery to ReaProjectLink as one
coherent pre-release change. The managed root becomes `_ReaProjectLink`. Source
packages retain `delivery.json` and use `history/delivery-NNNN.json`; Master
packages use `reference.json` and `history/reference-NNNN.json`.

Public and persisted names use Project Type, Master, Reference, Delivery
Revision, and the other confirmed terminology. The project extension namespace,
`P_EXT` keys, Lua module directory, `require` paths, scripts, tests, UI title,
manifest fields, and documentation are renamed together.

No compatibility aliases remain for ReaDelivery, Mix Project, Picture, Master
Reference, `project_mode`, `_Delivery`, `picture.json`, or their internal field
names. The product has not been publicly released, so existing development
projects and generated packages are regenerated rather than migrated.

### D077 — Project identity is separate from published-domain identity

Every initialized `.rpp` has one stable Project ID and one Project Type. A
Source Project additionally has one Delivery ID, and a Master Project
additionally has one Reference ID. `Delivery Set ID` is removed, and Master
Projects gain the Project ID that the earlier model lacked.

Local project state uses `project_id` and `project_type`. Delivery manifests
identify `sourceProjectId` and `deliveryId`; Reference manifests identify
`masterProjectId` and `referenceId`. Project identity and published-domain
identity remain separate even though the MVP permits only one Delivery or
Reference per project.

After Save As, Continue Existing Project preserves the Project ID, Delivery ID
or Reference ID, object identities, and managed package relationship. Start New
Project assigns a new Project ID and published-domain ID and creates an
independent managed package. The prompt identifies the concrete Source or Master
Project Type.

Lane ID, Clip ID, Reference Item ID, timeline Entry ID, Instance ID, and REAPER
Track GUID remain stable technical identities. They are shown only when useful
for diagnostics or identity resolution.

### D078 — Exceptional actions state the user's action, not implementation jargon

Detected unbaked Track FX or Take FX blocks Delivery Publish by default. The
explicit override is Publish Unprocessed Media, accompanied by confirmation that
the FX will not be included. Publishing a Reference with no detected changes
uses Publish Unchanged Reference Revision and explains that Source Projects will
still need to synchronize and review the new revision.

When a Linked Item contains Take data that cannot be copied automatically, the
actions remain Add New Take and Keep Current Media. A confirmation explains the
unsupported Take data, that the existing Take will be retained, and that the new
Take receives basic settings only. Internal wording such as `advanced state`
does not appear in the action label.

A blocked Publish identifies the possible current publisher and offers Check
Again, Unlock Publishing, or Cancel. Unlock Publishing requires explicit
confirmation that no other user or computer is publishing. Internal stale-lock
terminology is not used as the primary action label.

Identity-reset actions are Treat Selected Reference Tracks as New and Treat
Selected Reference Items as New. Their confirmation explains that new stable
identities will be assigned and Source Projects will see new Reference objects.

### D079 — Revision types and revision-state labels are always qualified

Delivery Revision is the complete Delivery version created by every successful
Delivery Publish. Media Revision is the WAV-content version of one Delivery
Clip and changes only when that content changes. Reference Revision is the
complete Reference version created by Reference Publish. Their counters are
independent and must not be compared across revision types.

Reference state uses Latest Reference Revision, Synchronized Reference Revision,
and Reviewed Reference Revision. Delivery Update uses Target Delivery Revision,
per-Linked-Item Handled Delivery Revision, Accepted Media Revision, and Available
Media Revision. Baseline is the historical Delivery state at the Handled
Delivery Revision, not another revision type.

UI labels use the full qualified name, or compact forms such as `Delivery r12`,
`Reference r8`, and `Media r4` when the qualifier is visible. A bare `r12` is not
used where more than one revision type may appear. Manifest filenames use
zero-padded numbers; ordinary UI labels do not.

### D080 — Public status language describes the condition and next action

Notice is informational, Warning permits an explicitly confirmed continuation,
and Blocked prevents the operation. Reviews invalidated by project or package
changes show Review Out of Date and offer Refresh Review. A newly published base
shows Newer Revision Available.

Public media states are Media File Not Found, Media Unavailable, Cannot Read
Media, Media Content Mismatch, and Unsupported Media Type. Public routing and
identity states use Target Track Missing, Lane Mapped, Lane Unmapped, Duplicate
Clip Identity, Needs Classification, and qualified Project, Delivery, or
Reference Identity Mismatch.

Publishing Is Locked shows the possible publisher, computer, start time, elapsed
time, and package path before offering Check Again, Unlock Publishing, or
Cancel. Technical terms such as stale, orphaned, offline, pointer validation,
schema integers, and lock-age heuristics remain in diagnostics rather than
primary user-facing status labels.

Unsupported newer schemas show ReaProjectLink Update Required. Structurally
invalid data uses Invalid Manifest, Manifest Revision Mismatch, or Invalid
Manifest Path as appropriate, with implementation details available separately.

### D081 — Public terminology and action labels follow one style

The brand is always written `ReaProjectLink`; lowercase `reaprojectlink` is used
only where a lowercase technical name is required. Formal domain objects and
REAPER object types use their canonical capitalization. Source and Master are
qualified as Source Project, Source User, Source Team, Master Project, Master
User, or Master Team rather than used as ambiguous bare nouns.

Register and Unregister start or stop ReaProjectLink management of an existing
REAPER object without creating or deleting it. Add and Create are reserved for
new relationships or objects. Actions begin with verbs, while conditions are
phrased as states.

An action label ends in an ellipsis when it opens a required selection or
confirmation step. Immediate actions omit the ellipsis. Singular and bulk
actions use explicit object counts such as Detach Linked Item, Detach Selected
Linked Items, and Add All as New Takes rather than parenthesized plurals.

Stable IDs are omitted from routine UI. When needed for identity resolution or
diagnostics, labels use the complete object name, values may be shortened, and
full values remain available in Technical Details.

The Source Project UI is organized around Reference Subscription, Delivery
Tracks, and Delivery Publishing. The Master Project UI is organized around
Reference Publishing and Delivery Subscriptions.

### D082 — Retired Linked Items require an explicit Master-side decision

A Delivery Clip that is absent from a later Delivery Revision is Retired. Each
of its Linked Items defaults to Keep Retired Item so Source-side structural
changes never silently delete Master Project work. The Master User may instead
choose Detach Retired Item, which preserves the REAPER Item without its Delivery
identity, or Delete Retired Item.

Delivery Update Review groups Retired Linked Items and Pending Clips as a
structural change. Match Source Structure sets every Retired Linked Item to
Delete and every Pending Clip to Import. Applying any Delete choice requires
confirmation; deletion, detachment, imports, and the rest of the Delivery Update
are committed as one REAPER Undo step.

### D083 — Delivery synchronization replaces a Source-owned snapshot

The pre-release Delivery model is simplified from Clip lineage merging to
Source-owned snapshot replacement. This decision supersedes the Delivery Clip
continuity, Media Revision reuse, per-Clip classification, per-field merge,
new-Take update, Pending/Declined Clip, and Retired Linked Item behavior in
D007, D010, D018–D021, D023, D026–D028, D032, D036–D038, D042, D049, D052–D060,
D072–D075, the Delivery-specific part of D077, D079, and D082. Reference
identity and synchronization are unchanged.

Every Delivery Publish treats every current Item on registered Delivery Tracks
as a newly generated Clip, copies its media into a new Clip directory, and
publishes a complete immutable Delivery Revision. The Source User never decides
whether an Item continues an older Clip. Clip ID and Media Revision remain
technical manifest fields, but a Clip is revision-local and its Media Revision
is always 1.

The Master Project owns Lane Bindings and Track-level mixing state. Items
imported onto a bound Master Track are Source-managed. Synchronizing any
Delivery Revision—including the currently handled Revision—deletes every still
managed Item for that Delivery and imports the complete target snapshot in one
REAPER Undo step. There is no per-Item merge, Take history, decline, or Retired
decision.

Moving a managed Item away from its bound Master Track prompts once for the
user to keep it as local Master content. Confirmation clears its Delivery
ownership while leaving the Item at the chosen location. It is never reattached;
the Source version is restored by synchronizing the desired Delivery Revision.
If the user does not confirm, the Item remains Source-managed and is replaced by
the next synchronization.

### D084 — ReaPack is the distribution channel

ReaProjectLink is distributed as a ReaPack package from this repository's own
`index.xml`. Everything shipped lives under `ReaProjectLink/`, which is the
ReaPack category; the entry script resolves modules relative to its own
directory, so the development checkout and an installed copy share one layout.
A release is a `@version` bump on `master`; the deploy workflow runs
`reapack-index` and commits the updated index.
