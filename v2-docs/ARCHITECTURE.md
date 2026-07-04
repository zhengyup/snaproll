# Snaproll V2 – Backend Architecture & Shared Rolls

## 1. Product Architecture Summary

Snaproll V2 introduces shared rolls while preserving the disposable camera metaphor.

Core principles:

* Anticipation over instant viewing
* Scarcity through fixed exposures
* Permanence after reveal
* Shared rolls as moments in time
* Local-first capture
* Cloud-backed shared state
* No social media complexity

V2 architecture:

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

Supabase is the backend for V2. No separate custom backend server is required.

---

# 2. Core Domain Model

## Entities

```text
Profile
Roll
RollParticipant
Exposure
Invite
```

There is no separate `Photo` table in V2.

A filled `Exposure` represents a photo.

## Roll Types

```text
PERSONAL
SHARED
```

Personal rolls behave like V1.

Shared rolls use lobby, participants, invite links, and cloud reveal.

## Creator

The creator counts as a participant.

Example:

```text
4 participants
12 exposures each
= 48 total possible photos
```

---

# 3. Shared Roll Lifecycle

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

## Before Start Roll

Creator may:

* Rename roll
* Change film stock
* Change exposure count
* Invite participants
* Remove participants
* Delete roll

Participants may:

* Join
* Leave

Leaving and removal before Start Roll both hard-delete the participant row.

## Start Roll

When creator presses **Start Roll**:

* Participant list locks
* Film stock locks
* Exposure count locks
* Invite link no longer allows joining
* Exposure slots are pre-created for every participant
* Roll enters `SHOOTING`

Only the roll title remains editable.

## Ready to Reveal

A participant is `FINISHED` only when all their exposures are synced to cloud.

The roll becomes `READY_TO_REVEAL` when all participants are finished.

## Reveal

Only creator can reveal.

Reveal is a cloud event.

```text
All participants FINISHED
↓
Roll READY_TO_REVEAL
↓
Creator presses Reveal Roll
↓
Roll REVEALED
```

## Force Reveal

Force Reveal is an escape hatch.

Hidden under:

```text
⋯
Manage Roll
Force Reveal
```

If force reveal happens:

* Uploaded photos are included
* Empty exposures are lost
* Roll immediately becomes `REVEALED`
* No partial uploaded photos are discarded

---

# 4. Exposure Model

Snaproll uses pre-created exposure slots.

When a shared roll starts:

```text
Roll
 └── Participant
      ├── Exposure 1
      ├── Exposure 2
      └── ...
```

An exposure has:

* Owner participant
* Exposure number
* Optional uploaded image path
* Render seed

A cloud exposure is considered filled if:

```text
storage_path != null
```

There is no cloud `sync_state`.

## Exposure Immutability

Once an exposure has been filled, it cannot be replaced.

```text
EMPTY exposure → can be completed once
FILLED exposure → immutable
```

No retakes. No overwrites.

---

# 5. Supabase Schema

## `profiles`

```sql
profiles
- id uuid primary key references auth.users(id)
- display_name text
- avatar_url text nullable
- created_at timestamptz
```

## `rolls`

```sql
rolls
- id uuid primary key
- creator_id uuid references profiles(id)
- title text
- type text check ('PERSONAL', 'SHARED')
- status text check (
    'DRAFT',
    'WAITING_FOR_PARTICIPANTS',
    'SHOOTING',
    'READY_TO_REVEAL',
    'REVEALED'
  )
- film_stock_id text
- exposures_per_participant int check (exposures_per_participant in (12, 24, 36))
- participant_cap int default 10
- started_at timestamptz nullable
- ready_to_reveal_at timestamptz nullable
- revealed_at timestamptz nullable
- created_at timestamptz
- updated_at timestamptz
```

Roll title is not unique.

## `roll_participants`

```sql
roll_participants
- id uuid primary key
- roll_id uuid references rolls(id) on delete cascade
- user_id uuid references profiles(id)
- status text check ('JOINED', 'SHOOTING', 'FINISHED')
- joined_at timestamptz
- finished_at timestamptz nullable

unique (roll_id, user_id)
```

## `exposures`

```sql
exposures
- id uuid primary key
- roll_id uuid references rolls(id) on delete cascade
- participant_id uuid references roll_participants(id) on delete cascade
- exposure_number int
- storage_path text nullable
- render_seed text not null
- captured_at timestamptz nullable
- uploaded_at timestamptz nullable
- created_at timestamptz

unique (participant_id, exposure_number)
check (exposure_number >= 1)
```

`roll_id` is duplicated intentionally for easier queries.

## `invites`

```sql
invites
- id uuid primary key
- roll_id uuid references rolls(id) on delete cascade
- token text unique not null
- created_by uuid references profiles(id)
- is_active boolean default true
- created_at timestamptz
- revoked_at timestamptz nullable
```

Rules:

* One active invite per roll
* Invite token is random and unguessable
* Invite remains viewable after start, but cannot be used to join

## Indexes

```sql
rolls(creator_id)
roll_participants(user_id)
roll_participants(roll_id)
exposures(roll_id)
exposures(participant_id)
invites(token)
```

---

# 6. Supabase RPC Functions

Business transitions must go through RPC functions.

Clients should not directly mutate lifecycle state.

## Required RPCs

```text
create_roll()
join_roll(invite_token)
leave_roll(roll_id)
start_roll(roll_id)
reveal_roll(roll_id)
force_reveal_roll(roll_id)
regenerate_invite(roll_id)
complete_exposure(exposure_id, storage_path)
```

## RPC Ownership

RPC functions own changes to:

```text
roll.status
roll.started_at
roll.ready_to_reveal_at
roll.revealed_at
participant.status
participant.finished_at
exposure.storage_path
exposure.uploaded_at
invite.is_active
invite.revoked_at
```

## `start_roll()`

Validates:

* User is creator
* Roll is waiting
* Participant count is between 1 and cap
* Film stock and exposure count are valid

Then:

* Locks roll
* Sets participants to `SHOOTING`
* Creates exposure slots
* Deactivates invite joining
* Sets roll status to `SHOOTING`

## `complete_exposure()`

Flow:

```text
Client uploads JPEG to Supabase Storage
↓
Client calls complete_exposure(exposure_id, storage_path)
↓
RPC validates ownership, roll state, exposure emptiness, and expected path
↓
RPC fills exposure
↓
RPC checks participant completion
↓
RPC checks roll completion
↓
Transaction commits
```

This is important.

The client uploads bytes, but backend owns business state.

---

# 7. Storage Architecture

## Bucket

```text
snaproll-originals
```

## Path

```text
rolls/{roll_id}/participants/{participant_id}/{exposure_number}.jpg
```

Example:

```text
rolls/roll_123/participants/participant_456/001.jpg
```

## Format

Cloud canonical format is **JPEG**.

Device may capture HEIC or another native format locally, but the uploaded cloud original is always JPEG.

Reason:

* Predictable renderer input
* Easier future Android support
* Simpler exports
* Simpler testing
* Same backend assumptions across platforms

## Storage Rules

* One file per exposure
* No replacement
* No rendered images uploaded in V2
* No thumbnails in cloud for V2

---

# 8. Rendering Architecture

Rendering happens entirely on-device.

Cloud stores:

```text
original JPEG
roll.film_stock_id
exposure.render_seed
```

Rendered output is derived from:

```text
original JPEG
+ film_stock_id
+ render_seed
+ renderer_version
```

No backend rendering.

No rendering workers.

No rendered files in Supabase Storage.

The device may cache rendered previews locally.

If renderer improves later through Film Lab, historical photos can be re-rendered.

---

# 9. Local SwiftData Schema

Local schema mirrors shared cloud facts and adds local workflow state.

## `LocalRoll`

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

## `LocalParticipant`

```text
- id
- roll_id
- user_id
- display_name
- status
- joined_at
- finished_at
```

## `LocalExposure`

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

## `LocalInvite`

```text
- id
- roll_id
- token
- is_active
- created_at
```

Principle:

```text
Cloud stores durable shared facts.
Device stores shared facts + local workflow state.
```

---

# 10. Sync Engine

Each captured exposure is a durable upload job.

## Local Sync States

```text
EMPTY
LOCAL_ONLY
UPLOADING
METADATA_PENDING
SYNCED
FAILED
```

## Meaning

```text
EMPTY
No photo captured.

LOCAL_ONLY
Photo captured and saved locally. Not uploaded yet.

UPLOADING
JPEG upload to Supabase Storage in progress.

METADATA_PENDING
File exists in Storage, but complete_exposure() has not succeeded.

SYNCED
Storage upload and complete_exposure() both succeeded.

FAILED
Last attempt failed. Retry allowed.
```

## Transitions

```text
EMPTY
→ capture
→ LOCAL_ONLY

LOCAL_ONLY
→ start upload
→ UPLOADING

UPLOADING
→ storage upload succeeds
→ METADATA_PENDING

UPLOADING
→ storage upload fails
→ FAILED

METADATA_PENDING
→ complete_exposure succeeds
→ SYNCED

METADATA_PENDING
→ complete_exposure fails
→ FAILED

FAILED
→ retry
→ LOCAL_ONLY or METADATA_PENDING
```

Retry rule:

```text
If storage_path exists locally, retry complete_exposure().
If storage_path does not exist, retry upload.
```

## Upload Rules

* Capture never waits for upload
* Upload in exposure-number order per participant
* One upload at a time per participant for V2
* Failed uploads retry automatically
* Upload is complete only after Storage upload and `complete_exposure()` both succeed

---

# 11. Local-First Behaviour

## Camera

The camera always works offline.

```text
Capture
↓
Save locally
↓
Queue upload
↓
Continue shooting
```

Network is not required to take photos.

## Shared Actions

Shared lifecycle actions require cloud connectivity.

Not queued:

```text
join_roll
start_roll
reveal_roll
force_reveal_roll
regenerate_invite
```

If offline, show an error and let user retry.

## Reinstall

Uploaded photos:

```text
Recoverable from Supabase
```

Local-only photos:

```text
Lost if app is deleted before upload
```

Acceptable for V2.

---

# 12. Polling Instead of Realtime

V2 uses polling.

No Supabase Realtime for MVP.

## Polling Behaviour

Lobby:

```text
Refresh every 3–5 seconds
```

Shooting / waiting:

```text
Refresh every 10–15 seconds
```

Also refresh:

* On pull-to-refresh
* On app foreground
* After key actions
* After upload completion

Polling updates SwiftData, and SwiftUI observes local state.

Architecture:

```text
Poller
↓
Repository
↓
SwiftData
↓
UI
```

Realtime can be added later without changing the domain model.

---

# 13. RLS / Security Model

Core security rule:

```text
Users can read shared data they belong to.
Users cannot directly mutate lifecycle/business state.
RPC functions perform protected transitions.
```

## Profiles

Read:

```text
Authenticated users can read basic profiles.
```

Update:

```text
User can update own profile only.
```

## Rolls

Read:

```text
Creator and participants can read.
```

Insert:

```text
Authenticated users can create.
```

Update:

```text
Creator can update title.
Lifecycle fields are RPC-owned.
```

Delete:

```text
Creator can delete only before Start.
```

## Roll Participants

Read:

```text
Participants can read participant list for their roll.
```

Insert:

```text
No direct shared-roll insert.
Use join_roll().
```

Delete:

```text
Before Start:
- user can leave
- creator can remove participant

After Start:
- no delete
```

Status updates are RPC-owned.

## Exposures

Read:

```text
Participants can read exposures for their roll.
```

Insert:

```text
No direct insert.
start_roll() creates exposures.
```

Update:

```text
No direct storage_path mutation.
complete_exposure() owns this.
```

## Invites

Read:

```text
Creator can read active invite.
join_roll(token) can resolve token internally.
```

Write:

```text
No direct writes.
regenerate_invite() owns invite changes.
```

## Storage

Upload:

```text
Authenticated user can upload only to their own participant folder while roll is SHOOTING.
```

Read:

```text
Participants can read originals only after roll is REVEALED.
```

Important:

```text
Storage upload alone does not complete an exposure.
complete_exposure() must validate and commit the business state.
```

---

# 14. Repository Architecture

Views and ViewModels should not talk directly to Supabase.

Use repositories.

## Repositories

```text
AuthRepository
RollRepository
ParticipantRepository
ExposureRepository
InviteRepository
SyncRepository
RenderCacheRepository
```

## RollRepository

```text
createPersonalRoll(...)
createSharedRoll(...)
getRoll(id)
observeRoll(id)
updateRollTitle(id, title)
deleteRoll(id)
startRoll(id)
revealRoll(id)
forceRevealRoll(id)
refreshRoll(id)
```

## ParticipantRepository

```text
joinRoll(inviteToken)
leaveRoll(rollId)
removeParticipant(participantId)
observeParticipants(rollId)
```

## ExposureRepository

```text
getNextEmptyExposure(rollId, userId)
captureExposure(exposureId, image)
observeExposures(rollId)
downloadRevealedExposures(rollId)
```

## SyncRepository

```text
enqueueExposureUpload(exposureId)
processPendingUploads()
retryFailedUpload(exposureId)
```

## RenderCacheRepository

```text
getRenderedImage(exposureId)
renderAndCache(exposureId)
invalidateCacheForRendererVersion(version)
```

Principle:

```text
ViewModels talk to repositories.
Repositories talk to SwiftData, Supabase, Storage, RPCs, and sync engine.
Views never talk directly to Supabase.
```

---

# 15. Gallery Behaviour

Shared gallery is grouped by participant.

Example:

```text
You
□□□□□□

Sarah
□□□□□□

Alex
□□□□□□
```

No chronological ordering.

The reveal experience should feel like opening each person’s disposable camera separately.

After reveal:

```text
Fetch roll metadata
↓
Fetch participants
↓
Fetch filled exposures
↓
Download originals
↓
Render locally
↓
Cache previews
↓
Display progressively
```

Do not block gallery until every image is cached.

---

# 16. Deletion Policy

V2 uses hard deletes.

Before Start:

```text
Creator can delete roll.
Rows cascade.
Storage cleanup should run if needed.
```

After Start:

```text
Roll cannot be deleted in V2.
```

Revealed rolls:

```text
Cannot be deleted in V2.
```

This supports permanence.

---

# 17. Implementation Roadmap for Codex

## Phase 1 — Supabase Foundation

Implement:

* Tables
* Enums/check constraints
* Indexes
* Foreign keys
* Basic RLS skeleton
* Storage bucket

Deliverable:

```text
Supabase schema migration
```

## Phase 2 — RPC Functions

Implement:

```text
create_roll
join_roll
leave_roll
start_roll
reveal_roll
force_reveal_roll
regenerate_invite
complete_exposure
```

Include transaction safety and validation.

Deliverable:

```text
RPC SQL migration + tests
```

## Phase 3 — iOS Data Layer

Implement:

* SwiftData local models
* Repository interfaces
* Supabase client wrapper
* AuthRepository
* RollRepository basics

Deliverable:

```text
App can create/fetch rolls through repositories.
```

## Phase 4 — Shared Roll Lobby

Implement:

* Create shared roll
* Invite link display
* Join roll
* Participant list
* Remove/leave before Start
* Polling refresh

Deliverable:

```text
Shared lobby works end-to-end.
```

## Phase 5 — Start Roll + Exposure Creation

Implement:

* start_roll RPC integration
* Exposure slot sync into SwiftData
* Camera entry from shared roll
* Locked roll settings after Start

Deliverable:

```text
Shared roll enters SHOOTING with exposure slots.
```

## Phase 6 — Capture + Sync Engine

Implement:

* Capture into next empty exposure
* Save local original
* Convert upload copy to JPEG
* Upload to Storage
* complete_exposure RPC
* Local sync states
* Retry logic
* Metadata pending recovery

Deliverable:

```text
Photos upload reliably without blocking capture.
```

## Phase 7 — Ready to Reveal + Reveal

Implement:

* Participant completion detection
* Roll polling for READY_TO_REVEAL
* Creator Reveal CTA
* reveal_roll RPC
* Reveal animation handoff

Deliverable:

```text
Shared roll can be revealed.
```

## Phase 8 — Shared Gallery

Implement:

* Fetch revealed exposures
* Download participant originals
* Render locally
* Cache rendered previews
* Group by participant

Deliverable:

```text
Revealed shared gallery works.
```

## Phase 9 — Force Reveal + Edge Cases

Implement:

* Hidden force reveal action
* Partial gallery support
* Failed upload UI
* Retry controls
* Offline messaging

Deliverable:

```text
Exceptional flows are handled safely.
```

## Phase 10 — Polish and Testing

Test:

* Lobby joins/removes
* Start roll transaction
* Upload failure before Storage
* Upload failure after Storage before RPC
* App killed during upload
* Reveal readiness
* Force reveal
* Reinstall recovery for uploaded photos

Deliverable:

```text
V2 beta-ready.
```

---

# 18. Final Architecture Principles

```text
The roll is the primary entity.
The creator controls lifecycle.
Each participant has their own disposable camera.
Exposure is the core sync unit.
Cloud stores shared facts.
Device stores local workflow.
Capture never blocks on network.
Reveal is a cloud event.
Clients upload bytes.
Backend owns business state.
Rendering is on-device.
Storage contains canonical JPEG originals only.
No social features unless they strengthen shared memory.
```
