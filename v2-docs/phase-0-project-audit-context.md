# Phase 0 – Project Audit Context

## Relevant Architecture

Snaproll V2 keeps the disposable-camera metaphor while adding shared rolls.

High-level stack:

```text
iOS App
↓
SwiftData local database
↓
Repositories
↓
Sync Engine / Polling / Renderer
↓
Supabase Auth + Postgres + Storage + RPC
```

Core domain entities:

```text
Profile
Roll
RollParticipant
Exposure
Invite
```

There is no separate `Photo` table in V2. A filled `Exposure` is the photo record.

Roll types:

```text
PERSONAL
SHARED
```

Shared roll lifecycle:

```text
DRAFT
↓
WAITING_FOR_PARTICIPANTS
↓
SHOOTING
↓
READY_TO_REVEAL
↓
REVEALED
```

Local-first model:

- Capture works offline
- Shared lifecycle actions require cloud connectivity
- Cloud stores durable shared facts
- Device stores shared facts plus local workflow state

Repository boundary:

- Views and ViewModels do not talk directly to Supabase
- Repositories mediate SwiftData, Supabase, Storage, RPCs, and sync

## Audit Focus

For an audit, verify that the codebase and migration plan align with:

- Supabase as the only backend
- SwiftData as the local V2 persistence layer
- RPC-owned business transitions
- Exposure slots as the core sync unit
- Polling instead of Realtime for MVP
- On-device rendering only

## Invariants That Must Not Be Violated

- The roll is the primary entity.
- The creator counts as a participant.
- Shared rolls must preserve anticipation, scarcity, permanence, and low social complexity.
- `Exposure` is the cloud photo unit; do not reintroduce a separate cloud `Photo` table.
- Capture must not depend on network connectivity.
- Clients may upload bytes, but backend RPCs own business state.
- Views and ViewModels must not talk directly to Supabase.
