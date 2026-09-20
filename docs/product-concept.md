# Product concept

## Problem

In a game cinematic workflow, dialogue, music, and sound effects are commonly
created in separate REAPER projects. They are combined only when the full
cinematic is ready for mixing.

The current integration approaches have recurring problems:

1. Copying tracks into the mix project brings incompatible or missing plug-in
   dependencies with it.
2. Manually bouncing and re-importing WAV files makes frequent updates difficult
   to track and maintain.
3. Native REAPER subprojects help with single-source-of-truth and proxy updates,
   but do not remove save conflicts and plug-in dependencies.
4. The picture in the mix project is authoritative, but source projects also
   need to discover, review, and adopt picture revisions.

## Product direction

ReaDelivery is not initially a cloud collaboration DAW. It is a local dependency
manager that uses an existing NAS as shared storage.

The system separates three concepts:

- **Working source:** a department's editable `.rpp` project.
- **Published delivery:** bounced WAV revisions and a small machine-readable
  manifest.
- **Mix integration:** the master `.rpp` that subscribes to source deliveries and
  decides when to import or update them.

Saving a source project is not publishing. Only an explicit successful Publish
operation creates a delivery revision visible to mix projects.

## Roles

On first use, each `.rpp` is explicitly initialized in one role for the MVP. A
project does not combine Source and Mix modes.

### Source project

A dialogue, music, or sound-effects project:

- may live anywhere on the NAS;
- keeps the department's preferred working structure and naming;
- uses delivery tracks manually designated through the tool;
- bounces plug-in-dependent work to ordinary audio files;
- explicitly publishes delivery revisions;
- does not write to or target a mix project.

### Mix project

The integration project:

- acts as the dependency-management hub;
- manually adds one or more published source manifests;
- chooses where source delivery lanes are placed in its own track hierarchy;
- imports new delivery clips;
- accepts updates as new takes on existing items;
- owns the authoritative reference-picture track.

## Primary workflow

1. A source project designates managed delivery tracks.
2. A source user creates bounced items using any preferred REAPER workflow and
   places the current effective items on managed delivery tracks.
3. Publish compares those tracks with the previous published snapshot, asks for
   confirmation where a new item cannot be classified safely, and writes the
   accepted state to the local `_Delivery` package.
4. A mix project adds the source's `delivery.json` and performs the first import.
5. The mix project stores stable lane-to-track and clip-to-item bindings.
6. A later source Publish creates new WAV revisions without modifying the mix
   project.
7. The mix project detects the new manifest revision and presents the change.
8. After user confirmation, a changed WAV becomes a new take on the already
   bound mix item or items, including still-linked copies and split instances.
9. Old takes remain until the user explicitly removes them.

## Picture workflow

The picture relationship runs in the opposite direction:

1. The mix project owns one authoritative Master Reference Set containing
   registered Picture Tracks, video Items, Markers, and Regions.
2. A Master Reference change is explicitly published as a picture revision.
3. Source projects detect that revision and ask the user to synchronize it.
4. Synchronization mirrors the Master timeline by default; synchronization and
   review remain distinct states.
5. A source audio Publish records the picture revision against which it was
   reviewed.
6. The mix project warns when a source delivery was produced against an older
   picture revision.

Picture changes are never applied or judged compatible automatically. Equal
duration, start time, and frame rate do not prove that the visual content is
unchanged.

## Non-goals for the first version

- Cloud storage or a hosted collaboration service.
- Simultaneous multi-user editing of one `.rpp`.
- Sharing third-party plug-in instances between departments.
- Automatically conforming audio to a changed picture edit.
- Inferring semantic identity from filenames.
- Directly modifying another user's closed or open `.rpp` file.
- Adopting or reconstructing delivery bindings in existing legacy mix projects.
