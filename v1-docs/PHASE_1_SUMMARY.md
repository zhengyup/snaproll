# Phase 1 Summary

## Overview

Phase 1 established the Snaproll iOS project foundation and aligned the app scaffold with the roll-based product direction.

## What Changed

- Reorganized the SwiftUI app target into the following folders:
  - `App`
  - `Models`
  - `Views`
  - `ViewModels`
  - `Services`
  - `Utilities`
- Replaced the default starter content with roll-oriented placeholder screens:
  - `HomeView`
  - `CreateRollView`
  - `RollView`
  - `CameraView`
  - `LockedRollView`
  - `GalleryView`
- Added placeholder data models:
  - `Roll`
  - `Member`
  - `Photo`
- Added placeholder service types:
  - `CameraService`
  - `PhotoStorageService`
  - `LocalStorageService`
- Added a minimal `HomeViewModel` to support the initial screen.
- Added a small utility file for shared app constants.

## Navigation Implemented

The following Phase 1 navigation flow is now wired:

`HomeView -> CreateRollView -> RollView -> CameraView`

Additional placeholder navigation is also available from `RollView` to:

- `LockedRollView`
- `GalleryView`

## Intentional Non-Goals

This phase does not implement:

- Camera functionality
- Photo capture logic
- Persistence
- Backend integration
- Supabase
- Business rules such as shot limits or reveal logic

## Architectural Notes

- The codebase now follows roll terminology instead of event terminology.
- Placeholder services and models keep the project compile-safe while reserving clear extension points for later phases.
- The app remains dependency-free beyond the default Apple frameworks already used by SwiftUI.

## Validation

Build verified with:

```bash
xcodebuild -project ios/snaproll/snaproll.xcodeproj -scheme snaproll -destination 'generic/platform=iOS' -derivedDataPath /Users/zhengyu/Desktop/projects/snaproll/.derivedData CODE_SIGNING_ALLOWED=NO build
```

## Recommended Next Step

Phase 2 should implement local roll creation, starting with editable form state in `CreateRollView` and basic in-memory roll data shown from `HomeView`.
