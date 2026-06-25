# AI Development Guide

Platform:
- Native iOS
- SwiftUI
- AVFoundation for camera
- Local storage first
- Supabase backend later

Development Principles:
- Camera reliability is core.
- Never lose captured photos.
- Photos must remain hidden before reveal.
- Keep MVP simple.
- Prefer local persistence over network dependence.
- Each Codex phase should be small and testable.
- Update this guide after every completed phase.

Product Direction:
- Snaproll is centered on rolls, not events.
- A roll represents a memory collection captured over time.
- Examples include "June 2026", "Summer 2026", "Okinawa", and "Autumn Walks".
- The product goal is anticipation and memory preservation, not film simulation.

Architecture:
- SwiftUI views
- ViewModels for view state only
- Models for rolls, members, and photos
- Services introduced as lightweight placeholders before real implementations
- Local persistence and camera integration added in later phases

Initial MVP Order:
1. Project foundation and navigation
2. Local roll creation flow
3. Member/join model
4. Camera capture
5. Local hidden photo storage
6. Shot limit enforcement
7. Locked roll and reveal gallery
8. Supabase sync
9. TestFlight/ad-hoc distribution

## Phase 1 Completed Work

- Refactored the app target into `App`, `Models`, `Views`, `ViewModels`, `Services`, and `Utilities`.
- Replaced the starter SwiftUI template with roll-focused placeholder screens.
- Added placeholder models: `Roll`, `Member`, and `Photo`.
- Added placeholder services: `CameraService`, `PhotoStorageService`, and `LocalStorageService`.
- Wired navigation for the core Phase 1 flow: `HomeView -> CreateRollView -> RollView -> CameraView`.
- Added placeholder destinations for locked-roll and gallery screens without implementing business logic.
- Verified the app builds without external dependencies.

## Architectural Decisions

- The user request is treated as the source of truth for terminology: code now uses `Roll` instead of `Event`.
- Phase 1 intentionally avoids persistence, backend integration, camera implementation, and real creation forms.
- Filesystem-synced Xcode groups are used so folder organization can evolve without manual project-file maintenance.
- Navigation is driven directly from SwiftUI views for now; more structured state coordination can be introduced when flows become dynamic.
- Placeholder services exist to reserve integration points without pulling future logic into the foundation phase.

## Phase 2 Completed Work

- Implemented a real `Roll` model with `id`, `name`, `shotLimit`, `unlockDate`, and `createdAt`.
- Replaced the placeholder create screen with editable input for roll name, shot limit, and reveal date.
- Added local JSON persistence so saved rolls survive app restarts.
- Updated `HomeView` to show locally saved rolls and route into creation and detail flows.
- Implemented a real `RollView` with roll name, exposures remaining, reveal date, and a countdown placeholder.
- Kept the UI restrained with larger typography, generous spacing, and a soft nature-inspired tone.
- Verified the project builds without external dependencies.

## Phase 2 Architectural Decisions

- `Roll` is now `Codable` and persisted as a simple JSON array for minimal local-first storage.
- Persistence lives in `LocalStorageService` so storage details stay out of SwiftUI views.
- `HomeViewModel` owns the in-memory roll list and save flow for Phase 2.
- `CreateRollViewModel` owns transient form state to keep creation UI simple and testable.
- Navigation now centers on `HomeView -> CreateRollView -> RollView`, while camera and reveal screens remain out of the active user flow.
- Exposures remaining currently mirrors `shotLimit` because capture and shot consumption are intentionally deferred.

## Next Phase

- Introduce member and join concepts without changing the local-first foundation.
- Decide how a roll should represent ownership and participation before camera work begins.
- Keep persistence simple while expanding the model surface only where the next feature requires it.

## Phase 3 Completed Work

- Reworked `HomeView` into a darker, calmer "My Rolls" experience inspired by the current UI direction.
- Introduced a stronger empty state that invites the user to begin their first roll without feeling like a utility screen.
- Promoted the newest saved roll into an "active roll" presentation while keeping older rolls visible below it.
- Reworked `RollView` into a more object-like detail screen with a large capture counter, progress indicator, and simple language.
- Removed reveal-date-driven behavior from the active flow. Rolls are now intended to open only after every exposure has been used.
- Added a disabled `Capture Memory` button in `RollView` as a future integration point for camera work.
- Added a shared `AppTheme` utility for consistent phase-level presentation without introducing custom assets or dependencies.
- Verified the project builds successfully without backend or camera implementation.

## Phase 3 Architectural Decisions

- The first locally saved roll is treated as the active roll for now to keep the product experience cohesive without introducing additional roll-state complexity.
- Roll presentation now centers on completion state rather than calendar state, which better matches the product direction of "open when full."
- Shared presentation helpers live on `Roll` so home and detail screens can phrase status consistently without duplicating UI copy.
- Shared colors were moved into `AppTheme` to keep the darker editorial tone lightweight and easy to refactor later.
- `RollView` includes a disabled capture CTA instead of navigation so the screen can be prepared for camera integration without implying unfinished behavior.
- The home screen still supports roll deletion, but the primary emphasis has shifted from list management toward living with a roll over time.

## Next Phase

- Introduce actual shot consumption so rolls can progress from in-progress to finished.
- Decide how completed rolls should move from the active list into a true review state once capture exists.
- Add camera navigation only when capture flow, shot usage, and post-completion review can be connected end-to-end.

## Phase 4 Completed Work

- Replaced the placeholder `CameraService` with a real AVFoundation-backed service for authorization, session configuration, lifecycle, and preview support.
- Added `CameraViewModel` so camera state and service coordination live outside SwiftUI screens.
- Replaced the placeholder `CameraView` with a full-screen live preview, minimal chrome, a back button, and an exposure counter placeholder.
- Added a dedicated preview bridge view so the preview implementation can be swapped later without rewriting camera screen logic.
- Wired `RollView -> CameraView -> RollView` navigation for active rolls.
- Added a graceful permissions flow with explanatory copy, retry support, and settings handoff on iOS.
- Verified the project builds successfully without adding photo capture, persistence, backend work, or external dependencies.

## Phase 4 Architectural Decisions

- AVFoundation session ownership stays inside `CameraService`; `CameraView` only talks to `CameraViewModel`.
- `CameraViewModel` exposes the preview session and permission state as presentation data while keeping business rules out of the service.
- The live preview is isolated in a representable bridge so the camera surface can later change from full-screen to a smaller viewfinder without reworking session logic.
- Camera setup is intentionally limited to session preview and authorization. Capture outputs, save flows, and film mechanics are deferred to later phases.
- Permission-denied handling stays calm and explicit instead of failing silently or crashing, matching the product’s more deliberate tone.

## Known Limitations

- The shutter button is intentionally non-functional in this phase.
- No photo data is captured, processed, or saved yet.
- Exposure progress shown in the camera remains placeholder-driven until shot consumption is implemented.
- The current camera preview uses the full screen for simplicity; the final tactile camera aesthetic is still deferred.

## Next Phase

- Add photo capture without introducing review or persistence leaks before the roll is complete.
- Connect successful captures to shot consumption so the roll can progress toward automatic reveal.
- Introduce local hidden photo persistence only after capture and shot accounting work end to end.

## Phase 5 Completed Work

- Added a single development configuration source in `ios/snaproll/snaproll/Utilities/AppConfig.swift` and temporarily reduced the minimum/default roll size to `3` exposures for faster manual testing.
- Extended `Roll` with persisted shot usage and completion state so rolls now survive restarts with accurate progress.
- Updated `Photo` into a real persisted metadata model with `id`, `rollId`, `localPath`, `createdAt`, and `exposureNumber`.
- Extended `LocalStorageService` to persist both `rolls.json` and `photos.json`.
- Replaced the placeholder `PhotoStorageService` with a real local file storage service that compresses images to JPEG and stores them per roll in Application Support.
- Extended `CameraService` with real `AVCapturePhotoOutput` capture while keeping all AVFoundation-specific implementation inside the service.
- Expanded `CameraViewModel` to orchestrate capture, hidden local storage, roll-progress updates, error handling, and final-roll completion without exposing image review to the UI.
- Updated `CameraView`, `RollView`, and `HomeView` so successful captures immediately update progress, show subtle confirmation messaging, and dismiss back to `RollView` when the final exposure is used.
- Verified the project builds successfully for iPhone without external dependencies or backend work.

## Phase 5 Architectural Decisions

- `AppConfig` is now the single source of truth for development roll sizing and photo-capture timing constants so the production roll size can be restored by changing one constant.
- `CameraService` owns session setup and image capture only; file storage remains isolated in `PhotoStorageService`, and JSON metadata persistence remains isolated in `LocalStorageService`.
- `CameraViewModel` acts as the orchestration layer for the hidden-film flow: capture image data, save the JPEG file, persist `Photo` metadata, update the `Roll`, and surface only lightweight UI state back to SwiftUI.
- Captured photos are stored in `Application Support/Snaproll/Rolls/<roll-id>/` so assets are organized by roll while remaining out of the visible review flow.
- The camera UI never renders the captured frame, thumbnail, or gallery entry. Instead it shows a brief text confirmation and returns to the live preview or to `RollView` on the final exposure.
- `RollView` now keeps a local copy of the active roll so camera captures can update the detail screen immediately on return, while `HomeViewModel` persists the same update back into the home list.
- `PRODUCT_SPEC.md` and `ARCHITECTURE.md` still contain older event-based language. Phase 5 continued using the newer roll-based direction from this guide and the active implementation prompts to avoid reintroducing outdated concepts.

## Known Limitations

- This phase has been verified with an iPhone-target build, but not with hands-on device testing from within Codex.
- Photos are stored locally and hidden from the user, but reveal/gallery behavior is still intentionally unimplemented.
- Capture persistence currently uses simple JSON-array rewrites for metadata, which is acceptable for the MVP but not yet optimized for large libraries.
- Roll deletion still removes the roll from JSON storage only; this phase does not yet clean up a deleted roll's saved image files.

## Next Phase

- Build the locked-roll and reveal flow on top of the now-complete local capture pipeline.
- Decide how finished rolls transition into a reveal-ready state without weakening the hidden-film illusion.
- Introduce review/gallery behavior only after the reveal boundary is clearly defined and enforced.

## Phase 6 Completed Work

- Added a distinct `revealed` roll state so finished rolls can transition from capture-complete into viewable, read-only memory collections.
- Created `RevealViewModel` to own reveal state, local photo loading, one-time reveal persistence, and roll update propagation back to the rest of the app.
- Added `RevealView` as a dedicated reveal experience with a calm opening screen for completed rolls and a finished-roll gallery for revealed rolls.
- Replaced the placeholder review path in `RollView` with real `Reveal Roll` and `View Roll` navigation depending on the roll state.
- Added a native SwiftUI `LazyVGrid` gallery that displays every roll photo in chronological exposure order.
- Extended `PhotoStorageService` with centralized local image loading so reveal screens reuse the same storage boundary as capture.
- Updated `HomeView` and `HomeViewModel` so revealed rolls are labeled distinctly and no longer count as active rolls.
- Verified the project builds successfully for iPhone without backend work, sharing, filters, or cloud storage.

## Phase 6 Architectural Decisions

- Reveal logic is coordinated in `RevealViewModel` instead of `RollView` so the one-time reveal transition, photo loading, and roll persistence stay off the view layer.
- Rolls now move through a simple state sequence: `inProgress -> completed -> revealed`.
- The reveal screen marks a roll as revealed only when the user deliberately opens it, rather than immediately when the detail screen is visited.
- `PhotoStorageService` remains the single place responsible for local image loading; the reveal UI only receives already-resolved presentation data.
- The gallery stays intentionally simple with native `LazyVGrid`, local file loading, and placeholder tiles for missing images so the reveal feels reflective rather than tool-like.
- `PRODUCT_SPEC.md` and `ARCHITECTURE.md` still contain older event-based language, so Phase 6 continued following the roll-based direction from this guide and the active implementation prompts.

## Known Limitations

- This phase has been verified with an iPhone-target build, but not with direct hands-on device testing from inside Codex.
- Tapping into a revealed roll shows the full grid immediately; there is not yet a deeper per-photo detail or paged lightbox experience.
- Missing image files are handled gracefully with placeholders, but there is not yet a repair or recovery workflow for damaged local storage.
- Roll deletion still does not clean up saved JPEG files from disk.

## Next Phase

- Add richer revealed-roll browsing only if it supports the reflective tone without turning the app into a general photo manager.
- Introduce cleanup for deleted rolls so local image files and metadata stay in sync.
- Revisit the older spec and architecture docs so the written source of truth matches the now-established roll-based product direction.

## Phase 7 Completed Work

- Added a dedicated `FilmStock` model with the MVP stock set: Kodak Gold 200, Fujifilm Superia 400, and Ilford HP5 Plus.
- Kept `Roll` attached to a selected film stock with backward-safe decoding that defaults older saved rolls to Kodak Gold 200.
- Updated the create-roll flow so film selection shows each stock's name, short description, and color or black-and-white type.
- Replaced the generic revealed-image processor with `PhotoRenderService`, a modular rendering pipeline that applies film-inspired looks only after reveal.
- Implemented stock-specific looks for Kodak Gold 200, Fujifilm Superia 400, and Ilford HP5 Plus using simple Core Image adjustments.
- Preserved the real revealed-roll gallery and full-screen photo viewer while routing all revealed rendering through the new stock-aware pipeline.
- Kept original stored images untouched and applied rendering only to display copies loaded during the reveal flow.
- Added lightweight in-memory caching inside the rendering service so repeated gallery and full-screen viewing does not re-run the same transforms unnecessarily.
- Preserved failure safety by falling back to the original loaded image if rendering fails.
- Verified the project builds successfully for iPhone without adding sharing, backend work, advanced reveal effects, or destructive processing.

## Phase 7 Architectural Decisions

- `FilmStock` is a standalone model so product-facing stock metadata does not stay buried inside `Roll`.
- `PhotoRenderService` is now the single place responsible for revealed-image styling so future film looks can be added without rewriting gallery, storage, or capture code.
- Rendering happens only after reveal, inside the reveal flow, which preserves the product rule that shooting remains hidden and visually unprocessed.
- `PhotoStorageService` still owns filesystem reads; `PhotoRenderService` only transforms already-loaded `UIImage` instances and never overwrites originals.
- `RevealViewModel` coordinates photo metadata loading, original image loading, and rendered image preparation so SwiftUI views remain presentation-focused.
- A lightweight `NSCache` lives inside `PhotoRenderService` because the same revealed images are revisited between the grid and the full-screen viewer. This keeps caching simple and fully in memory.
- Full-screen browsing still uses a restrained `TabView` pager instead of a heavier custom gesture system, which keeps the interaction Apple-native and maintainable.

## Known Limitations

- This phase has been verified with an iPhone-target build, but not with hands-on device testing from inside Codex.
- The rendering pipeline is intentionally approximate and expressive rather than a scientific emulation of real film stocks.
- Processed images are cached in memory only; there is no disk cache for rendered variants.
- Full-screen browsing supports swipe paging and close, but there is not yet pinch-to-zoom or deeper photo metadata presentation.
- Older event-based language still remains in `PRODUCT_SPEC.md` and `ARCHITECTURE.md`, even though the implementation continues to follow the current roll-based direction.

## Next Phase

- Decide whether revealed browsing should gain a richer single-photo experience such as zooming, captions, or sequencing details without losing the app's quiet tone.
- Revisit whether rendered-image disk caching is worthwhile once roll sizes grow beyond the current development configuration.
- Continue cleaning up the older written spec so the repository's top-level documents match the now-established product direction.
