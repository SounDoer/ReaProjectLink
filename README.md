# ReaDelivery

ReaDelivery is a REAPER-native publish and dependency-update system for
sound-post teams working on shared storage.

It is intended for game-audio cinematic production where dialogue, music, and
sound-design teams work in separate REAPER projects and periodically deliver
rendered audio into a master mixing project. It uses an existing NAS rather than
a cloud service or central project database, and it does not attempt to make
multiple users edit the same REAPER project.

The working principle is:

- source projects keep their own folder structures and working conventions;
- source teams explicitly publish bounced audio as versioned deliveries;
- the mix project reads published manifests and manages all downstream imports;
- updates become new takes on existing mix items;
- the authoritative picture lives in the mix project and is published back to
  source projects as a reviewed picture revision.

## Documentation

- [Product concept](docs/product-concept.md)
- [Architecture](docs/architecture.md)
- [Manifest schema](docs/manifest-schema.md)
- [Decision log](docs/decisions.md)
- [Development](docs/development.md)
- [Manual validation](docs/validation.md)

## Status

The local MVP is implemented in Lua 5.4 ReaScript with ReaImGui. It includes:

- Source and Mix project initialization;
- authoritative Picture publication, Source subscription, synchronization, and
  explicit review;
- Delivery Track registration, complete Publish Review, immutable WAV revisions,
  and atomic manifests;
- Mix-side Source subscription, Lane mapping, first import, new-Take updates,
  per-Instance three-way field resolution, and explicit detach;
- NAS Publish locking, stale-lock inspection, and interrupted-commit recovery.

The current scope assumes new projects initialized through ReaDelivery and does
not infer bindings for existing legacy Mix Items.
