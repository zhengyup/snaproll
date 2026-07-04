# Phase 0 Audit Report

## Scope

This audit reviews the current V1 Snaproll iOS codebase against the V2 architecture defined in:

- `v2-docs/ARCHITECTURE.md`
- `v2-docs/phase-0-project-audit-context.md`

This phase does **not** implement V2 features. The goal is to identify what can be preserved, what must be reshaped, and what foundational work is missing before V2 begins.

---

## Executive Summary

The existing V1 app is a solid single-device MVP with clear separation between:

- SwiftUI views
- flow-oriented view models
- local services for camera, storage, rendering, export, and integrity repair

The strongest parts of V1 are:

- camera isolation inside `CameraService`
- on-device rendering inside `PhotoRenderService`
- local JPEG file storage inside `PhotoStorageService`
- a user flow that already treats capture as hidden until reveal

The biggest architectural mismatch with V2 is the data model and persistence layer.

V1 is built around:

- local JSON persistence
- `Roll` + `Photo`
- single-user local state ownership

V2 requires:

- SwiftData-backed local-first persistence
- Supabase-backed authoritative business state
- `Exposure` as the core sync unit
- explicit shared roll lifecycle and RPC-owned transitions
- repository boundaries between UI and backend/data concerns

In short:

- the capture/rendering foundations are worth preserving
- the local storage/domain model must be refactored substantially
- the V2 backend-facing data layer does not exist yet

---

## Current V1 Architecture Snapshot

### App Entry

- `ios/snaproll/snaproll/App/SnaprollApp.swift`
- App launches directly into `HomeView`
- No dependency container or app composition root yet

### Views

Current feature views are mostly organized by screen:

- `HomeView`
- `CreateRollView`
- `RollView`
- `CameraView`
- `RevealView`
- `GalleryView`

These views are presentation-focused, but several screens still instantiate their own concrete view models and services indirectly through default initializers.

### View Models

Flow orchestration currently lives in:

- `HomeViewModel`
- `CreateRollViewModel`
- `CameraViewModel`
- `RevealViewModel`
- `RollActionsViewModel`

These are useful orchestration layers, but they depend directly on concrete services rather than repository protocols.

### Models

Current V1 domain models include:

- `Roll`
- `Photo`
- `FilmStock`
- `Member`

Observations:

- `Roll` is a local device-oriented model with `exposuresUsed` and a simple 3-state lifecycle: `inProgress`, `completed`, `revealed`
- `Photo` is a local metadata record pointing to an image path in the sandbox
- `FilmStock` is already a good fit for future reuse
- `Member` exists, but V2 needs a more explicit participant model aligned with shared-roll ownership and membership

### Services

The current service layer is the most reusable part of V1:

- `CameraService`
- `PhotoStorageService`
- `PhotoRenderService`
- `ExportService`
- `LocalStorageService`
- `StorageIntegrityService`
- `HardwareShutterService`

Observations:

- AVFoundation is correctly isolated from SwiftUI in `CameraService`
- local file writing and JPEG management are correctly isolated in `PhotoStorageService`
- film rendering is already on-device and modular in `PhotoRenderService`
- export logic is separated into `ExportService`
- persistence is still JSON-file based through `LocalStorageService`

### Persistence

V1 currently uses two persistence mechanisms:

1. JSON files for structured metadata
   - `rolls.json`
   - `photos.json`

2. JPEG files on disk for image bytes
   - Application Support
   - `Snaproll/Rolls/<rollID>/<photoID>.jpg`

This is good enough for V1, but it conflicts with the V2 requirement that SwiftData becomes the local-first structured source of truth.

---

## V1 Flow Audit

### Roll Flow

Current flow:

- `HomeView` owns the top-level roll list
- `HomeViewModel` loads rolls from local JSON storage
- `CreateRollView` collects name, film, shot limit
- `HomeViewModel.createRoll(...)` inserts a new `Roll` and persists it
- `RollView` shows details for a single roll and routes either to camera or reveal

What is good:

- flow is simple and understandable
- navigation is already centered on the roll as the primary product object

What blocks V2:

- `Roll` does not model creator, participants, type, lobby state, or explicit server-owned lifecycle
- `Roll` is mutated locally as the authoritative object
- no concept of RPC-controlled transitions such as start, join, reveal, or participant lock

### Camera / Capture Flow

Current flow:

- `RollView` pushes `CameraView`
- `CameraViewModel` asks `CameraService` for permission/session/capture
- `CameraService` returns raw image bytes
- `CameraViewModel.persistCapture(...)`:
  - saves JPEG bytes through `PhotoStorageService`
  - creates local `Photo` metadata
  - updates local `Roll.exposuresUsed`
  - writes both back through `LocalStorageService`

What is good:

- capture service is cleanly isolated
- image bytes are stored separately from metadata
- hidden-film behavior is already respected
- capture remains local-first and immediate

What blocks V2:

- capture creates a `Photo`, but V2 requires a pre-created `Exposure` slot model
- roll progression is locally owned instead of RPC-owned
- there is no upload state machine
- there is no sync queue, no polling, and no mapping between local capture state and server state

### Reveal / Gallery Flow

Current flow:

- when a roll is full, `RollView` routes to `RevealView`
- `RevealViewModel` loads all `Photo` records for the roll
- each photo is loaded from disk and rendered on-device using `PhotoRenderService`
- revealing marks the roll as `.revealed` in local storage
- `GalleryView` shows a contact sheet and single-photo view

What is good:

- reveal is distinct from capture
- rendering stays on-device
- original files are preserved and rendered copies are generated only for viewing/export

What blocks V2:

- reveal state is local and immediate, but V2 requires reveal to be a cloud event
- no participant grouping for shared gallery
- no per-exposure ownership model
- no cloud readiness gate for whether all required uploads exist

### Rendering Flow

Current flow:

- original image bytes are loaded from local storage
- `PhotoRenderService` applies base film response plus stock-specific adjustments
- rendered images are cached in-memory
- exports preserve the rendered version rather than the original

What is good:

- this aligns strongly with the V2 invariant that rendering remains on-device
- film rendering is already service-isolated and easy to preserve

What needs future adjustment:

- rendering inputs will need to move from `Photo` metadata to `Exposure`
- cache keys and invalidation may later need to include exposure identity, renderer version, and possibly roll film selection/versioning

---

## Existing V1 Components That Should Be Preserved

### 1. `CameraService`

Preserve the service boundary and AVFoundation isolation.

Why:

- matches V2 separation of concerns
- keeps views/view models free from AVFoundation details
- already supports permission, session lifecycle, capture, and flash behavior

### 2. `PhotoStorageService`

Preserve the responsibility split for local image byte storage.

Why:

- V2 still needs local-first image storage before remote sync completes
- JPEG handling and file path normalization already exist
- this can evolve into the local original-image store for exposures

### 3. `PhotoRenderService`

Preserve the rendering architecture.

Why:

- V2 explicitly keeps rendering on-device
- the current service is already modular and cache-aware
- it should remain separate from gallery and storage concerns

### 4. View-model orchestration pattern

Preserve the idea that flows are coordinated by view models rather than raw views.

Why:

- this is a good fit for V2 as long as dependencies are inverted behind repositories

### 5. Hidden-film product behavior

Preserve the current behavioral rule that captured photos are not shown during shooting.

Why:

- this is a core product invariant in both V1 and V2

---

## Existing Components That Need Refactoring For V2

### 1. `Roll`

Current issue:

- V1 `Roll` is too small and too local

Needed refactor:

- evolve to V2 roll fields and lifecycle
- separate local editable properties from server-owned state
- add roll type, creator, participant metadata, and explicit status transitions

### 2. `Photo`

Current issue:

- `Photo` is the wrong core abstraction for V2

Needed refactor:

- replace or migrate to `Exposure`
- treat each exposure as the canonical unit for capture, upload, sync, readiness, and reveal

### 3. `LocalStorageService`

Current issue:

- JSON file persistence is the current structured store

Needed refactor:

- replace with SwiftData-backed repositories
- possibly retain as a migration/import helper only during transition

### 4. `ExportService`

Current issue:

- depends directly on `Roll`, `Photo`, and local JSON-driven querying

Needed refactor:

- switch to repository-driven loading of revealed exposures and rendered assets

### 5. `StorageIntegrityService`

Current issue:

- designed around V1 JSON plus file-store reconciliation

Needed refactor:

- either retire it once SwiftData + sync metadata exist
- or narrow it into a migration/integrity utility that understands exposure records instead of photo metadata

### 6. View model dependency wiring

Current issue:

- view models instantiate concrete services via default initializers

Needed refactor:

- introduce injected repositories/use cases from an app composition root

---

## Existing Components That Conflict With The V2 Architecture

### 1. JSON as the primary structured datastore

Conflict:

- V2 requires SwiftData local-first persistence

### 2. `Photo` as the primary captured-media record

Conflict:

- V2 requires `Exposure` as the sync and business unit

### 3. Locally owned roll lifecycle

Conflict:

- V2 requires roll lifecycle transitions to be explicit and RPC-owned

### 4. No repository layer

Conflict:

- V2 architecture expects repositories between UI and data/backend concerns

### 5. No backend/auth/profile model

Conflict:

- V2 is Supabase-backed and requires authenticated users, profiles, invites, and participants

### 6. No sync engine or polling model

Conflict:

- V2 requires upload + metadata sync + polling for server state refresh

### 7. Delete behavior for rolls

Conflict:

- V1 freely deletes rolls from the home list
- V2 architecture states no delete after start or reveal

This does not need to change in Phase 0, but it must be revisited once V2 lifecycle rules are introduced.

---

## Missing Foundations Required Before V2 Implementation

### 1. SwiftData local schema

Missing:

- SwiftData models for `Profile`, `Roll`, `RollParticipant`, `Exposure`, `Invite`
- local sync metadata fields
- migration plan from existing JSON/photo metadata if V1 data preservation is desired

### 2. Repository interfaces

Missing:

- `AuthRepository`
- `RollRepository`
- `ParticipantRepository`
- `ExposureRepository`
- `InviteRepository`
- `SyncRepository`
- `RenderCacheRepository`

### 3. Supabase integration boundary

Missing:

- auth/session management
- RPC client layer
- storage upload/download boundary
- backend DTO mapping

### 4. Exposure state machine

Missing:

- explicit local state for empty/filled/uploading/synced/failed exposure slots

### 5. Sync engine and polling

Missing:

- queued upload flow
- metadata completion flow
- polling refresh for shared roll state

### 6. Shared roll lobby foundations

Missing:

- participant roster
- invite/join flow
- start-roll lock semantics

### 7. App composition root

Missing:

- centralized dependency wiring for repositories/services/view models

This will become important once local and remote data sources multiply.

---

## Suggested Phase-By-Phase Migration Checklist

### Phase 0

- complete this audit
- avoid user-visible changes
- keep V1 stable
- do not begin feature migration before the local data-layer plan is clear

### Phase 1

- define Supabase schema to match V2 entities and lifecycle
- finalize cloud representation of `Roll`, `RollParticipant`, `Exposure`, `Invite`, and `Profile`

### Phase 2

- implement RPC functions for lifecycle ownership
- ensure server owns start/reveal/join transitions

### Phase 3

- introduce SwiftData local models
- add repository interfaces and concrete implementations
- keep existing rendering and camera services, but move view models onto repositories
- introduce DTO/domain mapping between SwiftData and Supabase payloads

### Phase 4

- add shared-roll lobby foundations
- participant list
- invite acceptance
- creator-only start behavior

### Phase 5

- replace local roll-count mutation with exposure-slot creation and RPC-owned start semantics
- precreate exposure placeholders locally and remotely

### Phase 6

- integrate capture with local `Exposure`
- store JPEG locally first
- queue uploads
- add sync and polling behavior

### Phase 7

- move reveal gating to cloud-backed readiness
- reveal through RPC
- make revealed state read-only and consistent across devices

### Phase 8

- build shared gallery grouped by participant
- continue using on-device rendering for revealed exposures

### Phase 9

- handle conflict states, offline edge cases, retry paths, migration issues, and integrity testing

---

## Small Refactors Made In Phase 0

None.

Reason:

- the current codebase can be audited accurately without touching V1 behavior
- introducing even small structural edits before the V2 data layer is defined would create churn without meaningful payoff

---

## Recommended Next Step

Begin with the V2 local data layer before any shared-roll UI work.

Priority order:

1. Define SwiftData models that mirror the V2 backend facts.
2. Introduce repository protocols and a composition root.
3. Migrate view models away from direct `LocalStorageService` access.
4. Keep `CameraService`, `PhotoStorageService`, and `PhotoRenderService` intact and adapt them behind the new repositories.

That sequence preserves the strongest parts of V1 while replacing the pieces that fundamentally conflict with V2.
