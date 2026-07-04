# Phase 2 Summary

## Overview

Phase 2 implemented local roll creation for Snaproll, turning the Phase 1 scaffold into a working on-device flow that saves rolls across app launches.

## What Changed

- Implemented the `Roll` model with these fields:
  - `id`
  - `name`
  - `shotLimit`
  - `unlockDate`
  - `createdAt`
- Added JSON-based local persistence through `LocalStorageService`.
- Added `CreateRollViewModel` for form state and expanded `HomeViewModel` to manage saved rolls.
- Replaced the placeholder creation screen with editable inputs for:
  - Roll name
  - Shot limit
  - Reveal date
- Updated `HomeView` to list saved rolls and start the creation flow.
- Updated `RollView` to display:
  - Roll name
  - Exposures remaining
  - Reveal date
  - Countdown placeholder

## Navigation

The active flow is now:

`HomeView -> CreateRollView -> RollView`

## Persistence Approach

- Rolls are saved locally as JSON.
- Saved rolls are loaded on app launch.
- No backend or database dependency was introduced.
- This keeps the implementation simple and aligned with the local-first MVP direction.

## Design Notes

The UI was adjusted without a full redesign:

- Larger typography
- More spacing
- Clean Apple-style cards and forms
- Subtle warm green and cream accents for a calm, nature-inspired tone

## Intentional Non-Goals

This phase still does not implement:

- Camera capture
- Supabase
- Sharing
- Film filters
- Reveal logic

## Validation

Build verified with:

```bash
xcodebuild -project ios/snaproll/snaproll.xcodeproj -scheme snaproll -destination 'generic/platform=iOS' -derivedDataPath /Users/zhengyu/Desktop/projects/snaproll/.derivedData CODE_SIGNING_ALLOWED=NO build
```

## Recommended Next Step

Phase 3 should introduce the member and join model while preserving the new local-first roll creation and persistence foundation.
