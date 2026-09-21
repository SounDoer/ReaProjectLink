# Terminology inventory

This document began as the terminology inventory used before ReaProjectLink's
public naming was finalized. The confirmed baseline below is current. The later
inventory sections are retained as a historical audit and are not current
workflow documentation.

Confirmed product decisions remain authoritative in `decisions.md`.

## Confirmed terminology baseline

The following terminology was confirmed after this inventory was created. It
supersedes the conflicting current terms documented in later sections; those
sections remain as an implementation inventory until the rename is complete.

| Concept | Confirmed term |
| --- | --- |
| Product | ReaProjectLink |
| Product classification | Source-Master project coordination for REAPER |
| Project classification field | Project Type |
| Upstream project type | Source Project |
| Central project type | Master Project |
| Source-to-Master domain | Delivery |
| Master-to-Source domain | Reference |
| Complete audio publication version | Delivery Revision |
| Master publication version | Reference Revision |
| Source materialized Reference state | Synchronized Revision |
| Source user-confirmed Reference state | Reviewed Revision |
| Optional relative-alignment anchor | Reference Start Marker |
| Persistent Master relationship to a Source Delivery | Delivery Subscription |
| In-review Lane routing choice | Lane Mapping |
| Persisted Lane-to-Track route | Lane Binding |
| Source-managed downstream object | Synchronized Item |
| Master-owned Item formerly managed by a Delivery | Local Item |

The supported topology remains single-level and centralized: multiple Source
Projects publish Deliveries to one Master Project, and that Master Project
publishes the Reference back to its Source Projects. Source Project and Master
Project are mutually exclusive Project Types.

The confirmed public Audio Delivery hierarchy is:

```text
Source Project
  -> Delivery
    -> Delivery Revision
    -> Delivery Lane
      -> Delivery Clip (revision-local)
        -> Media Revision 1
```

A registered Source REAPER Track is a Delivery Track whose stable published
route is a Delivery Lane. Every Publish creates new revision-local Delivery
Clips. In the Master Project, imported Clips become Synchronized Items owned by
the Source snapshot. Delivery Set is not public terminology; per-Item Instance
identity is no longer part of the Delivery workflow.

The confirmed relationship vocabulary is:

- A Delivery Subscription relates a Master Project to a Source Delivery.
- A Lane Mapping is a user choice made during review.
- A Lane Binding is the persisted Delivery Lane to Master Track route.
- Lane Mapping uses Create New Track, Use Existing Track, and Leave Unmapped.
- Moving a Synchronized Item out of its mapped Master Track offers Keep as Local.
- Synchronize Delivery replaces all remaining Synchronized Items with the
  complete target Delivery Revision.

Confirmed Review names are Delivery Publish Review, Reference Publish Review,
Delivery Import Review, Delivery Update Review, and Reference Update Review.
Delivery Publish Review lists current Items as Included or Blocked and has no
Clip-lineage decisions. Delivery Update Review shows snapshot replacement
counts and Lane Mapping only.

Unregister stops managing a registered object. Remove Subscription removes the
relationship while retaining project content. Keep as Local clears Delivery
ownership from an Item that the user moved out of its mapped Master Track.

Publish, Subscribe, Import, Update, Synchronize, Review, and Apply also have
distinct workflow meanings. Publish creates an external revision; Subscribe
creates a persistent relationship; Import creates local Delivery objects;
Synchronize Delivery replaces the Source-managed snapshot; Synchronize Reference
materializes a Reference Revision; Review validates a complete operation or
records explicit Reference review.

The pre-release implementation will receive a complete rename with no legacy
aliases. `_ReaProjectLink` replaces `_Delivery`; Source packages use
`delivery.json` and `history/delivery-NNNN.json`; Master packages use
`reference.json` and `history/reference-NNNN.json`. Project extension state,
`P_EXT` keys, manifest fields, Lua modules, scripts, tests, and UI names are
renamed together. Existing development projects and packages are regenerated.

Every initialized `.rpp` has a Project ID and Project Type. A Source Project
also has a Delivery ID; a Master Project also has a Reference ID. Delivery Set
ID is removed. Local state uses `project_id`; manifests qualify it as
`sourceProjectId` or `masterProjectId`. Save As offers Continue Existing Project
or Start New Project.

Exceptional actions use user goals rather than internal jargon: Publish
Unprocessed Media, Publish Unchanged Reference Revision, Keep as Local, Unlock
Publishing, Treat Selected Reference Tracks as New, and
Treat Selected Reference Items as New. Detailed risks belong in contextual
confirmation text.

Delivery Revision and Reference Revision are the two evolving public revision
types. Media Revision remains a technical manifest field fixed at 1 for each
revision-local Clip. Reference state uses Latest, Synchronized, and Reviewed
Reference Revision. Delivery synchronization uses Target and Handled Delivery
Revision.

Public severity levels are Notice, Warning, and Blocked. User-facing conditions
include Review Out of Date, Newer Revision Available, Media File Not Found,
Media Unavailable, Cannot Read Media, Media Content Mismatch, Target Track
Missing and qualified Identity Mismatch. Stale,
orphaned, offline, pointer, schema-integer, and lock-age terminology remains in
technical diagnostics.

The brand is always ReaProjectLink. Formal domain objects use canonical Title
Case, Source and Master are qualified by object or actor type, Register and
Unregister manage existing REAPER objects, and action labels begin with verbs.
Ellipses denote required follow-up input or confirmation. Bulk actions use
explicit plural wording, and stable IDs stay out of routine UI.

Reference replaces Picture, Master Reference, and Master Reference Set as the
public domain term. The Source-facing states are Latest Revision, Synchronized
Revision, and Reviewed Revision. FFOP is not a product role: users may optionally
assign any registered Marker as the Reference Start Marker, and project zero is
the default when none is assigned.

## Product and roles

| Current term | Current meaning | Audience |
| --- | --- | --- |
| ReaDelivery | Product name. | Public |
| Source Project | A REAPER project that prepares and publishes audio deliveries. | Public and development |
| Mix Project | A REAPER project that subscribes to deliveries and owns the final integration. | Public and development |
| Source user / source team | An upstream user or department, such as Dialogue, Music, or Sound Effects. | Product documentation |
| Mix user / mixer | The downstream user responsible for integration and mixing. | Product documentation |
| Source mode / Mix mode | The mutually exclusive ReaDelivery mode assigned to a project. | UI and development |
| project role | Another expression currently used for a project's Source or Mix classification. | Product documentation |
| Working Source | Content that is still being prepared and has not crossed the Publish boundary. | Product concept |
| Published Delivery | Content made available through a successful Publish. | Product concept |
| Mix Integration | Importing, routing, reviewing, and updating published deliveries in a Mix Project. | Product concept |
| Dialogue / Music / Sound Effects | Example upstream departments or content categories. | Product documentation |

Resolved by D069: the public classification is Project Type, with Source Project
and Master Project as its mutually exclusive values.

## Audio Delivery domain

The current object hierarchy is:

```text
Source Project
  -> Delivery Set
    -> Delivery Lane
      -> Delivery Clip
        -> Media Revision
```

The principal downstream relationships are:

```text
Delivery Lane -> Mix Track
Delivery Clip -> one or more Mix Item Instances
```

| Current term | Current meaning | Audience |
| --- | --- | --- |
| Delivery | General name for publishable and subscribable audio delivery content. | Public |
| Delivery Set | The logical delivery collection published by one Source Project. | Primarily development |
| Delivery Track | A REAPER Track explicitly registered as part of the delivery surface. | Public |
| Delivery Surface | The complete current set of registered Delivery Tracks and their eligible Items. | Product and development |
| Delivery Lane | A stable logical route corresponding to a registered Delivery Track. | Public and development |
| Delivery Clip | A stable logical unit of delivered audio across Publish revisions. | Public and development |
| Media Revision | A specific WAV-content revision of a Delivery Clip. | Public and development |
| Mix Track | A REAPER Track used as the destination for a Delivery Lane. | Public |
| Mix Item Instance | A linked downstream occurrence of a Delivery Clip in a Mix Project. | Public and development |
| Instance ID | Stable local identity of a Mix Item Instance. | Development |
| Source Project ID | Stable logical identity of a Source Project. | Development |
| Delivery Set ID | Stable identity of a Delivery Set. | Development |
| Lane ID | Stable identity of a Delivery Lane. | Development |
| Clip ID | Stable identity of a Delivery Clip. | Development |

The intended distinctions are:

- A Track and an Item are REAPER objects.
- A Lane and a Clip are ReaDelivery domain objects.
- An Instance is a downstream Item linked to a Clip. A Clip can have multiple
  Instances after copying or splitting.

## Publication, revisions, and storage

| Current term | Current meaning |
| --- | --- |
| Publish | Save durable identity and create a complete externally visible delivery revision. |
| Publish Revision | The set-level revision created by every successful audio Publish. |
| Published Revision | An alternate expression currently used for Publish Revision. |
| Delivery Revision | Another expression currently used for Publish Revision. |
| Media Revision | The WAV-content revision of one Delivery Clip. |
| latest revision | The latest Publish Revision referenced by the stable manifest. |
| historical snapshot | An immutable manifest for one completed revision. |
| full snapshot | A revision manifest that describes the entire current Delivery Set rather than a delta. |
| Delivery Manifest | Structured metadata describing an audio delivery snapshot. |
| `delivery.json` | The stable entry point selected by a subscribing Mix Project. |
| managed delivery package | The ReaDelivery-managed `_Delivery` directory tree. |
| managed WAV | An immutable WAV copied into managed storage by Publish. |
| Source Package Root | The root of one Source Project's managed delivery package. |
| staging | Temporary transaction storage used before a Publish becomes visible. |
| stable pointer | A small manifest that points to the latest immutable snapshot. |
| content hash / SHA-256 | A hash used to identify or validate media content. |
| Publish Lock | A short-lived lock that serializes Publish transactions. |
| observed stale lock | A lock reported as potentially abandoned but never removed automatically. |

Resolved by D072: the public term is Delivery Revision.

## Master Reference and Picture

| Current term | Current meaning |
| --- | --- |
| Picture | The established synchronization-domain term used by manifests, subscriptions, and parts of the UI. |
| Master Reference | The newer name for the complete authoritative reference surface. |
| Master Reference Set | One complete published set of reference Tracks, media Items, Markers, and Regions. |
| Master Reference surface | The complete registered reference content in the Mix Project. |
| Picture Track | A registered REAPER Track containing authoritative reference media. |
| Picture Item | A video or reference-media Item on a Picture Track. |
| Picture ID | Stable identity used by the compatibility entry point and subscriptions. |
| Picture Revision | A published revision of the Master Reference domain. |
| Picture Manifest | The manifest exposed through `picture.json`. |
| Master Reference Manifest | A newer expression for the same class of manifest. |
| Picture History | Immutable historical Picture manifests under `picture-history`. |
| Picture Subscription | A Source Project's persistent relationship to the authoritative reference package. |
| authoritative Picture | The reference content controlled by the Mix Project. |
| synchronized revision | The Picture Revision currently materialized in a Source Project. |
| reviewed revision | The synchronized Picture Revision explicitly reviewed by a Source user. |
| Reference Start | The alignment anchor used by Relative Reference mode. |
| Master Reference Start | The semantic reference start, provided by FFOP when assigned. |
| Picture Start | A withdrawn early-design term still present in some internal names. |
| FFOP | First Frame of Picture, an optional semantic role assigned to one registered Marker. |
| Master Timeline | The registered Markers and Regions published with the Master Reference. |
| Mirror Master Timeline | Alignment mode that adopts the Master project's absolute timeline. |
| Relative Reference | Alignment mode that keeps a local timeline and aligns relative to Reference Start. |
| timeline rebase | An explicitly confirmed uniform shift of the complete Source project timeline. |

Resolved by D070: the public domain term is Reference. Picture and Master
Reference remain in this inventory only because the implementation has not yet
been renamed.

## Subscription, mapping, binding, and linking

| Current term | Current meaning |
| --- | --- |
| Source Subscription | A Mix Project's persistent relationship to one Source delivery package. |
| Add Source `delivery.json` | Create a Source Subscription by selecting its stable manifest. |
| Lane Mapping | A user's routing choice during import or update review. |
| Lane Binding | The persisted Delivery Lane to Mix Track relationship. |
| Clip-to-Item Binding | The identity relationship between a Delivery Clip and a Mix Item Instance. |
| Create New Track | Create a new Mix Track as a Lane destination. |
| Use / Map to Existing Track | Select an existing Mix Track as a Lane destination. |
| Skip for Now | Leave a Lane without a Track binding. |
| bound Lane | A Lane with a persisted Mix Track destination. |
| unmapped Lane | A Lane with no confirmed Mix Track destination. |
| orphaned binding | A Lane binding whose target Track no longer exists. |
| rebind | Select a replacement target Track for a Lane. |
| Folder Track | An optional parent Track used to organize imported material. |
| detach | Remove ReaDelivery identity while retaining the REAPER object. |
| linked Instance | A Mix Item that remains associated with a Delivery Clip. |
| declined Clip | A Clip explicitly rejected by the Mix user. |
| pending Clip | A Clip that has not yet been represented or declined. |
| retired Clip | A Clip absent from the newest Source snapshot but retained downstream. |

The intended distinctions are:

- A Subscription relates a project to a package.
- A Mapping is a user choice under review.
- A Binding is the persisted routing or identity relationship.
- A Link associates a Clip with a concrete downstream Instance.

## Workflow actions

### Source Project actions

- Initialize Source Project
- Register Delivery Track
- Remove Delivery Track
- Open Publish Review
- Refresh Publish Review
- Save & Publish
- Create New Clip
- Keep This Clip ID
- Link as Revision of...
- Clear Decision
- Continue Logical Source
- Start New Source
- Publish Anyway

### Master Reference and Picture actions

- Register Picture Track
- Unregister Picture Track
- Register Marker / Region
- Unregister Marker / Region
- Set FFOP
- Save & Publish Picture
- Make Selected Picture Items New
- Detach Selected Picture Items
- Select `picture.json`
- Check Picture Update
- Synchronize Picture
- Mark Picture Reviewed

### Mix Project actions

- Initialize Mix Project
- Add Source `delivery.json`
- First Import Review
- Confirm Import
- Check Update
- Update Review
- Load Revision
- Apply Update
- Apply Lane Mapping
- Accept as New Take
- Replace Anyway
- Use Source
- Keep Mix
- Skip This Instance
- Detach Selected Instance
- Remove Subscription
- Remove Observed Stale Lock

`Publish Anyway` currently describes two different overrides: publishing audio
with detected unbaked FX, and publishing an unchanged Master Reference. These
actions need context-specific public labels.

## Review, difference, and state vocabulary

### Publish Review states

- Added
- Audio Changed
- Placement Changed
- Metadata Changed
- Unchanged
- Retired
- Needs Decision
- Blocked

### Source Update comparison states and decisions

- Source-only change
- Mix-only change
- Same change
- Conflict
- Unchanged
- Use Source
- Keep Mix

### General states

- registered / unregistered
- published / unpublished
- linked / detached
- mapped / unmapped
- synchronized / unsynchronized
- reviewed / unreviewed
- available / unavailable
- missing / unreadable / offline
- pending
- skipped
- declined
- retired
- orphaned
- stale
- blocked
- warning
- duplicate identity
- ambiguous identity

### Overloaded terms

| Term | Current distinct meanings |
| --- | --- |
| Review | A Publish/Import/Update planning screen, and the semantic confirmation that a Picture was reviewed. |
| Revision | Publish Revision, Media Revision, Picture Revision, accepted revision, and handled revision. |
| Skip | Leave a Lane unmapped, durably decline a Clip, or defer media on one Instance. |
| Source | Source Project, upstream state, a Take's media source, or the `Use Source` decision. |
| Update | A Source Delivery update, Picture update, or per-Instance media/state update. |
| Remove | Unregister an object, remove a Subscription, or retire content without necessarily deleting it. |
| Master | Master Reference, a master mix, or potentially the REAPER Master Track. |

## REAPER-native vocabulary

ReaDelivery should preserve REAPER's native terminology and capitalization for:

- Project
- Project Tab
- Track
- Folder Track
- Media Item / Item
- Take
- Active Take
- Marker
- Region
- Track FX
- Take FX
- GUID
- ReaScript
- ReaImGui
- Undo
- Save As

## Development-only vocabulary

The following terms and identifiers normally do not need to appear in the
general user interface:

- schema / `schemaVersion`
- manifest pointer / snapshot
- project extension state / `ProjExtState`
- Track and Item `P_EXT` fields
- runtime project token
- project state change count
- review model / plan / assignments / decisions
- package writer / picture writer
- atomic Publish
- immutable snapshot
- `sourceProjectId`
- `deliverySetId`
- `publishRevision`
- `laneId`
- `clipId`
- `instanceId`
- `mediaRevision`
- `pictureId`
- `pictureRevision`
- `reviewedRevision`
- `acceptedPublishRevision`
- `declinedClips`
- `mirror` / `relative`
- `new` / `link` / `keep` / `create` / `existing` / `skip`
- `keep_mix` / `use_source` / `accept_new_take`

## Original naming issues

Items marked resolved below remain useful as a migration checklist.

1. Picture versus Master Reference versus Master Reference Set. Resolved:
   Reference.
2. Project role versus project mode. Resolved: Project Type.
3. Publish Revision versus Published Revision versus Delivery Revision.
   Resolved: Delivery Revision.
4. Picture Revision versus Master Reference Revision. Resolved: Reference
   Revision.
5. Delivery Track versus Delivery Lane.
6. Delivery Clip versus REAPER Item.
7. Mix Item Instance versus Instance versus linked Item. Resolved for public UI:
   Linked Item.
8. Subscription versus Mapping versus Binding versus Link. Resolved by D073.
9. The three meanings of Skip. Partly resolved by Leave Unmapped, Decline Clip,
   and Reconsider Clip; per-Item media update wording remains to review.
10. Retired versus Removed versus Deleted.
11. Workflow Review versus semantic reviewed state.
12. The different levels described as a Revision.
13. The different meanings of Source.
14. Master Reference versus master mix and the REAPER Master Track. Resolved:
    Reference; Master Project remains fully qualified.
15. Withdrawn Picture Start wording versus current Reference Start behavior.
    Resolved: optional Reference Start Marker with project-zero fallback.
16. The two unrelated Publish Anyway overrides.
17. Make New versus Reset Identity.
18. Source Update versus Picture Update.
19. Whether Delivery Set should ever be public terminology.

## Proposed review order

1. Product and roles.
2. Picture and Master Reference.
3. Audio Delivery object hierarchy.
4. Revision levels.
5. Subscription, Mapping, Binding, and Link.
6. Workflow actions and states.
7. UI copy, documentation, schemas, and code identifiers.
