# ReaDelivery

ReaDelivery is a REAPER-native publish and dependency-update system for
sound-post teams working on shared storage.

It is intended for game-audio cinematic production where dialogue, music, and
sound-design teams work in separate REAPER projects and periodically deliver
rendered audio into a master mixing project. It uses an existing NAS rather than
a cloud service or central project database, and it does not attempt to make
multiple users edit the same REAPER project.

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
- [Manifest schema](docs/manifest-schema.md)
- [Decision log](docs/decisions.md)

## Status

The MVP product and architecture baseline is documented. Implementation has not
started; technical choices will be validated through a thin end-to-end
prototype.
