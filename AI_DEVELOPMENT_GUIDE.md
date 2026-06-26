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
- Refactored the revealed roll into a filmstrip-style viewer that presents one selected photo at a time with a horizontal strip of thumbnails underneath.
- Updated the revealed viewing experience to preserve original photo composition at all times: no automatic cropping, no stretching, and black space used whenever needed.
- Added camera-only orientation control so the capture experience requests landscape while the rest of the app remains portrait.
- Tuned Fujifilm Superia 400 further toward cooler whites, gentler contrast, subtle green-blue influence, softer highlights, slightly lifted blacks, and restrained fine grain.
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
- `GalleryView` now adapts itself to the selected photograph instead of forcing photographs into a fixed grid. Landscape images use full available width, portrait images remain centered, and black space absorbs any leftover area.
- Orientation preference is now explicit per screen. Portrait screens opt into portrait, while `CameraView` opts into landscape so the film-camera experience can feel distinct without rotating the whole app permanently.
- A lightweight `NSCache` lives inside `PhotoRenderService` because the same revealed images are revisited between the grid and the full-screen viewer. This keeps caching simple and fully in memory.
- The revealed viewer now prioritizes composition fidelity over generic gallery density, which better matches the intended compact-film-camera feel from the current visual references.

## Known Limitations

- This phase has been verified with an iPhone-target build, but not with hands-on device testing from inside Codex.
- The rendering pipeline is intentionally approximate and expressive rather than a scientific emulation of real film stocks.
- Processed images are cached in memory only; there is no disk cache for rendered variants.
- The current camera orientation support still relies on older AVFoundation orientation APIs that compile cleanly but emit SDK deprecation warnings for future migration.
- The revealed viewer now favors a single-photo filmstrip layout, but there is not yet a richer zoom or metadata interaction layer.
- Older event-based language still remains in `PRODUCT_SPEC.md` and `ARCHITECTURE.md`, even though the implementation continues to follow the current roll-based direction.

## Next Phase

- Decide whether revealed browsing should gain a richer single-photo experience such as zooming, captions, or sequencing details without losing the app's quiet tone.
- Revisit whether rendered-image disk caching is worthwhile once roll sizes grow beyond the current development configuration.
- Continue cleaning up the older written spec so the repository's top-level documents match the now-established product direction.

## Phase 10 Completed Work

- Added a dedicated `ExportService` that owns revealed-photo export, whole-roll export, Photos permission flow, and shareable rendered file preparation.
- Kept export limited to revealed rolls so memories remain hidden until the roll has been fully completed and opened.
- Added individual photo export and native share-sheet actions to the revealed single-photo viewer.
- Added whole-roll export and share actions to both the revealed gallery menu and the revealed roll detail menu.
- Preserved film rendering during export by exporting the rendered display version rather than the hidden original capture.
- Added generated Photo Library usage descriptions to the app target so export permission requests are correctly described at runtime.
- Added a native `UIActivityViewController` bridge for Apple’s standard share sheet without introducing custom sharing UI.
- Updated manual testing guidance for single-photo export, whole-roll export, order preservation, restart behavior, and permission denial handling.
- Verified the project builds successfully for iPhone without changing capture flow, reveal boundaries, or original local photo storage.

## Phase 10 Architectural Decisions

- `ExportService` composes existing local storage, photo loading, and rendering services so export logic stays out of SwiftUI screens and can be reused by both roll detail and reveal flows.
- Whole-roll export loads and renders photos in exposure order inside the service, which keeps ordering consistent across export and share entry points.
- Share-sheet payloads are prepared from temporary rendered JPEG files so sharing uses the processed film look while leaving hidden originals untouched.
- Photos permission uses the `.readWrite` authorization path so limited-library access can be detected and treated as an allowed export state.
- `RevealViewModel` owns revealed-photo export and sharing because it already has the selected rendered photo context, while `RollActionsViewModel` keeps roll-level export behavior out of `RollView`.
- Whole-roll export continues after individual failures and reports a summary rather than aborting at the first failed image.

## Known Limitations

- This phase has been verified with an iPhone-target build, but not with hands-on export testing on a real device from inside Codex.
- Whole-roll export preserves attempt order, but the Apple Photos app ultimately controls how imported assets are displayed after saving.
- Shared files are written to a temporary export directory and recreated on demand; there is no persistent exported-file cache.
- The current camera orientation path still emits older AVFoundation deprecation warnings that are unrelated to export and remain future cleanup work.
- `PRODUCT_SPEC.md`, `ARCHITECTURE.md`, and `TESTING.md` still contain some older event-based wording, even though the implementation follows the current roll-based Snaproll flow.

## Next Phase

- Run the full export flow on a real iPhone to validate Photos permission prompts, limited-access handling, Apple Photos ordering, and share-sheet destinations end to end.
- Decide whether a future post-MVP build should add richer export presentation such as progress UI for larger rolls without increasing interface clutter.
- Reconcile the remaining older top-level product docs so the written specification matches the shipped roll-based MVP behavior.

## Phase 11.1 Completed Work

- Kept the existing `UIImage -> CIImage -> film-specific render path -> Core Image filters -> UIImage` rendering architecture inside `PhotoRenderService`.
- Introduced a film-profile-based renderer configuration so each stock now has its own tone curve, highlight/shadow response, softening settings, grain settings, and vignette behavior.
- Replaced the previous heavier reliance on simple saturation and contrast with stock-specific `CIToneCurve` shaping as a primary part of the look.
- Improved Fujifilm Superia 400 with cooler white balance, subtler channel shaping for greener foliage and cleaner skies, softer highlight roll-off, and restrained grain.
- Improved Kodak Gold 200 with warmer midtones, soft golden highlights, slightly richer tonal contrast, and a more nostalgic warmth without pushing the image orange.
- Improved the black-and-white rendering by switching to a richer monochrome conversion with deeper tonal separation, stronger grain, and smoother highlight handling.
- Added a subtle softening step after noise reduction to reduce the over-crisp digital feel without making images blurry.
- Reworked grain so it is more visible in shadows and midtones, weaker in bright highlights, and softer overall to feel more like scanned film than a flat overlay.
- Temporarily reduced `AppConfig.Rolls.minimumShotLimit` to `1` for faster manual renderer tuning, while keeping that decision in a single configuration value.
- Verified the project builds successfully for iPhone after the renderer changes.

## Phase 11.1 Architectural Decisions

- The renderer still lives entirely in `PhotoRenderService`; reveal, export, and storage layers continue to treat it as the single source of rendered image output.
- A lightweight internal `FilmProfile` configuration now drives stock-specific parameters without replacing the rendering pipeline or introducing LUTs or third-party tooling.
- Tone shaping is now handled primarily by `CIToneCurve`, while `CIHighlightShadowAdjust`, color temperature, color matrix adjustments, subtle noise reduction, and grain remain supporting steps.
- Grain stays procedural and on-device using Core Image primitives so performance remains suitable for the current MVP and rendered image caching still works unchanged.
- Softening is implemented as a low-opacity blurred overlay after noise reduction, which keeps the images from feeling overly digital without materially changing the renderer’s architecture.
- `PHASE_11_SUMMARY.md` was referenced in the prompt but is not present in the repository, so this phase followed the active renderer implementation and current development guide as the available source of truth.

## Known Limitations

- This phase was validated with an iPhone-target build, but not with real-device visual tuning from inside Codex.
- The film look is still an approximation built from fast Core Image operations rather than a scanned-film or LUT-based emulation.
- Grain remains procedural and subtle by design; it is more film-like than before, but it is still not a stock-accurate grain simulation.
- Caching behavior is unchanged and remains in-memory only.
- Older event-based wording still exists in some top-level docs even though the implementation follows the roll-based Snaproll product direction.

## Next Phase

- Tune the updated renderer on a real iPhone using outdoor foliage, skin tones, bright skies, and night scenes to calibrate subtlety against actual captures.
- Restore `AppConfig.Rolls.minimumShotLimit` from `1` to `24` before release once renderer tuning is complete.
- Continue tightening the written product docs so the top-level repository documents match the current Snaproll implementation.

## Phase 11.3 Completed Work

- Studied the local film reference folders for Kodak Gold and Fujifilm Superia to tune toward stock character instead of isolated one-off images.
- Kept the existing `PhotoRenderService` architecture and existing film stock selection logic intact.
- Refactored `PhotoRenderService` so the same rendering pipeline can now output `CGImage` results for developer tooling while preserving the app-facing `UIImage` rendering path.
- Tuned Kodak Gold 200 toward warmer daylight, softer blue skies, golden highlights, and slightly creamier contrast.
- Tuned Fujifilm Superia 400 toward cooler whites, greener foliage, slightly cyan-leaning skies, and a cleaner everyday snapshot feel with softer contrast than Kodak Gold.
- Added a developer rendering utility at `tools/render_test_images.swift` plus a helper runner at `tools/run_render_test_images.sh`.
- Generated batch outputs for every file in `test-images/` under `render-output/`, including per-image originals, Kodak renders, Superia renders, and comparison contact sheets.
- Preserved all originals by writing only to `render-output/`.

## Phase 11.3 Reference Observations

- Kodak Gold references consistently showed warmer sunlight, creamier highlights, softer blues, gentle nostalgic contrast, and warm but not orange skin tones.
- Fujifilm Superia references leaned cooler overall, with deeper greens, slightly cyan-bluer skies, more neutral skin rendering, and a cleaner, less golden mood.
- Both stocks showed softer highlight roll-off than the digital test images, but Kodak felt airier while Superia carried slightly denser color separation in foliage and urban scenes.

## Phase 11.3 Architectural Decisions

- The renderer still lives entirely inside `PhotoRenderService`; the batch utility compiles against that real service rather than reimplementing any rendering logic.
- `renderedCGImage(...)` was added as a shared output path so app rendering and developer batch rendering use the same film profiles and Core Image pipeline.
- Contact sheets are generated by the utility after rendering so comparison remains fast and filesystem-based, without requiring app UI changes.
- The utility intentionally limits itself to Kodak Gold 200 and Fujifilm Superia 400 because those are the two stocks under active visual comparison in this phase.
- `PHASE_11_SUMMARY.md` was referenced in the prompt but is still not present in the repository, so Phase 11.3 followed the current renderer implementation, the existing guide, and the local reference folders as the available source of truth.

## Known Limitations

- This phase was verified with generated local outputs and an iPhone-target build, but not with real-device side-by-side image review from inside Codex.
- The test utility is macOS-hosted because it uses local Apple frameworks to compile against the shared renderer for offline comparison output.
- Render tuning remains intentionally subtle; some test images will still show smaller stock differences than dramatic online film examples.
- The app still emits the existing AVFoundation deprecation warnings around older camera orientation APIs, which are unrelated to this rendering phase.

## Next Phase

- Review the generated `render-output/contact-sheets/` files on a calibrated display and compare them directly against the local Kodak Gold and Superia reference folders.
- Tune skin tones and foliage further using real iPhone captures if the Superia/Kodak split still feels too close in mixed-light scenes.
- Restore `AppConfig.Rolls.minimumShotLimit` to `24` before release once renderer evaluation and tuning are complete.

## Phase 11.4 Completed Work

- Preserved the Phase 11.3 renderer path and added a feature flag at `AppConfig.Rendering.useBaseFilmResponse` so the new experiment can be enabled or disabled from a single location.
- Introduced a shared base-film-response stage inside `PhotoRenderService` that runs before stock-specific Kodak Gold 200 and Fujifilm Superia 400 adjustments when the flag is enabled.
- Tuned the base stage to soften highlight roll-off, lift blacks slightly, reduce digital crispness, lower microcontrast, and add subtle integrated grain before stock-specific color shaping.
- Kept Kodak Gold 200 and Fujifilm Superia 400 as separate stock renderers after the base stage so each stock still carries its own color character.
- Preserved the legacy renderer logic in the same service so comparison against the previous behavior remains easy and low risk.
- Updated the batch rendering workflow so `tools/run_render_test_images.sh` compiles with `AppConfig.swift` and therefore uses the same feature-flagged renderer path as the app.
- Regenerated the comparison outputs for every image in `test-images/` under `render-output/`, including per-image originals, Kodak renders, Superia renders, and contact sheets.
- Verified the Snaproll iPhone target still builds successfully after the base-film experiment changes.

## Phase 11.4 Architectural Decisions

- The renderer remains centralized in `PhotoRenderService`; neither the gallery nor export flows needed any rendering-specific changes for this experiment.
- The new `BaseFilmProfile` is intentionally lightweight and sits behind the existing film-stock selection flow rather than replacing it with a broader color-science abstraction.
- The old renderer path is preserved through `legacyFilmProfile(...)`, while the new path uses `applyBaseFilmResponse(...)` followed by `experimentalFilmProfile(...)`.
- The cache key now includes whether the base-film path or legacy path was used so rendered results do not collide when the feature flag changes.
- `AppConfig.Rendering.useBaseFilmResponse` is the single toggle for reverting to the pre-experiment renderer behavior without deleting any code.

## Phase 11.4 Evaluation Notes

- The new base stage makes the rendered outputs feel less harsh and less obviously digital before Kodak or Superia-specific color adjustments are applied.
- Kodak Gold 200 now layers warmth and nostalgic contrast on top of a softer shared film base rather than trying to do all of the work directly from the untouched original.
- Fujifilm Superia 400 now layers cooler whites, greener foliage, and cleaner cyan-blue skies on top of the same softened base, which helps keep its look flatter and less golden than Kodak.
- The generated contact sheets suggest the new path is moving closer to the local film references overall, but this still needs human review on a good display and real-device comparison to actual iPhone captures.

## Known Limitations

- This remains a subtle Core Image-based approximation, not a full film-stock emulation or scan pipeline.
- The base-film response is shared across stocks, so deeper stock-specific tonal separation may still be needed in a later phase.
- Real-device visual tuning from inside Codex is still limited to build verification and offline output generation.
- The app still has the existing AVFoundation orientation deprecation warnings, which are unrelated to this renderer experiment.

## Next Phase

- Compare the regenerated `render-output/contact-sheets/` files against the local reference folders on a calibrated display and decide whether the base-film path should remain enabled.
- Continue tuning stock-specific skin tones, foliage, and sky handling now that the shared base-film response has reduced some of the digital feel.
- Restore `AppConfig.Rolls.minimumShotLimit` to `24` before release after renderer testing is complete.

## Film Rendering Lock

- Snaproll's current MVP renderer is now considered locked.
- Do not change film rendering parameters casually.
- Do not retune Kodak Gold 200, Fujifilm Superia 400, or Black & White unless explicitly requested.
- Any future rendering changes should be compared against `test-images/`, `film-references/`, and `render-output/`.
- Future rendering improvements belong in a dedicated Film Lab workflow, not random production tweaks.
