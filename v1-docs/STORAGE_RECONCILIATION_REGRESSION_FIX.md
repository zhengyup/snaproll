# Storage Reconciliation Regression Fix

## Summary

A regression was introduced when the startup storage reconciliation pass was added.

On cold launch, Snaproll could rewrite valid rolls so their `exposuresUsed` count became `0`, which made previously captured rolls appear wiped even though the roll records themselves still existed.

This document explains the symptom, diagnosis, root cause, fix, and validation.

## User-Visible Symptom

- Capture photos into one or more rolls.
- Close the app.
- Remove Snaproll from the iPhone app switcher.
- Reopen Snaproll.
- Existing rolls still appear, but their captured exposure count resets to `0`.

## Impact

- The bug affected the app's core product loop.
- Valid roll progress could be overwritten during normal startup.
- The previous reconciliation logic was too destructive for MVP storage integrity work.

## Diagnosis

The investigation focused on the startup path because the issue only appeared after a full close-and-reopen cycle.

An important clarification:

- force-quitting the app from the app switcher does not itself delete Snaproll's files
- it does force a cold launch on the next open
- that cold launch reruns the startup reconciliation pass
- the destructive reconciliation logic is what reset roll progress

### Relevant code path

`HomeViewModel.init()` and `HomeViewModel.reload()` both call:

- `refreshFromStorage()`

which in turn called:

- `storageIntegrityService.reconcile()`

before loading rolls back into memory.

### Problematic behavior in the original reconciliation pass

The original `StorageIntegrityService` did two risky things:

1. It treated the startup reconciliation pass as authoritative enough to rewrite roll progress.
2. It persisted absolute sandbox file paths in `Photo.localPath` and then treated path validation during startup as authoritative.
3. It relied on `LocalStorageService.loadPhotos()` and `LocalStorageService.loadRolls()`, which intentionally return empty arrays on any read or decode failure.

That combination meant:

- every startup had a chance to reinterpret saved photo state before the UI loaded
- stale absolute sandbox paths could make valid photo metadata look invalid
- and the service could rewrite every roll using `0` captured photos

The destructive step was the downward reconciliation of:

- `roll.exposuresUsed`

from:

- `photo count loaded during startup`

This made the reconciliation layer a hidden source of truth for roll progress, which was incorrect.

### Actual deterministic bug mechanism

The more precise root cause was that Snaproll saved photo locations like this:

- `/var/mobile/Containers/Data/Application/<container-id>/Library/Application Support/Snaproll/Rolls/<roll-id>/<photo-id>.jpg`

That is a raw absolute sandbox path.

Absolute sandbox paths are a poor persistence format because the app container root is not the product-level identity of the file.

On cold launch, the reconciliation code trusted those paths directly.

If the saved absolute container root no longer matched the current environment, every startup path check could fail consistently.

Once that happened, reconciliation treated the photo metadata as invalid and recalculated all roll progress downward from the now-empty surviving photo list.

That explains the deterministic behavior much better than a random decode failure would.

## Root Cause

The root cause was not the existence of cleanup logic itself.

The root cause was that the cleanup logic was:

- destructive,
- eager,
- based on lossy read helpers and brittle absolute file paths,
- and allowed to decrease persisted roll progress during app startup.

In other words:

startup reconciliation was allowed to mutate product state based on an uncertain storage read.

## Fix

The reconciliation pass was changed to be conservative.

### 1. Added explicit integrity-load methods

`LocalStorageService` now exposes:

- `loadRollsForIntegrityCheck()`
- `loadPhotosForIntegrityCheck()`

These throw on read/decode problems instead of silently collapsing into `[]`.

This allows the integrity layer to distinguish:

- "there is no file"

from:

- "the file exists but could not be read or decoded"

### 2. Abort reconciliation on uncertain reads

`StorageIntegrityService.reconcile()` now exits without mutating anything if storage cannot be loaded confidently.

This prevents startup cleanup from rewriting valid app state when the read itself is uncertain.

### 3. Stop persisting brittle absolute sandbox paths

`Photo.localPath` now stores a stable path relative to the Snaproll photo storage root instead of the full absolute sandbox path.

The storage layer also now:

- resolves old legacy absolute paths
- normalizes them into the new relative format
- keeps photo lookup working even when older saved metadata still contains the legacy absolute style

This makes the persisted path portable across cold launches and less dependent on the container root string.

### 4. Stop destructive file-missing cleanup during startup

The previous version removed `Photo` metadata just because the file check failed during reconciliation.

That was too aggressive for cold launch.

The updated reconciliation now only removes data that is definitely invalid, such as:

- photo metadata whose `rollID` no longer exists
- roll storage directories whose roll no longer exists

### 5. Never decrease roll exposure counts during reconciliation

The previous version recomputed:

- `roll.exposuresUsed = min(shotLimit, photoCount)`

which could reduce valid progress to `0`.

The updated version preserves persisted roll progress and only reconciles upward when metadata indicates a higher valid count:

- `reconciledExposureCount = max(persistedExposureCount, metadataExposureCount)`

This keeps reconciliation from acting like a destructive reset pass.

## Files Changed

- `ios/snaproll/snaproll/Services/LocalStorageService.swift`
- `ios/snaproll/snaproll/Services/StorageIntegrityService.swift`
- `ios/snaproll/snaproll/Services/PhotoStorageService.swift`
- `ios/snaproll/snaproll/ViewModels/CameraViewModel.swift`

## Validation

Validation was performed by:

1. Inspecting the startup load path from `HomeViewModel`.
2. Tracing how reconciliation rewrote roll progress.
3. Confirming that the previous logic treated persisted absolute sandbox paths as authoritative.
4. Confirming that startup reconciliation could downgrade roll progress from that path validation.
5. Updating storage to use stable relative paths plus legacy-path normalization.
6. Updating reconciliation logic to be conservative.
7. Rebuilding the iPhone target successfully.

Build command used:

```bash
xcodebuild -quiet -project /Users/zhengyu/Desktop/projects/snaproll/ios/snaproll/snaproll.xcodeproj -scheme snaproll -destination 'generic/platform=iOS' -derivedDataPath /Users/zhengyu/Desktop/projects/snaproll/.derivedData-ios CODE_SIGNING_ALLOWED=NO build
```

Result:

- exit code `0`

## Engineering Takeaway

Startup integrity jobs should not be allowed to downgrade persisted user data unless the source of truth is unquestionably valid.

For Snaproll, roll progress is product-critical state.

That means reconciliation must follow two rules:

1. Be conservative on uncertain reads.
2. Prefer preserving existing user progress over aggressively "fixing" state during launch.

It also means persisted file references inside app storage should use stable relative identifiers, not brittle absolute sandbox paths.
