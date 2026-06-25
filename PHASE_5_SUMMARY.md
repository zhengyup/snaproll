# Phase 5 Summary

## Work Completed

- Added real photo capture on top of the existing AVFoundation session.
- Added hidden local image storage with JPEG compression and per-roll directories.
- Persisted `Photo` metadata locally in `photos.json`.
- Extended `Roll` persistence so used exposures and completion state survive app restarts.
- Updated the camera flow so each successful capture immediately reduces remaining exposures and updates the UI.
- Added subtle post-capture confirmation messaging without ever showing the captured image.
- Automatically marks a roll complete on the final exposure and returns from `CameraView` to `RollView`.

## Architectural Decisions

- `ios/snaproll/snaproll/Utilities/AppConfig.swift` is now the single source of truth for development-only roll sizing and camera feedback timing.
- `CameraService` owns AVFoundation session and capture responsibilities only.
- `PhotoStorageService` owns JPEG compression and filesystem writes only.
- `LocalStorageService` owns JSON metadata persistence for rolls and photos only.
- `CameraViewModel` coordinates the hidden-film capture flow across those services without exposing AVFoundation to SwiftUI views.
- `RollView` keeps local roll state so camera progress updates are visible immediately after returning from capture.

## Storage Strategy

- Roll metadata is stored in `Documents/rolls.json`.
- Photo metadata is stored in `Documents/photos.json`.
- Captured JPEG files are stored in `Application Support/Snaproll/Rolls/<roll-id>/`.
- Photos are organized per roll and referenced by persisted local file paths in the `Photo` model.

## Development Configuration

- The temporary development roll size lives in `ios/snaproll/snaproll/Utilities/AppConfig.swift`.
- `AppConfig.Rolls.minimumShotLimit` and `AppConfig.Rolls.defaultShotLimit` are both currently set to `3`.
- Restoring the production baseline is a one-line change: set `AppConfig.Rolls.minimumShotLimit` back to `24`.

## Known Limitations

- Reveal and gallery behavior are still intentionally not implemented.
- Roll deletion does not yet remove already-saved JPEG files from local storage.
- Metadata persistence still rewrites full JSON arrays, which is acceptable for the MVP but not the final storage strategy.
- This phase was validated with an iPhone-target build, but not with direct manual device testing from inside Codex.

## Next Phase

- Implement the locked roll and reveal flow on top of the local hidden-photo pipeline.
- Decide how completed rolls surface as reveal-ready without exposing their images early.
- Add cleanup behavior for deleted rolls once the reveal storage lifecycle is fully defined.
