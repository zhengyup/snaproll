# Phase 3 – iOS Data Layer Context

## Roadmap Placement

This document still maps directly to roadmap Phase 3.

## Relevant Architecture

The iOS V2 data layer is:

```text
SwiftData local database
↓
Repositories
↓
Sync Engine / Polling / Renderer
↓
Supabase
```

SwiftData mirrors shared cloud facts and adds local workflow state.

### LocalRoll

```text
- id
- title
- type
- status
- film_stock_id
- exposures_per_participant
- creator_id
- created_at
- started_at
- ready_to_reveal_at
- revealed_at
- last_synced_at
```

### LocalParticipant

```text
- id
- roll_id
- user_id
- display_name
- status
- joined_at
- finished_at
```

### LocalExposure

```text
- id
- roll_id
- participant_id
- exposure_number
- render_seed
- local_original_path nullable
- upload_jpeg_path nullable
- cloud_storage_path nullable
- rendered_cache_path nullable
- sync_state
- captured_at nullable
- uploaded_at nullable
- last_error nullable
- updated_at
```

### LocalInvite

```text
- id
- roll_id
- token
- is_active
- created_at
```

Repository boundary:

```text
AuthRepository
RollRepository
ParticipantRepository
ExposureRepository
InviteRepository
SyncRepository
RenderCacheRepository
```

Session and identity note:

- Session bootstrap is handled in roadmap Phase 5
- Development Authentication is introduced in roadmap Phase 6
- Shared-roll features must still depend only on `AuthRepository`

Principle:

```text
ViewModels talk to repositories.
Repositories talk to SwiftData, Supabase, Storage, RPCs, and sync engine.
Views never talk directly to Supabase.
```

## Invariants That Must Not Be Violated

- Cloud stores durable shared facts; device stores facts plus local workflow state.
- SwiftData models must mirror cloud identifiers exactly.
- Repositories are the only boundary between UI state and backend state.
- Exposure remains the core sync unit.
- Local workflow state such as upload progress must not leak into cloud schema.
- Rendering and render cache concerns stay out of the core cloud model.
