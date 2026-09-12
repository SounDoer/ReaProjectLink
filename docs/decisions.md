# Decision log

This file records decisions reached during product discovery. Items under Open
questions are intentionally not yet decisions.

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

Template projects may establish designated delivery/print tracks. Their names and
locations are flexible, but only registered delivery items on these tracks are
eligible for publication.

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

## Open questions

- Exact rules and UI for registering a new Delivery Clip versus publishing a new
  revision of an existing clip.
- How tool-controlled Bounce creates or updates persistent source-side item/take
  containers.
- Which parts of take state are copied when a new mix take is created.
- First-import mapping UI and support for adopting WAVs already present in an
  existing mix project.
- Policies for source position changes when the corresponding mix item has also
  been moved, split, trimmed, slip-edited, or stretched.
- Exact Manifest schema and schema-version migration policy.
- Picture Manifest location and lifecycle.
- Source and mix project locking, stale-lock handling, and NAS failure recovery.
- Whether publish history retains all WAV revisions indefinitely or offers an
  explicit garbage-collection tool.
