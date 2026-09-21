# ReaProjectLink

ReaProjectLink provides Source-Master project coordination for REAPER on shared
storage.

It is intended for game-audio cinematic production where dialogue, music, and
sound-design teams work in separate REAPER projects and periodically deliver
rendered audio into a Master Project. It uses an existing NAS rather than
a cloud service or central project database, and it does not attempt to make
multiple users edit the same REAPER project.

The working principle is:

- Source Projects keep their own folder structures and working conventions;
- Source Teams explicitly publish bounced audio as versioned Deliveries;
- the Master Project subscribes to Deliveries and manages downstream imports;
- synchronization replaces Source-managed Items with a complete Delivery snapshot;
- the Master Project publishes the shared Reference back to Source Projects.

## Documentation

- [Product concept](docs/product-concept.md)
- [Architecture](docs/architecture.md)
- [Manifest schema](docs/manifest-schema.md)
- [Decision log](docs/decisions.md)
- [Development](docs/development.md)
- [Manual validation](docs/validation.md)

## Status

The local MVP is implemented in Lua 5.4 ReaScript with ReaImGui. It includes:

- Source Project and Master Project initialization;
- multi-track Reference publication with registered video Items, Markers,
  Regions, an optional Reference Start Marker, timeline mirroring, and explicit
  review;
- Delivery Track registration, complete Publish Review, immutable WAV revisions,
  and atomic manifests;
- Master-side Delivery Subscription, Lane Mapping, first import, complete
  snapshot synchronization, and move-to-local confirmation;
- NAS Publish locking, explicit Unlock Publishing, and interrupted-commit
  recovery.

The current scope assumes new projects initialized through ReaProjectLink and does
not infer Links or Lane Bindings for existing unregistered Items.

Runtime requirements are REAPER 7.74 or newer and a ReaImGui 0.9-compatible
release or newer.
