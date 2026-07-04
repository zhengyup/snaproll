# Phase 4 Summary

## Overview

Phase 4 establishes the camera foundation for Snaproll without implementing actual capture or persistence yet. The focus of this phase was reliability, architectural separation, and a minimal camera experience that feels calm instead of cluttered.

## Work Completed

- Implemented a real `CameraService` using AVFoundation.
- Added camera authorization handling for not determined, denied, restricted, authorized, and unavailable states.
- Added camera session configuration and lifecycle management.
- Added a live preview bridge for the capture session.
- Added `CameraViewModel` so SwiftUI screens do not directly coordinate AVFoundation.
- Replaced the placeholder camera screen with a minimal full-screen camera interface.
- Added back navigation and an exposure counter placeholder in `CameraView`.
- Wired `RollView` into `CameraView` for active rolls.

## Architectural Decisions

- `CameraService` owns AVFoundation session setup and running state.
- `CameraViewModel` translates service state into presentation-friendly screen state.
- The preview is isolated in a dedicated bridge view so the preview surface can be redesigned later without changing service logic.
- Camera capture, persistence, and shot mechanics remain intentionally out of scope for this phase.

## Known Limitations

- The shutter button is present but intentionally disabled.
- No photos are captured or saved.
- No exposure consumption happens yet.
- The current preview is full-screen and functional, but not the final art-directed camera experience.

## Next Phase

- Add real photo capture.
- Connect captures to shot accounting.
- Begin hidden local photo persistence once capture flow is stable.

## Validation

Build verified with:

```bash
xcodebuild -quiet -project ios/snaproll/snaproll.xcodeproj -scheme snaproll -destination 'generic/platform=macOS' -derivedDataPath /Users/zhengyu/Desktop/projects/snaproll/.derivedData-macos CODE_SIGNING_ALLOWED=NO build
xcodebuild -quiet -project ios/snaproll/snaproll.xcodeproj -scheme snaproll -destination 'generic/platform=iOS' -derivedDataPath /Users/zhengyu/Desktop/projects/snaproll/.derivedData-ios CODE_SIGNING_ALLOWED=NO build
```
