# Product concept

## Problem

In a game cinematic workflow, dialogue, music, and sound effects are commonly
created in separate REAPER projects. They are combined only when the full
cinematic is ready for mixing.

The current integration approaches have recurring problems:

1. Copying Tracks into the Master Project brings incompatible or missing plug-in
   dependencies with it.
2. Manually bouncing and re-importing WAV files makes frequent updates difficult
   to track and maintain.
3. Native REAPER subprojects help with single-source-of-truth and proxy updates,
   but do not remove save conflicts and plug-in dependencies.
4. The Reference published by the Master Project is authoritative, but Source
   Projects also need to discover, synchronize, and review its revisions.

## Product direction

ReaProjectLink is not initially a cloud collaboration DAW. It is a local
cross-project coordination and dependency manager that uses an existing NAS as
shared storage.

The system separates three concepts:

- **Working source:** a department's editable `.rpp` project.
- **Published delivery:** bounced WAV revisions and a small machine-readable
  manifest.
- **Master integration:** the Master `.rpp` that subscribes to Source
  Deliveries and decides when to import or update them.

Saving a source project is not publishing. Only an explicit successful Publish
operation creates a Delivery Revision visible to the Master Project.

## Project Types

On first use, each `.rpp` is explicitly initialized with one Project Type for
the MVP. A project does not combine Source and Master types.

### Source Project

A dialogue, music, or sound-effects project:

- may live anywhere on the NAS;
- keeps the department's preferred working structure and naming;
- uses delivery tracks manually designated through the tool;
- bounces plug-in-dependent work to ordinary audio files;
- explicitly publishes Delivery Revisions;
- does not write to or target a Master Project.

### Master Project

The central integration project:

- acts as the dependency-management hub;
- manually adds one or more published Source manifests;
- chooses where Source Delivery Lanes are placed in its own Track hierarchy;
- maps Delivery Lanes to Master Tracks;
- synchronizes each Delivery as a Source-owned Item snapshot;
- publishes the authoritative Reference for its Source Projects.

## Primary workflow

1. A source project designates managed delivery tracks.
2. A source user creates bounced items using any preferred REAPER workflow and
   places the current effective items on managed delivery tracks.
3. Publish writes every current Item as a new Clip in a complete immutable
   Delivery Revision under the local `_ReaProjectLink` package.
4. A Master Project adds the Source's `delivery.json` and performs the first
   import.
5. The Master Project stores stable Lane Bindings; imported Items remain
   Source-managed while they stay on their mapped Master Tracks.
6. A later Source Publish creates another complete snapshot without modifying the Master
   project.
7. The Master Project synchronizes by replacing the previous managed Items with
   the complete selected Delivery Revision while preserving Master Track state.
8. To keep or edit an Item independently, the user moves it away from its
   mapped Track and confirms that it should become local Master content.
9. Synchronizing the current Revision can restore the Source snapshot at any time.

## Reference workflow

The Reference relationship runs in the opposite direction:

1. The Master Project owns one authoritative Reference containing registered
   Reference Tracks, media Items, Markers, and Regions.
2. A Reference change is explicitly published as a Reference Revision.
3. Source Projects detect that revision and ask the user to synchronize it.
4. Synchronization mirrors the Master timeline by default; synchronization and
   review remain distinct states.
5. A Delivery Publish records the Reference Revision against which it was
   reviewed.
6. The Master Project warns when a Source Delivery was produced against an older
   Reference Revision.

Reference changes are never applied or judged compatible automatically. Equal
duration, start time, and frame rate do not prove that the visual content is
unchanged.

## Non-goals for the first version

- Cloud storage or a hosted collaboration service.
- Simultaneous multi-user editing of one `.rpp`.
- Sharing third-party plug-in instances between departments.
- Automatically conforming audio to a changed visual edit.
- Inferring semantic identity from filenames.
- Directly modifying another user's closed or open `.rpp` file.
- Adopting or reconstructing Delivery Bindings in existing legacy Master
  Projects.
