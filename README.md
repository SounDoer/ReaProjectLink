# ReaDelivery

ReaDelivery is a local, NAS-based delivery and dependency-management workflow for
REAPER projects.

It is intended for game-audio cinematic production where dialogue, music, and
sound-design teams work in separate REAPER projects and periodically deliver
rendered audio into a master mixing project.

The project is currently in the design phase. The working principle is:

- source projects keep their own folder structures and working conventions;
- source teams explicitly publish bounced audio as versioned deliveries;
- the mix project reads published manifests and manages all downstream imports;
- updates become new takes on existing mix items;
- the authoritative picture lives in the mix project and is published back to
  source projects as a reviewed picture revision.

## Documentation

- [Product concept](docs/product-concept.md)
- [Architecture](docs/architecture.md)
- [Decision log](docs/decisions.md)

## Status

No implementation has been selected yet. The next design topic is the exact
source-side publish behavior for new items and new revisions on managed delivery
tracks.
