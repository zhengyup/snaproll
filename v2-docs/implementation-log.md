# V2 Implementation Log

## Phase 11A – V2 Shared Roll Creation + Joinable Lobby

### Files changed

App / V2 flow:

- `ios/snaproll/snaproll/App/V2/V2CloudHomeView.swift`
- `ios/snaproll/snaproll/App/V2/V2SharedRollLobbyView.swift`

View models:

- `ios/snaproll/snaproll/ViewModels/V2CloudHomeViewModel.swift`
- `ios/snaproll/snaproll/ViewModels/V2SharedRollLobbyViewModel.swift`

Tests:

- `ios/snaproll/snaprollTests/V2CloudHomeViewModelTests.swift`
- `ios/snaproll/snaprollTests/V2SharedRollLobbyViewModelTests.swift`

Documentation:

- `v2-docs/implementation-log.md`

### Shared roll creation flow

- Extended the V2 cloud home creation surface to support both:
  - `PERSONAL`
  - `SHARED`
- Shared roll creation now calls the existing `create_roll()` RPC through `RollRepository.createRoll(...)` with:
  - `type = SHARED`
  - `film_stock_id = kodakGold200`
  - `exposures_per_participant = 12`
  - `participant_cap = 10`
- The client does not create participant rows or invites directly.
- After creation:
  - the shared roll is reloaded from Supabase through the normal roll list
  - the returned invite token is stored in the home view model and displayed in a developer-facing card

### Lobby implementation

- Added a dedicated V2 shared lobby screen:
  - `V2SharedRollLobbyView`
- Added a lobby view model that loads:
  - current session
  - roll metadata
  - backend participant list
  - active invite when the current user is the creator
- Shared rolls now route to the lobby from the V2 cloud roll list.
- Personal rolls continue to route to the existing personal-roll detail flow unchanged.

### Invite token display / join flow

- Added a minimal join panel on the V2 cloud home:
  - text field for invite token
  - `Join Shared Roll` action
- Joining uses `ParticipantRepository.joinRoll(...)`, which calls the existing `join_roll()` RPC.
- After a successful join:
  - the token field is cleared
  - the roll list is refreshed from Supabase
  - the joined shared roll becomes visible to the current development identity
- The shared lobby shows the invite token only for the creator.
- Non-creators still see the same lobby and participant list, but not the invite token.

### Manual validation

With V2 enabled:

1. Launch app.
2. Select `Creator`.
3. Create a shared roll from the V2 cloud home.
4. Confirm it appears with `WAITING_FOR_PARTICIPANTS`.
5. Open the shared lobby and confirm the creator appears in the participant list.
6. Copy the invite token from either the shared-roll creation card or the creator lobby.
7. Switch to `Participant A`.
8. Paste the token into the join panel and join.
9. Confirm the shared roll becomes visible in Participant A’s cloud roll list.
10. Open the shared lobby as Participant A and confirm the participant list loads from Supabase.
11. Switch back to `Creator`, refresh, and confirm Participant A now appears in the lobby.
12. Confirm no exposure slots exist yet because Start Roll is not implemented in this phase.

### Build command executed

```text
xcodebuild -quiet -project ios/snaproll/snaproll.xcodeproj -scheme snaproll -destination 'generic/platform=iOS' -derivedDataPath /Users/zhengyu/Desktop/projects/snaproll/.deriveddata-phase11a-build CODE_SIGNING_ALLOWED=NO build
```

### Test command executed

```text
xcodebuild -quiet -project ios/snaproll/snaproll.xcodeproj -scheme snaproll -destination 'platform=iOS Simulator,id=EAC195FF-FF23-4BCF-A389-B7550AF27B53' -derivedDataPath /Users/zhengyu/Desktop/projects/snaproll/.deriveddata-tests-phase11a CODE_SIGNING_ALLOWED=NO -only-testing:snaprollTests/V2CloudHomeViewModelTests -only-testing:snaprollTests/V2SharedRollLobbyViewModelTests test
```

### Results

- full iOS build succeeded
- focused shared-lobby / cloud-home tests passed
- personal-roll V2 flow remains intact and still routes through the previous detail screens

### Assumptions / follow-up work

- This phase intentionally stops before `start_roll()`.
- Lobby refresh is manual for now; polling can be layered in later without changing the repository boundaries.
- Invite token sharing is intentionally simple and developer-oriented in this phase.
- Participant removal, leaving, delete roll, and regenerate invite remain later shared-roll management work.

## Phase 10 – V2 Personal Reveal & Gallery

### Files changed

App / V2 flow:

- `ios/snaproll/snaproll/App/V2/V2PersonalRevealGalleryView.swift`
- `ios/snaproll/snaproll/App/V2/V2PersonalRollDetailView.swift`

Repositories:

- `ios/snaproll/snaproll/Repositories/SupabaseRepositories.swift`
- `ios/snaproll/snaproll/Repositories/V2RepositoryProtocols.swift`

View models:

- `ios/snaproll/snaproll/ViewModels/V2PersonalRevealGalleryViewModel.swift`
- `ios/snaproll/snaproll/ViewModels/V2PersonalRollDetailViewModel.swift`

Tests:

- `ios/snaproll/snaprollTests/V2CloudHomeViewModelTests.swift`
- `ios/snaproll/snaprollTests/V2PersonalRevealGalleryViewModelTests.swift`
- `ios/snaproll/snaprollTests/V2PersonalRollDetailViewModelTests.swift`

Documentation:

- `v2-docs/implementation-log.md`

### Reveal flow

- Added `RollRepository.revealRoll(id:)` and live Supabase support via the `reveal_roll` RPC.
- Reveal availability is now driven by the backend-owned roll status:
  - `READY_TO_REVEAL` shows `Reveal Roll`
  - `REVEALED` shows `View Gallery`
- The V2 personal roll detail view model now:
  - invokes `reveal_roll()`
  - reloads roll metadata from Supabase
  - confirms the roll becomes `REVEALED`
- The client does not mutate reveal state locally.

### Gallery implementation

- Added a dedicated V2 personal reveal gallery screen:
  - `V2PersonalRevealGalleryView`
- Added a gallery view model that:
  - fetches the latest roll metadata
  - fetches roll exposures from Supabase
  - mirrors those exposures into the local exposure store
  - renders the gallery in `exposure_number` order
- The gallery remains intentionally minimal for this phase:
  - rendered image
  - exposure number
  - roll title
  - film stock

### Rendering pipeline integration

- Rendering stays entirely on-device.
- The gallery uses:
  - local original image
  - film stock
  - render seed
- The renderer is now called through a small abstraction so Phase 10 tests can verify the actual inputs.
- Local originals are preferred over upload artifacts:
  - `local_original_path` is used when present
  - `upload_jpeg_path` is not used for primary reveal rendering
- If rendering fails:
  - the original local image is preserved for display
  - a development diagnostic is surfaced
  - rendering can be retried by reloading the gallery

### Development diagnostics

- In development mode, the gallery can show:
  - render seed
  - sync state
  - rendering source
  - local-original availability
  - render duration
  - local original path
- These diagnostics remain hidden outside development mode.

### Manual validation expectations

With V2 enabled:

1. Create and start a V2 personal roll.
2. Capture and sync every exposure.
3. Confirm the backend roll reaches `READY_TO_REVEAL`.
4. Open the roll detail and press `Reveal Roll`.
5. Confirm the backend row becomes `REVEALED`.
6. Confirm the V2 gallery opens.
7. Confirm the displayed order matches `exposure_number`.
8. Confirm the gallery renders from local originals rather than upload copies.
9. If development diagnostics are enabled, confirm render seed and source metadata are visible.

### Build command executed

```text
xcodebuild -quiet -project ios/snaproll/snaproll.xcodeproj -scheme snaproll -destination 'generic/platform=iOS' -derivedDataPath /Users/zhengyu/Desktop/projects/snaproll/.deriveddata-phase10-build CODE_SIGNING_ALLOWED=NO build
```

```text
xcodebuild -quiet -project ios/snaproll/snaproll.xcodeproj -scheme snaproll -destination 'platform=iOS Simulator,id=EAC195FF-FF23-4BCF-A389-B7550AF27B53' -derivedDataPath /Users/zhengyu/Desktop/projects/snaproll/.deriveddata-tests-phase10 CODE_SIGNING_ALLOWED=NO build-for-testing
```

### Test command executed

```text
xcodebuild -quiet -project ios/snaproll/snaproll.xcodeproj -scheme snaproll -destination 'platform=iOS Simulator,id=EAC195FF-FF23-4BCF-A389-B7550AF27B53' -derivedDataPath /Users/zhengyu/Desktop/projects/snaproll/.deriveddata-tests-phase10 CODE_SIGNING_ALLOWED=NO -only-testing:snaprollTests/V2PersonalRollDetailViewModelTests -only-testing:snaprollTests/V2PersonalRevealGalleryViewModelTests -only-testing:snaprollTests/V2ExposureSyncRunnerTests -only-testing:snaprollTests/V2ExposureUploadPipelineTests -only-testing:snaprollTests/V2ExposureMetadataCompletionPipelineTests -only-testing:snaprollTests/V2LocalCapturePipelineTests test-without-building
```

### Results

- full iOS build succeeded
- focused Phase 10 reveal/gallery tests passed
- existing dependent Phase 9 sync/capture tests still passed

### Assumptions / follow-up work

- This phase does not add cloud download fallback for missing originals.
- The gallery is intentionally simple and not yet the final production gallery design.
- Shared reveal/gallery remains a later phase and should reuse this local-first render path.

## Phase 9C – V2 Automatic Sync Runner, Retry & Recovery

### Files changed

App / V2 flow:

- `ios/snaproll/snaproll/App/V2/V2CaptureView.swift`
- `ios/snaproll/snaproll/App/V2/V2PersonalRollDetailView.swift`

Repositories:

- `ios/snaproll/snaproll/Repositories/V2LocalExposureMirrorStore.swift`

Services:

- `ios/snaproll/snaproll/Services/V2ExposureMetadataCompletionPipeline.swift`
- `ios/snaproll/snaproll/Services/V2ExposureSyncRunner.swift`
- `ios/snaproll/snaproll/Services/V2ExposureUploadPipeline.swift`

View models:

- `ios/snaproll/snaproll/ViewModels/V2PersonalRollDetailViewModel.swift`

Tests:

- `ios/snaproll/snaprollTests/V2ExposureSyncRunnerTests.swift`
- `ios/snaproll/snaprollTests/V2PersonalRollDetailViewModelTests.swift`

Documentation:

- `v2-docs/implementation-log.md`

### Automatic sync runner

- Added `V2ExposureSyncRunner` as the single orchestration layer for post-capture synchronization.
- The runner processes mirrored exposures sequentially in exposure-number order.
- It owns the full local sync progression:

```text
LOCAL_ONLY
→ upload JPEG to Storage
→ METADATA_PENDING
→ complete_exposure(...)
→ SYNCED
```

- The camera no longer kicks off upload/metadata work directly.
- The V2 personal roll detail flow now triggers the same runner when:
  - the roll detail first appears
  - the user returns from `V2CaptureView`
  - the app becomes active again while the roll detail is open

### Retry and recovery behavior

- Retry is now state-aware:
  - `LOCAL_ONLY` / `UPLOADING`
    - rerun upload, then metadata completion
  - `METADATA_PENDING`
    - rerun metadata completion only
  - `FAILED` with `cloud_storage_path`
    - skip upload and retry metadata only
  - `FAILED` without `cloud_storage_path`
    - restart from upload
- Failures no longer stop the whole queue.
- The runner marks failed exposures with:
  - `sync_state = FAILED`
  - `last_error`
- Fixed the local mirror merge logic so restart recovery preserves locally known:
  - `cloud_storage_path`
  - `uploaded_at`
  - pending error context
- This closes the earlier recovery gap where a successfully uploaded file could survive app restart while the local mirror forgot that upload had already happened.

### V2 UI / diagnostics changes

- Replaced the old manual debug actions:
  - `Upload Pending Exposures`
  - `Complete Pending Metadata`
- Added runner-backed development actions:
  - `Process Pending Exposures`
  - `Retry Failed Sync`
  - `Force Refresh`
- All three development actions now route through the same Phase 9C orchestration path.
- Normal mode now surfaces only lightweight sync messaging such as:
  - `Uploading…`
  - `Syncing…`
  - `Waiting for upload…`
  - `Ready to Reveal`
- The capture screen now waits until the user leaves the camera flow before invoking the roll-detail sync callback.

### Manual validation expectations

With V2 enabled:

1. Create and start a V2 personal roll.
2. Capture one or more exposures.
3. Return from the capture screen.
4. Confirm the roll detail begins syncing automatically.
5. Confirm development diagnostics update exposure states from:
   - `LOCAL_ONLY`
   - to `METADATA_PENDING`
   - to `SYNCED`
6. Kill and relaunch the app with an exposure mid-sync.
7. Reopen the roll and confirm the runner resumes from the persisted local state instead of starting over incorrectly.
8. In development mode, use:
   - `Retry Failed Sync`
   - `Process Pending Exposures`
   - `Force Refresh`
   and confirm they all drive the same queue.

### Build command executed

```text
xcodebuild -quiet -project ios/snaproll/snaproll.xcodeproj -scheme snaproll -destination 'generic/platform=iOS' -derivedDataPath /Users/zhengyu/Desktop/projects/snaproll/.deriveddata-phase9c-build CODE_SIGNING_ALLOWED=NO build
```

```text
xcodebuild -quiet -project ios/snaproll/snaproll.xcodeproj -scheme snaproll -destination 'platform=iOS Simulator,id=EAC195FF-FF23-4BCF-A389-B7550AF27B53' -derivedDataPath /Users/zhengyu/Desktop/projects/snaproll/.deriveddata-tests-phase9c CODE_SIGNING_ALLOWED=NO build-for-testing
```

### Test command executed

```text
xcodebuild -quiet -project ios/snaproll/snaproll.xcodeproj -scheme snaproll -destination 'platform=iOS Simulator,id=EAC195FF-FF23-4BCF-A389-B7550AF27B53' -derivedDataPath /Users/zhengyu/Desktop/projects/snaproll/.deriveddata-tests-phase9c CODE_SIGNING_ALLOWED=NO -only-testing:snaprollTests/V2ExposureUploadPipelineTests -only-testing:snaprollTests/V2ExposureMetadataCompletionPipelineTests -only-testing:snaprollTests/V2ExposureSyncRunnerTests -only-testing:snaprollTests/V2PersonalRollDetailViewModelTests -only-testing:snaprollTests/V2LocalCapturePipelineTests test-without-building
```

### Results

- full iOS build succeeded
- focused Phase 9 sync/capture/detail tests passed
- automatic sync now compiles and is covered by dedicated retry/recovery tests

### Assumptions / follow-up work

- This phase still runs sync when the roll detail is foregrounded, not as a background task or long-lived daemon.
- Upload progress is represented at the exposure-state level, not as byte-level progress.
- Background scheduling, polling, and broader offline hardening remain future work.

## Phase 9B – V2 Metadata Completion with `complete_exposure()`

### Files changed

App / V2 flow:

- `ios/snaproll/snaproll/App/V2/V2PersonalRollDetailView.swift`

Repositories:

- `ios/snaproll/snaproll/Repositories/SupabaseRepositories.swift`
- `ios/snaproll/snaproll/Repositories/V2RepositoryProtocols.swift`

Services:

- `ios/snaproll/snaproll/Services/V2ExposureMetadataCompletionPipeline.swift`

View models:

- `ios/snaproll/snaproll/ViewModels/V2PersonalRollDetailViewModel.swift`

Tests:

- `ios/snaproll/snaprollTests/V2ExposureMetadataCompletionPipelineTests.swift`
- `ios/snaproll/snaprollTests/V2PersonalRollDetailViewModelTests.swift`

Documentation:

- `v2-docs/implementation-log.md`

### `complete_exposure()` integration

- Added a dedicated second-half sync service:
  - `V2ExposureMetadataCompletionPipeline`
- The metadata completion pipeline is separate from upload and only processes mirrored exposures with:
  - `sync_state = METADATA_PENDING`
  - non-empty `cloud_storage_path`
- Added repository support for the backend-owned transition:
  - `ExposureRepository.completeExposure(id:storagePath:)`
  - live implementation calls the approved `complete_exposure` RPC
- This phase does not:
  - re-upload images
  - generate a new upload JPEG
  - delete Storage objects on failure

### Local state transitions

- Successful metadata completion path:

```text
METADATA_PENDING
→ complete_exposure(...)
→ SYNCED
```

- On success, the mirrored exposure keeps:
  - `cloud_storage_path`
  - `uploaded_at`
  - `upload_jpeg_path`
- On success, the mirrored exposure updates:
  - `sync_state = SYNCED`
  - `last_error = nil`
  - `updated_at`

- On metadata completion failure:
  - the uploaded Storage object is left untouched
  - the mirrored exposure remains retryable in:
    - `METADATA_PENDING`
  - the mirrored exposure records:
    - `last_error`
    - updated timestamp

### Backend refresh behavior

- After metadata completion runs from the V2 personal roll detail screen, the view model reloads:
  - roll metadata from `RollRepository.fetchRoll(id:)`
  - cloud exposures from `ExposureRepository.fetchExposures(forRollID:)`
  - the mirrored local exposure state via `ExposureMirrorStore.mirrorCloudExposures(...)`
- This lets the UI reflect backend-owned lifecycle changes such as:
  - participant finishing
  - roll moving to `READY_TO_REVEAL`
- Development diagnostics now surface:
  - metadata completion action
  - metadata completion result message
  - `last_error` when metadata completion fails

### Manual validation performed

- Verified build-for-testing succeeds with the new Phase 9B code path.
- Verified the previously failing metadata-failure path test passes when run after build-for-testing using `test-without-building`.
- The broader focused Phase 9 test group had already passed except for that single failure-path test before the final fixture correction.

### Build command executed

```text
xcodebuild -quiet -project ios/snaproll/snaproll.xcodeproj -scheme snaproll -destination 'generic/platform=iOS' -derivedDataPath /Users/zhengyu/Desktop/projects/snaproll/.deriveddata-phase9b-build CODE_SIGNING_ALLOWED=NO build
```

```text
xcodebuild -quiet -project ios/snaproll/snaproll.xcodeproj -scheme snaproll -destination 'platform=iOS Simulator,id=EAC195FF-FF23-4BCF-A389-B7550AF27B53' -derivedDataPath /Users/zhengyu/Desktop/projects/snaproll/.deriveddata-tests-phase9b CODE_SIGNING_ALLOWED=NO build-for-testing
```

### Test commands executed

```text
xcodebuild -quiet -project ios/snaproll/snaproll.xcodeproj -scheme snaproll -destination 'platform=iOS Simulator,id=EAC195FF-FF23-4BCF-A389-B7550AF27B53' -derivedDataPath /Users/zhengyu/Desktop/projects/snaproll/.deriveddata-tests-phase9b CODE_SIGNING_ALLOWED=NO -only-testing:snaprollTests/V2ExposureUploadPipelineTests -only-testing:snaprollTests/V2ExposureMetadataCompletionPipelineTests -only-testing:snaprollTests/V2PersonalRollDetailViewModelTests test
```

```text
xcodebuild -quiet -project ios/snaproll/snaproll.xcodeproj -scheme snaproll -destination 'platform=iOS Simulator,id=EAC195FF-FF23-4BCF-A389-B7550AF27B53' -derivedDataPath /Users/zhengyu/Desktop/projects/snaproll/.deriveddata-tests-phase9b CODE_SIGNING_ALLOWED=NO -only-testing:snaprollTests/V2PersonalRollDetailViewModelTests/metadataCompletionFailurePreservesMetadataPendingState test-without-building
```

### Results

- full iOS build succeeded
- build-for-testing succeeded
- new metadata completion pipeline compiles cleanly
- the focused Phase 9 test suite initially exposed a failure-path fixture bug in the V2 personal roll detail test
- after correcting that fixture to match the real backend failure shape (`storage_path` remains null when `complete_exposure()` fails), the targeted failure-path test passed with `test-without-building`

### Assumptions / follow-up work

- Phase 9B assumes:
  - the upload phase has already written the canonical Storage object
  - `cloud_storage_path` is already present locally
- This phase still does not add:
  - retry scheduler / background worker
  - app restart recovery
  - reveal UI
  - shared-roll sync behavior
- A later hardening phase should unify upload + metadata completion under a more explicit sync orchestrator once retry / recovery / polling are added.

## Phase 9A Follow-Up – Storage Bucket & Policies

- Added migration:
  - `supabase/migrations/20260708133000_phase_9a_storage_bucket_and_policies.sql`
- What it provisions:
  - private Storage bucket:
    - `snaproll-originals`
  - helper-based Storage access checks:
    - `public.can_upload_snaproll_original(...)`
    - `public.can_read_snaproll_original(...)`
  - authenticated Storage grants for:
    - `storage.buckets`
    - `storage.objects`
  - Storage policies for:
    - reading the `snaproll-originals` bucket metadata
    - uploading only to the caller's own canonical pending-exposure path
    - reading originals only after a roll reaches `REVEALED`
- Why this was needed:
  - Phase 9A app uploads were in place, but Supabase Storage had not yet been provisioned, so uploads failed with:
    - `Bucket not found`
- Canonical upload contract enforced by the policy:
  - `rolls/{roll_id}/participants/{participant_id}/001.jpg`
  - padded three-digit exposure filenames are required
  - only JPEG paths are accepted
- Security / architecture notes:
  - the bucket remains private
  - no update or delete object policies were added in this phase
  - upload checks run through security-definer helpers so the policy layer does not repeat the earlier recursive RLS pattern
  - object reads remain blocked until the roll is `REVEALED`, preserving the hidden-film product rule at the backend layer too

## Phase 9A – V2 Upload Pipeline (JPEG Generation + Storage Upload)

### Files changed

App / V2 flow:

- `ios/snaproll/snaproll/App/V2/V2DependencyContainer.swift`
- `ios/snaproll/snaproll/App/V2/V2PersonalRollDetailView.swift`

Repositories:

- `ios/snaproll/snaproll/Repositories/SupabaseRepositories.swift`
- `ios/snaproll/snaproll/Repositories/V2RepositoryProtocols.swift`

Services:

- `ios/snaproll/snaproll/Services/PhotoStorageService.swift`
- `ios/snaproll/snaproll/Services/V2ExposureUploadPipeline.swift`

View models:

- `ios/snaproll/snaproll/ViewModels/V2PersonalRollDetailViewModel.swift`

Tests:

- `ios/snaproll/snaprollTests/V2ExposureUploadPipelineTests.swift`

Utilities:

- `ios/snaproll/snaproll/Utilities/AppConfig.swift`

Documentation:

- `v2-docs/implementation-log.md`

### Upload pipeline

- Added a dedicated V2 upload synchronization service:
  - `V2ExposureUploadPipeline`
- The upload pipeline is separate from capture and only processes mirrored exposures with:
  - `sync_state = LOCAL_ONLY`
- The service now:
  1. loads pending local exposures in exposure-number order
  2. verifies the local original exists
  3. marks the exposure `UPLOADING`
  4. generates a canonical JPEG upload copy locally
  5. uploads that JPEG to Supabase Storage
  6. records upload metadata locally
  7. transitions the exposure to `METADATA_PENDING`
- This phase still does not:
  - call `complete_exposure()`
  - mark the cloud exposure complete
  - advance the roll lifecycle

### JPEG generation

- Extended `PhotoStorageService` so V2 can:
  - read local original data
  - normalize image orientation for upload
  - generate a JPEG upload copy without mutating the original capture
  - persist the local upload JPEG copy separately
- The original local capture remains untouched in `local_original_path`.
- The upload artifact is stored separately in `upload_jpeg_path`.

### Canonical storage layout

- Added a dedicated storage boundary:
  - `ExposureAssetStorageRepository`
  - `SupabaseExposureAssetStorageRepository`
- Live uploads now use the agreed bucket:
  - `snaproll-originals`
- Live uploads now use the agreed canonical padded path:
  - `rolls/{roll_id}/participants/{participant_id}/001.jpg`
- The upload pipeline uses `LocalExposure.canonicalCloudStoragePath`, so the padded numbering rule remains centralized.

### Local state transitions

- Successful upload path:

```text
LOCAL_ONLY
→ UPLOADING
→ METADATA_PENDING
```

- On successful upload, the mirrored exposure records:
  - `upload_jpeg_path`
  - `cloud_storage_path`
  - `uploaded_at`
  - `sync_state = METADATA_PENDING`

- On upload failure:
  - the original local capture is preserved
  - `last_error` is recorded
  - the exposure returns to `LOCAL_ONLY`
  - the exposure remains retryable by a future Phase 9 retry pass

### Development visibility

- In development diagnostics, the V2 personal roll detail screen can now show:
  - upload button for pending local exposures
  - upload JPEG existence
  - upload JPEG local path
  - cloud storage path
  - uploaded timestamp
- This remains behind the existing debug visibility path.
- Normal hidden-film behavior remains unchanged outside development diagnostics.

### Manual validation

With V2 bootstrap and development auth enabled:

1. Launch the app.
2. Select a development identity.
3. Create and start a V2 personal roll.
4. Capture one or more exposures so they become `LOCAL_ONLY`.
5. Open the V2 personal roll detail screen.
6. In development diagnostics, press `Upload Pending Exposures`.
7. Confirm:
   - local upload JPEGs are created
   - exposure paths use padded numbering
   - files appear in the `snaproll-originals` bucket
   - local exposures transition to `METADATA_PENDING`
8. Confirm cloud exposure rows are still incomplete because `complete_exposure()` is not called in this phase.

### Build command executed

```text
xcodebuild -quiet -project ios/snaproll/snaproll.xcodeproj -scheme snaproll -destination 'generic/platform=iOS' -derivedDataPath /Users/zhengyu/Desktop/projects/snaproll/.deriveddata CODE_SIGNING_ALLOWED=NO build
```

### Test commands executed

```text
xcodebuild -quiet -project ios/snaproll/snaproll.xcodeproj -scheme snaproll -destination 'platform=iOS Simulator,id=EAC195FF-FF23-4BCF-A389-B7550AF27B53' -derivedDataPath /Users/zhengyu/Desktop/projects/snaproll/.deriveddata-tests CODE_SIGNING_ALLOWED=NO -only-testing:snaprollTests/V2PersonalRollDetailViewModelTests -only-testing:snaprollTests/V2LocalCapturePipelineTests -only-testing:snaprollTests/V2ImageSourceProviderTests -only-testing:snaprollTests/V2CloudHomeViewModelTests -only-testing:snaprollTests/V2ExposureUploadPipelineTests test
```

```text
xcodebuild -project ios/snaproll/snaproll.xcodeproj -scheme snaproll -destination 'platform=iOS Simulator,id=EAC195FF-FF23-4BCF-A389-B7550AF27B53' -derivedDataPath /Users/zhengyu/Desktop/projects/snaproll/.deriveddata-tests-phase9a CODE_SIGNING_ALLOWED=NO -only-testing:snaprollTests/V2ExposureUploadPipelineTests test
```

### Results

- full iOS build succeeded
- the new upload pipeline compiles cleanly as part of the app target
- the simulator test runs were started and progressed through cold package/test-bundle build setup, but the Xcode test harness did not complete within the session window after rebuilding dependencies and test bundles from scratch

### Assumptions / follow-up work

- The follow-up Storage migration now provisions the `snaproll-originals` bucket and its initial policies.
- Phase 9B should build directly on this state by:
  - calling `complete_exposure()`
  - transitioning `METADATA_PENDING → SYNCED`
  - adding retry and recovery behavior
  - keeping capture fully local-first
  - avoiding duplicate metadata completion calls

## Phase 8C – V2 Development Visibility & Simulator Capture Hardening

### Files changed

App / V2 flow:

- `ios/snaproll/snaproll/App/V2/V2CloudHomeView.swift`
- `ios/snaproll/snaproll/App/V2/V2PersonalRollDetailView.swift`

View models:

- `ios/snaproll/snaproll/ViewModels/V2PersonalRollDetailViewModel.swift`

Tests:

- `ios/snaproll/snaprollTests/V2ImageSourceProviderTests.swift`
- `ios/snaproll/snaprollTests/V2PersonalRollDetailViewModelTests.swift`

Documentation:

- `v2-docs/implementation-log.md`

### Debug visibility behavior

- Completed the remaining Phase 8C diagnostics on the V2 personal roll detail surface instead of creating a separate debug screen.
- When `AppConfig.V2.isExposureDiagnosticsEnabled` is enabled, the V2 roll detail now shows:
  - active development identity
  - roll id
  - roll status
  - captured count
  - remaining count
  - per-exposure local diagnostics already added in Phase 8B
- When diagnostics are disabled, those details remain fully hidden and the roll detail falls back to film-style progress only.

### Simulator / dev capture support

- The existing `DevelopmentSampleImageSourceProvider` remains the simulator-safe image source for V2 capture testing.
- Added explicit test coverage proving it returns non-empty, decodable image data.
- The capture pipeline itself remains unchanged:
  - image source provider
  - next empty mirrored exposure
  - local original persistence
  - `LOCAL_ONLY`

### How to manually validate Phase 8C

With V2 bootstrap and development auth enabled:

1. Launch the app in a debug build.
2. Select a development identity from the V2 cloud home screen.
3. Create and start a V2 personal roll.
4. Open the roll detail.
5. Confirm the development diagnostics panel now clearly shows:
   - active identity
   - roll id
   - roll status
   - captured / remaining counts
6. Capture on simulator using the development sample provider.
7. Confirm captured exposures continue to show:
   - `LOCAL_ONLY`
   - local file exists
   - local file path
   - capture timestamp
   - thumbnail preview in development mode only
8. Disable exposure diagnostics and confirm the same roll detail hides the diagnostic metadata and thumbnails.

### Build command executed

```text
xcodebuild -quiet -project ios/snaproll/snaproll.xcodeproj -scheme snaproll -destination 'generic/platform=iOS' -derivedDataPath /Users/zhengyu/Desktop/projects/snaproll/.deriveddata CODE_SIGNING_ALLOWED=NO build
```

### Test command executed

```text
xcodebuild -quiet -project ios/snaproll/snaproll.xcodeproj -scheme snaproll -destination 'platform=iOS Simulator,id=EAC195FF-FF23-4BCF-A389-B7550AF27B53' -derivedDataPath /Users/zhengyu/Desktop/projects/snaproll/.deriveddata-tests CODE_SIGNING_ALLOWED=NO -only-testing:snaprollTests/V2PersonalRollDetailViewModelTests -only-testing:snaprollTests/V2LocalCapturePipelineTests -only-testing:snaprollTests/V2ImageSourceProviderTests -only-testing:snaprollTests/V2CloudHomeViewModelTests test
```

### Results

- full iOS build succeeded
- targeted Phase 8A/8B/8C V2 tests passed on simulator

### Assumptions / follow-up work

- The V2 roll detail diagnostics remain intentionally developer-facing and are not final product UI.
- Phase 9 should continue from the current local-first behavior by introducing upload state transitions without weakening the hidden-film behavior in normal mode.

## Phase 8B – V2 Local Capture Pipeline

### Files changed

App / V2 flow:

- `ios/snaproll/snaproll/App/V2/V2CaptureView.swift`
- `ios/snaproll/snaproll/App/V2/V2DependencyContainer.swift`
- `ios/snaproll/snaproll/App/V2/V2PersonalRollDetailView.swift`

View models:

- `ios/snaproll/snaproll/ViewModels/V2CaptureViewModel.swift`
- `ios/snaproll/snaproll/ViewModels/V2PersonalRollDetailViewModel.swift`

Services / capture pipeline:

- `ios/snaproll/snaproll/Services/PhotoStorageService.swift`
- `ios/snaproll/snaproll/Services/V2ImageSourceProviders.swift`
- `ios/snaproll/snaproll/Services/V2LocalCapturePipeline.swift`

Repositories / local mirror:

- `ios/snaproll/snaproll/Repositories/V2LocalExposureMirrorStore.swift`
- `ios/snaproll/snaproll/Repositories/V2RepositoryProtocols.swift`

Tests:

- `ios/snaproll/snaprollTests/V2CloudHomeViewModelTests.swift`
- `ios/snaproll/snaprollTests/V2LocalCapturePipelineTests.swift`
- `ios/snaproll/snaprollTests/V2PersonalRollDetailViewModelTests.swift`

Documentation:

- `v2-docs/implementation-log.md`

### What changed

- Added an `ImageSourceProvider` abstraction so V2 local capture does not depend directly on one concrete input mechanism.
- Added two provider implementations:
  - `DeviceCameraImageSourceProvider`
  - `DevelopmentSampleImageSourceProvider`
- Added a V2-only local capture pipeline that:
  - fetches the next empty mirrored exposure
  - captures image data from the selected provider
  - saves the original image locally without upload
  - marks the exposure `LOCAL_ONLY`
  - persists the updated mirrored exposure
- Added a minimal V2 capture screen reachable from the V2 personal roll detail screen.

### ImageSourceProvider

- `ImageSourceProvider` is now the boundary between the V2 capture flow and the actual image source.
- The V2 pipeline only asks the provider for a captured image payload:
  - raw image data
  - file extension
- Provider implementations:
  - `DeviceCameraImageSourceProvider`
    - wraps the existing `CameraService`
    - prepares camera authorization and preview
    - returns captured device-camera data as the local original
  - `DevelopmentSampleImageSourceProvider`
    - generates a deterministic development sample image
    - allows simulator/manual testing without camera hardware

### Local capture pipeline

- `V2LocalCapturePipeline.captureNextExposure(...)` is now the core Phase 8B workflow.
- Capture flow:
  1. ask the selected `ImageSourceProvider` for image data
  2. load local mirrored exposures for the roll
  3. select the next empty exposure only
  4. save the original image locally
  5. set:
     - `local_original_path`
     - `captured_at`
     - `sync_state = LOCAL_ONLY`
     - `updated_at`
  6. persist the updated mirrored exposure
- This phase still does not:
  - upload
  - create JPEG upload copies
  - call `complete_exposure()`
  - touch Supabase Storage

### Local persistence

- Added `PhotoStorageService.saveOriginalImageData(...)` for V2 local-original persistence.
- Unlike the older V1 helper, this path stores the captured original bytes directly and does not generate a JPEG upload artifact.
- The local exposure mirror store now supports `saveExposure(_:)` so captured local state survives leaving and reopening the roll.

### Sequential exposure filling

- Captures always fill the next available empty mirrored exposure in exposure-number order.
- Previously captured exposures are not overwritten.
- If no empty exposure remains, the V2 pipeline throws a local business error instead of reusing a filled slot.

### Development diagnostics

- The V2 personal roll detail screen now shows richer diagnostics when `AppConfig.V2.isExposureDiagnosticsEnabled` is enabled:
  - exposure number
  - sync state
  - local file exists
  - local file path
  - capture timestamp
  - optional thumbnail preview
- The V2 capture screen also exposes a debug-only source picker when multiple providers are available.

### Manual validation

With V2 bootstrap and development auth enabled:

1. Launch the app.
2. Select the Creator development identity.
3. Create and start a V2 personal roll.
4. Open the roll detail.
5. Press `Capture Next Exposure`.
6. On device:
   - use the device camera provider
7. On simulator or in debug testing:
   - use the development sample provider
8. Confirm each capture fills the next empty exposure only.
9. Confirm progress updates from local mirrored exposures.
10. Confirm captured exposures become `LOCAL_ONLY`.
11. Confirm local original files exist on disk.
12. Confirm no upload occurs.
13. Confirm normal hidden-film mode still hides captured images when diagnostics are disabled.

### Build command executed

```text
xcodebuild -quiet -project ios/snaproll/snaproll.xcodeproj -scheme snaproll -destination 'generic/platform=iOS' -derivedDataPath /Users/zhengyu/Desktop/projects/snaproll/.deriveddata CODE_SIGNING_ALLOWED=NO build
```

### Test command executed

```text
xcodebuild -quiet -project ios/snaproll/snaproll.xcodeproj -scheme snaproll -destination 'platform=iOS Simulator,id=EAC195FF-FF23-4BCF-A389-B7550AF27B53' -derivedDataPath /Users/zhengyu/Desktop/projects/snaproll/.deriveddata-tests CODE_SIGNING_ALLOWED=NO -only-testing:snaprollTests/V2PersonalRollDetailViewModelTests -only-testing:snaprollTests/V2LocalCapturePipelineTests -only-testing:snaprollTests/V2CloudHomeViewModelTests test
```

### Results

- full iOS build succeeded
- targeted Phase 8A/8B V2 test coverage passed on simulator
- new passing coverage includes:
  - start roll fetch/mirror flow
  - reopening does not duplicate mirrored exposures
  - progress starts at zero captured
  - diagnostics visibility rules
  - image-source provider integration
  - next empty exposure selection
  - local-original persistence
  - `LOCAL_ONLY` assignment
  - sequential filling
  - no overwrite of existing exposures

### Assumptions / follow-up work

- The development image provider currently uses a generated sample image rather than a photo picker. This keeps the Phase 8B source abstraction simple while still satisfying simulator/development testing.
- The V2 capture screen is intentionally minimal and debug-oriented, not final product UI.
- Phase 9 should build on this by:
  - generating upload JPEG copies
  - moving `LOCAL_ONLY` exposures through upload/sync states
  - calling `complete_exposure()`
  - preserving offline-first capture while sync runs in the background

## Phase 8A – V2 Personal Roll Start & Exposure Slot Mirroring

### Files changed

App / V2 flow:

- `ios/snaproll/snaproll/App/V2/V2CloudHomeView.swift`
- `ios/snaproll/snaproll/App/V2/V2DependencyContainer.swift`
- `ios/snaproll/snaproll/App/V2/V2PersonalRollDetailView.swift`

Repositories / local mirror:

- `ios/snaproll/snaproll/Repositories/SupabaseRepositories.swift`
- `ios/snaproll/snaproll/Repositories/V2LocalExposureMirrorStore.swift`
- `ios/snaproll/snaproll/Repositories/V2RepositoryProtocols.swift`

View models / config:

- `ios/snaproll/snaproll/ViewModels/V2PersonalRollDetailViewModel.swift`
- `ios/snaproll/snaproll/Utilities/AppConfig.swift`

Tests:

- `ios/snaproll/snaprollTests/V2CloudHomeViewModelTests.swift`
- `ios/snaproll/snaprollTests/V2PersonalRollDetailViewModelTests.swift`

Documentation:

- `v2-docs/implementation-log.md`

### What changed

- Added a minimal V2 personal roll detail screen reachable from the V2 cloud roll list.
- Added `RollRepository.startRoll(id:)` and wired the live repository to the backend `start_roll()` RPC.
- Added a local exposure mirror store that persists mirrored exposure-slot records to a V2-specific JSON file.
- After a roll starts, the client now:
  - reloads roll metadata from cloud
  - fetches backend-created exposure slots
  - mirrors those slots into the local exposure model
  - derives progress from the local mirrored exposures

### Start roll implementation

- `V2PersonalRollDetailViewModel.startRoll()` calls `RollRepository.startRoll(id:)`.
- The live repository calls the existing backend `start_roll()` RPC.
- The backend remains authoritative for:
  - creating exposure slots
  - transitioning the roll into `SHOOTING`
- The client never generates exposure slots itself.

### Exposure slot mirroring

- After start, the detail view model fetches all cloud exposure rows for the roll through `ExposureRepository.fetchExposures(forRollID:)`.
- Those cloud exposures are passed into `FileBackedExposureMirrorStore.mirrorCloudExposures(...)`.
- The mirror store reconciles by cloud exposure `id` so each cloud exposure has exactly one local mirrored exposure record.
- The mirrored records currently store:
  - exposure id
  - roll id
  - participant id
  - exposure number
  - render seed
  - local/original/upload/rendered paths
  - sync state
  - timestamps

### Local mirror lifecycle

- Before start:
  - the roll detail shows roll metadata and zero mirrored exposures
- After start:
  - the cloud exposure list is mirrored locally
  - progress reads from that local mirrored list
- On reopen:
  - the roll metadata reloads from cloud
  - started rolls refetch cloud exposures
  - the mirror store replaces/reconciles by exposure id instead of appending duplicates
- This phase intentionally does not:
  - capture photos
  - generate JPEG upload copies
  - upload to Storage
  - call `complete_exposure()`
  - reveal photos

### Development diagnostics

- Added a development-only diagnostics section on the V2 personal roll detail screen.
- When `AppConfig.V2.isExposureDiagnosticsEnabled` is enabled, the detail view may show:
  - exposure number
  - local sync state
  - cloud exposure id
  - render seed
- No thumbnails or capture diagnostics are shown in this phase.

### Manual validation

With V2 session bootstrap and development auth enabled:

1. Launch app.
2. Select the Creator development identity.
3. Create a V2 personal roll.
4. Open the roll detail.
5. Press `Start Roll`.
6. Confirm the roll status becomes `SHOOTING`.
7. Confirm exposure slots exist in Supabase.
8. Confirm local mirrored exposure records are created.
9. Confirm progress shows `0 / N captured`.
10. Close and reopen the roll.
11. Confirm mirrored exposure records are reused rather than duplicated.

### Build command executed

```text
xcodebuild -quiet -project ios/snaproll/snaproll.xcodeproj -scheme snaproll -destination 'generic/platform=iOS' -derivedDataPath /Users/zhengyu/Desktop/projects/snaproll/.deriveddata CODE_SIGNING_ALLOWED=NO build
```

### Test commands executed

```text
xcodebuild -quiet -project ios/snaproll/snaproll.xcodeproj -scheme snaproll -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /Users/zhengyu/Desktop/projects/snaproll/.deriveddata-tests CODE_SIGNING_ALLOWED=NO -only-testing:snaprollTests test
```

```text
xcodebuild -quiet -project ios/snaproll/snaproll.xcodeproj -scheme snaproll -destination 'platform=iOS Simulator,id=EAC195FF-FF23-4BCF-A389-B7550AF27B53' -derivedDataPath /Users/zhengyu/Desktop/projects/snaproll/.deriveddata-tests CODE_SIGNING_ALLOWED=NO -only-testing:snaprollTests test
```

### Results

- full iOS build succeeded
- new Phase 8A code compiled successfully
- unit-test execution was interrupted by the simulator environment before completion:
  - Xcode could build the tests
  - the simulator test session later failed to launch the app cleanly and reported `server died` / `TEST INTERRUPTED`

### Assumptions / follow-up work

- The local exposure mirror is persisted through a V2-specific local JSON file for this phase so the working copy survives reopening the roll without requiring the Phase 9 sync engine.
- This keeps V1 behavior untouched and avoids prematurely wiring capture or upload logic into the V2 path.
- Phase 8B should build on this mirror as the client-side working copy for local capture.
- A later phase can replace the mirror-store persistence layer with the planned SwiftData-backed local repository once the broader V2 local data path is integrated.

## Documentation Update – Phase 8 Local-First Shooting vs Phase 9 Upload/Sync

- Clarified that Phase 8 is local-first personal-roll shooting only:
  - start personal roll through the V2 cloud lifecycle
  - fetch cloud-created exposure slots
  - mirror them into the local exposure model
  - capture locally into the next empty exposure
  - persist local originals without uploading
- Clarified that Phase 9 owns networked upload and sync responsibilities:
  - JPEG upload copy generation
  - Supabase Storage upload
  - `complete_exposure()` RPC
  - retry logic
  - metadata-pending recovery
- Recorded the architectural rule that captures must not block on network and Phase 8 must not directly perform uploads.
- Documented that debug visibility for hidden photos is allowed only behind a development-only flag.
- Reaffirmed that normal user-mode hidden-film behavior remains mandatory until reveal.

## Documentation Update – Roadmap and Authentication Strategy

- Reordered the V2 implementation roadmap to reflect the approved sequence from Phase 0 through Phase 16.
- Added a Development Authentication strategy to the architecture:
  - authentication remains provider-agnostic
  - `AuthRepository` remains the only auth boundary
  - shared-roll features depend on `AuthRepository`, not directly on Google Sign-In or Apple Sign In
- Deferred production authentication to the later production-auth phase:
  - Google Sign-In initially
  - Apple Sign In before App Store release
- Rationale:
  - faster product iteration
  - easier manual testing
  - avoids blocking development on Apple Developer Program enrollment
  - preserves clean architecture

## Documentation Update – Personal Roll First Strategy

- Recorded Phase 6 as completed Development Authentication.
- Documented that user-scoped roll ownership is not yet enforced in the visible V2 UI/data flow.
- Reordered the roadmap so Phase 7 now becomes V2 Cloud Personal Roll Foundation.
- Documented that V2 must first prove:
  - current-user ownership
  - cloud-backed personal roll creation
  - personal roll shooting, upload, reveal, and gallery
- Deferred shared-roll implementation until after the V2 personal-roll pipeline is proven.
- Rationale:
  - personal rolls are the core Snaproll experience
  - shared rolls extend the personal-roll pipeline
  - multi-user complexity should reuse a proven cloud-backed personal flow
  - this reduces migration risk while preserving V1 behind the feature flag

## Phase 6 Follow-Up – `ensure_profile()` Ambiguity Fix

- Added migration:
  - `supabase/migrations/20260707114500_phase_6_ensure_profile_ambiguity_fix.sql`
- Root cause:
  - `ensure_profile()` uses `RETURNS TABLE (id, display_name)`, which creates PL/pgSQL output variables named `id` and `display_name`
  - that makes later SQL edits fragile because unqualified references to those names can become ambiguous between output variables and table columns
- Fix applied:
  - kept the RPC signature unchanged for the iOS client
  - rewrote the function to upsert into `public.profiles`, capture the row with `RETURNING ... INTO`, and assign output values explicitly
  - replaced `on conflict (id)` with `on conflict on constraint profiles_pkey` to avoid relying on a bare `id` identifier inside the conflict target
- Impact:
  - Phase 6 bootstrap can continue calling `ensure_profile()` without app-side changes
  - this closes the same class of ambiguity bug previously seen in Phase 2 RPC work

## Phase 7 – V2 Cloud Personal Roll Foundation

### Files changed

App / V2 flow:

- `ios/snaproll/snaproll/App/SnaprollApp.swift`
- `ios/snaproll/snaproll/App/V2/V2CloudHomeView.swift`
- `ios/snaproll/snaproll/App/V2/V2DependencyContainer.swift`
- `ios/snaproll/snaproll/App/V2/V2DevelopmentAuth.swift`
- `ios/snaproll/snaproll/App/V2/V2DevelopmentIdentityStore.swift`
- `ios/snaproll/snaproll/App/V2/V2SessionBootstrap.swift`

View model:

- `ios/snaproll/snaproll/ViewModels/V2CloudHomeViewModel.swift`

Tests:

- `ios/snaproll/snaprollTests/V2CloudHomeViewModelTests.swift`

Documentation:

- `v2-docs/implementation-log.md`

### What changed

- With the V2 feature flag enabled, a signed-in V2 session now routes into a minimal V2-only cloud home instead of the V1 `HomeView`.
- Added a development-only identity store so the selected development identity can change at runtime without recompiling the app.
- Added a minimal V2 cloud home surface that shows:
  - current development identity
  - current authenticated user/session
  - loading / empty / failed states
  - cloud-backed roll list
  - create personal roll action
  - refresh action

### How V2 cloud personal rolls are created

- The V2 cloud home calls `V2CloudHomeViewModel.createPersonalRoll()`.
- That method calls `RollRepository.createRoll(...)`.
- The live repository implementation uses the approved `create_roll(...)` RPC.
- Personal-roll defaults used in this phase:
  - `type = PERSONAL`
  - `film_stock_id = kodakGold200`
  - `exposures_per_participant = 12`
  - `participant_cap = 1`
- The backend remains responsible for creator/participant insertion.
- This phase does not touch:
  - `LocalStorageService`
  - V1 `Roll`
  - V1 `Photo`
  - camera / upload / reveal flows

### How visible rolls are scoped to current identity

- The V2 home loads the current session through `AuthRepository`.
- It fetches rolls through `RollRepository.fetchRolls()`.
- Read-side scoping is enforced by the existing Supabase RLS:
  - creator can see their own rolls
  - participants can see rolls they belong to
- For this phase, the V2 home filters the visible list to personal rolls.
- Switching the development identity triggers:
  - persisted identity update
  - V2 session bootstrap retry
  - reload of the visible cloud roll list

### Manual testing with development identities

1. Enable the V2 bootstrap and development auth flags in `ios/snaproll/snaproll/Utilities/AppConfig.swift`.
2. Launch the app.
3. Confirm the app enters the V2 bootstrap path and lands on `V2 Cloud Rolls`.
4. Leave the segmented identity control on `Creator`.
5. Create a personal roll and confirm it appears in the list.
6. Switch the segmented identity control to `Participant A`.
7. Confirm the Creator roll disappears.
8. Create a Participant A personal roll and confirm it appears.
9. Switch back to `Creator` and confirm the list changes back to the Creator-owned roll set.

### Build command executed

```text
xcodebuild -quiet -project ios/snaproll/snaproll.xcodeproj -scheme snaproll -destination 'generic/platform=iOS' -derivedDataPath /Users/zhengyu/Desktop/projects/snaproll/.deriveddata CODE_SIGNING_ALLOWED=NO build
```

### Test command executed

```text
xcodebuild -quiet -project ios/snaproll/snaproll.xcodeproj -scheme snaproll -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /Users/zhengyu/Desktop/projects/snaproll/.deriveddata-tests CODE_SIGNING_ALLOWED=NO -only-testing:snaprollTests test
```

### Results

- build succeeded
- tests succeeded

New Phase 7 coverage includes:

- V2 home loads rolls for current identity
- V2 personal roll creation uses `PERSONAL`
- reloading after identity change yields different user-scoped roll data
- repository failures surface as error state

### Assumptions / follow-up work

- This phase intentionally keeps V1 behavior untouched when the V2 feature flag is disabled.
- The new V2 cloud home is intentionally development-oriented, not final product UI.
- The next phases still need to wire:
  - personal roll start / exposure slots
  - capture -> upload -> sync
  - personal reveal / gallery
- The build still emits pre-existing camera orientation deprecation warnings and some Swift 6 isolation warnings in older test code; these do not block Phase 7 functionality but should be cleaned up in a later hardening pass.

## Phase 7 Follow-Up – Read RLS Recursion Fix

- Added migration:
  - `supabase/migrations/20260708002000_phase_7_read_rls_recursion_fix.sql`
- Root cause:
  - the Phase 4 read policy on `public.roll_participants` queried `public.roll_participants` inside its own `USING` clause
  - `public.rolls` and `public.exposures` also depended on `roll_participants` checks
  - once the V2 cloud home fetched user-scoped rolls, PostgreSQL raised:
    - `infinite recursion detected in policy for relation "roll_participants"`
- Fix applied:
  - introduced security-definer helper functions:
    - `public.is_roll_participant(...)`
    - `public.is_roll_creator(...)`
  - dropped the recursive read-side policies
  - recreated the policies to call those helpers instead of querying RLS-protected tables directly inside the policy body
- Impact:
  - personal cloud rolls remain scoped to the authenticated user
  - V2 roll fetches no longer recurse through `roll_participants` policy evaluation
  - no app-side changes were required for this database fix

## Phase 7 Follow-Up – Read RLS Helper Hardening

- Added migration:
  - `supabase/migrations/20260708004500_phase_7_read_rls_helper_hardening.sql`
- Problem observed after the recursion fix:
  - authenticated V2 roll reads could still fail with `permission denied for table rows`
- Interpretation:
  - the helper-based policy path still needed to run as an explicitly trusted membership / ownership check rather than under ordinary row-level restrictions
- Fix applied:
  - recreated `public.is_roll_participant(...)` and `public.is_roll_creator(...)`
  - marked them as `security definer`
  - set `row_security = off` in the helper execution context
  - reassigned ownership to `postgres`
  - dropped and recreated the read policies to bind them to the hardened helper definitions
- Impact:
  - authenticated reads for V2 personal roll lists should evaluate through the trusted helper path
  - personal cloud roll visibility remains user-scoped
  - no Swift or repository changes were required

## Phase 7 Follow-Up – Read Grants For Authenticated

- Added migration:
  - `supabase/migrations/20260708011000_phase_7_read_grants_for_authenticated.sql`
- Root cause:
  - table-level `SELECT` privileges had not been granted to the `authenticated` role for the V2 read path
  - PostgreSQL therefore rejected queries before RLS policy evaluation with:
    - `permission denied for table rolls`
- Fix applied:
  - granted `usage` on schema `public` to `authenticated`
  - granted `select` on:
    - `public.profiles`
    - `public.rolls`
    - `public.roll_participants`
    - `public.exposures`
    - `public.invites`
- Impact:
  - authenticated client reads can now reach the read-side RLS policies
  - row visibility remains policy-controlled
  - direct writes remain blocked outside the approved RPC path

## Phase 6 – Development Authentication

### Files changed

App / repository code:

- `ios/snaproll/snaproll/App/V2/V2DevelopmentAuth.swift`
- `ios/snaproll/snaproll/App/V2/V2DependencyContainer.swift`
- `ios/snaproll/snaproll/App/V2/V2SessionBootstrap.swift`
- `ios/snaproll/snaproll/Repositories/V2RepositoryProtocols.swift`
- `ios/snaproll/snaproll/Repositories/SupabaseRepositories.swift`
- `ios/snaproll/snaproll/Utilities/AppConfig.swift`

Tests:

- `ios/snaproll/snaprollTests/DevelopmentAuthTests.swift`
- `ios/snaproll/snaprollTests/V2SessionBootstrapTests.swift`

Backend support:

- `supabase/migrations/20260707103000_phase_6_development_auth_profile_ensure.sql`

Documentation:

- `v2-docs/phase-6-development-auth-context.md`

### Development identities added

- `Creator`
- `Participant A`
- `Participant B`

Each identity includes:

- stable development label
- fixed display name
- selected identity routing through `AuthRepository`

Implementation note:

- the current development-auth implementation uses anonymous Supabase sessions persisted per identity slot
- this provides stable repeatable identities on a given development device/workspace without coupling shared-roll logic to Apple or Google auth providers

### How to enable / disable development auth

In `ios/snaproll/snaproll/Utilities/AppConfig.swift`:

- enable V2 bootstrap with `AppConfig.V2.isSessionBootstrapEnabled = true`
- enable development auth with `AppConfig.V2.isDevelopmentAuthenticationEnabled = true`
- disable either flag to return to the existing safe V1 default path

### How to switch identities

In `ios/snaproll/snaproll/Utilities/AppConfig.swift`, change:

- `AppConfig.V2.developmentIdentity`

Supported values:

- `.creator`
- `.participantA`
- `.participantB`

### Repository / bootstrap behavior added

- `AuthRepository` now includes `signOut()`
- `DevelopmentAuthRepository` resolves the selected development identity and remains the only auth boundary seen by the rest of V2
- `V2DependencyContainer` now selects either:
  - standard Supabase session auth
  - or development auth
- V2 bootstrap now supports sign-out transitions while preserving V1 behavior when the V2 flags stay off

### Profile ensure support

- Added `public.ensure_profile(p_display_name text)` as a minimal security-definer RPC
- Development auth calls this during bootstrap so the authenticated user satisfies the existing Snaproll RPC invariant that a `profiles` row must exist

### Logging added

- development auth enabled
- selected development identity
- session restore / creation
- profile ensure success
- profile ensure failure
- development sign-out

### Build command executed

```text
xcodebuild -project ios/snaproll/snaproll.xcodeproj -scheme snaproll -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /Users/zhengyu/Desktop/projects/snaproll/.deriveddata CODE_SIGNING_ALLOWED=NO build
```

### Test command executed

```text
xcodebuild -project ios/snaproll/snaproll.xcodeproj -scheme snaproll -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath /Users/zhengyu/Desktop/projects/snaproll/.deriveddata CODE_SIGNING_ALLOWED=NO -only-testing:snaprollTests test
```

### Results

- build succeeded
- unit tests succeeded

Covered test cases include:

- development auth resolves `Creator`
- development auth resolves `Participant A`
- development auth sign-out transitions to `signedOut`
- bootstrap starts in `loading`
- no session transitions to `signedOut`
- existing session transitions to `signedIn`
- profile ensure / profile fetch failure transitions to `failed`
- flags-disabled configuration resolves to standard auth mode

### Assumptions / follow-up work

- This phase intentionally keeps V1 behavior unchanged because `AppConfig.V2.isSessionBootstrapEnabled` remains off by default.
- Development identity selection is currently config-driven rather than UI-driven to keep the phase non-invasive.
- Production authentication remains deferred to the later production-auth phase.

## Phase 1 – Supabase Schema Foundation

### Migration filename

- `supabase/migrations/20260704112500_phase_1_v2_schema_foundation.sql`

### Tables created

- `public.profiles`
- `public.rolls`
- `public.roll_participants`
- `public.exposures`
- `public.invites`

### Helper functions and triggers created

- `public.set_updated_at()`
- `public.prevent_filled_exposure_mutation()`
- trigger `set_rolls_updated_at` on `public.rolls`
- trigger `prevent_filled_exposure_mutation` on `public.exposures`

### Indexes created

- `idx_rolls_creator_id` on `rolls(creator_id)`
- `idx_roll_participants_user_id` on `roll_participants(user_id)`
- `idx_roll_participants_roll_id` on `roll_participants(roll_id)`
- `idx_exposures_roll_id` on `exposures(roll_id)`
- `idx_exposures_participant_id` on `exposures(participant_id)`
- `idx_invites_one_active_per_roll` unique partial index on active invites per roll

Note:

- `invites.token` is backed by the `invites_token_unique` unique constraint, which also provides the required token lookup index.
- `roll_participants(roll_id, user_id)` and `exposures(participant_id, exposure_number)` are enforced through unique constraints, which also create supporting indexes.

### Constraints added

- `rolls.type` constrained to `PERSONAL | SHARED`
- `rolls.status` constrained to `DRAFT | WAITING_FOR_PARTICIPANTS | SHOOTING | READY_TO_REVEAL | REVEALED`
- `rolls.exposures_per_participant` constrained to `12 | 24 | 36`
- `rolls.participant_cap >= 1`
- `roll_participants.status` constrained to `JOINED | SHOOTING | FINISHED`
- `unique (roll_id, user_id)` on `roll_participants`
- `unique (participant_id, exposure_number)` on `exposures`
- `exposure_number >= 1`
- composite foreign key on `exposures(participant_id, roll_id)` to ensure an exposure cannot reference a participant from a different roll
- `token unique` on `invites`
- one active invite per roll enforced by partial unique index
- filled exposures are immutable once `storage_path` is non-null

### RLS skeleton added

RLS was enabled on:

- `profiles`
- `rolls`
- `roll_participants`
- `exposures`
- `invites`

No explicit placeholder policies were kept. The schema relies on PostgreSQL/Supabase's default deny behavior when RLS is enabled without matching policies, with TODO comments left for the later authorization phase.

### Assumptions made

- `title`, `film_stock_id`, `type`, `status`, `exposures_per_participant`, `created_by`, and participant membership references are required fields and therefore stored as `NOT NULL`.
- `gen_random_uuid()` is used for non-auth primary keys via `pgcrypto`.
- `updated_at` is only applied to `rolls`, because that is the only table explicitly defined with `updated_at` in the architecture.
- `roll_participants.joined_at` is treated as the participant-row creation timestamp, so no separate `created_at` column was added there.
- Exposure immutability is safe to enforce now as a structural invariant, even though the actual fill/update workflow will later be owned by RPC functions.

### Deviations from architecture

No table-level deviations were introduced.

One implementation detail was added to preserve an architectural invariant:

- `roll_participants` includes a redundant `unique (id, roll_id)` constraint so `exposures` can use a composite foreign key and guarantee that `exposures.roll_id` always matches the participant's roll.

### Notes for later phases

- The schema does not yet enforce the workflow invariant that the creator is also a participant. That will be established by the later roll-creation / start-roll RPC flow.
- Exposure rows are not auto-created here. They will be created later by `start_roll()`, per the architecture.
- No storage buckets, storage policies, RPC functions, auth sync triggers, or iOS code were added in this phase.

### Follow-up adjustments

- `profiles.display_name` was relaxed to nullable so providers like Apple Sign In can create accounts before a display name is collected.
- Exposure immutability was narrowed so only `storage_path`, `captured_at`, `uploaded_at`, and `render_seed` are frozen after an exposure is filled.
- Explicit deny-all placeholder RLS policies were removed while keeping RLS enabled on every table.

## Phase 2 – RPC Foundation

### Migration filename

- `supabase/migrations/20260705103000_phase_2_rpc_foundation.sql`

### RPCs added

- `public.create_roll(...)`
- `public.join_roll(...)`
- `public.leave_roll(...)`
- `public.start_roll(...)`
- `public.reveal_roll(...)`
- `public.force_reveal_roll(...)`
- `public.regenerate_invite(...)`
- `public.complete_exposure(...)`

### Helper functions added

- `public.require_authenticated_profile_id()`
- `public.is_valid_film_stock_id(text)`
- `public.generate_secure_token()`
- `public.generate_render_seed()`

### Validation coverage

- All RPCs require an authenticated caller with an existing `profiles` row.
- Ownership is enforced for creator-only operations:
  - `start_roll()`
  - `reveal_roll()`
  - `force_reveal_roll()`
  - `regenerate_invite()`
- `join_roll()` validates:
  - active invite
  - shared-roll type
  - pre-start state
  - duplicate participation
  - participant cap
- `leave_roll()` validates:
  - pre-start state
  - participant membership
  - creator cannot leave
- `start_roll()` validates:
  - creator ownership
  - startable lifecycle state
  - participant count
  - participant cap
  - valid film stock
  - valid exposure count
  - exposures have not already been created
- `reveal_roll()` validates creator ownership and `READY_TO_REVEAL`
- `force_reveal_roll()` validates creator ownership and requires the roll to have started but not yet be revealed
- `regenerate_invite()` validates creator ownership, shared-roll type, and pre-start state
- `complete_exposure()` validates:
  - exposure ownership
  - participant status
  - roll status `SHOOTING`
  - exposure still empty
  - non-empty JPEG-like storage path

### State transitions implemented

- `create_roll()`:
  - creates the roll
  - inserts the creator as the first participant
  - creates an active invite for shared rolls
  - creates no exposures
- `join_roll()` inserts a participant before start
- `leave_roll()` removes a participant before start
- `start_roll()`:
  - creates exposure slots transactionally for every participant
  - marks participants `SHOOTING`
  - marks the roll `SHOOTING`
  - deactivates active invites
- `reveal_roll()` marks the roll `REVEALED`
- `force_reveal_roll()` marks the roll `REVEALED` without requiring all participants to finish
- `regenerate_invite()` revokes the previous active invite and inserts a new token
- `complete_exposure()`:
  - fills `storage_path`
  - sets `uploaded_at`
  - marks the participant `FINISHED` when all their exposures are filled
  - marks the roll `READY_TO_REVEAL` when all exposures in the roll are filled

### Assumptions made

- Security-definer RPCs are used because RLS is enabled and no table policies exist yet.
- Film stock validation currently accepts the same identifiers already used by the iOS V1/V2 code path:
  - `kodakGold200`
  - `fujifilmSuperia400`
  - `ilfordHP5Plus`
- `complete_exposure()` currently validates `storage_path` as a non-empty JPEG-like object path because the final storage path convention has not been specified yet.
- `captured_at` is not populated by `complete_exposure()` in this phase because the RPC contract only provided `exposure_id` and `storage_path`.

### Deviations / documented decisions

- To reconcile the architecture with the required initial roll states, `start_roll()` accepts:
  - `WAITING_FOR_PARTICIPANTS` for shared rolls
  - `DRAFT` for personal rolls

  Without this, personal rolls would remain stuck in `DRAFT` with no path to exposure creation.

- `regenerate_invite()` is limited to shared rolls before start. Regenerating invites after start was treated as invalid because joining is no longer allowed once the roll is locked.

### Phase 2 follow-up adjustments

- `start_roll()` no longer revokes or deactivates invites. Invite links remain viewable after start, while `join_roll()` continues to reject because the roll is no longer in `WAITING_FOR_PARTICIPANTS`.
- `participant_cap` is now validated consistently as `1 <= participant_cap <= 10`.
- Film stock validation was relaxed to require only a present, non-empty `film_stock_id` until a canonical V2 film catalogue exists.
- `complete_exposure()` now enforces the exact canonical storage path format:
  `rolls/{roll_id}/participants/{participant_id}/{exposure_number_padded_to_3_digits}.jpg`
- Shared roll participation now requires the caller to have a non-null, non-empty `profiles.display_name` for:
  - `create_roll(type = 'SHARED')`
  - `join_roll()`

### Phase 2 test script added

- Added a plug-and-play SQL smoke test script at:
  `supabase/tests/rpc_happy_path.sql`
- The script:
  - cleans previous fixture data
  - creates fixture `auth.users`
  - creates fixture `profiles`
  - simulates `auth.uid()` with `set_config`
  - runs the shared-roll happy path end-to-end
  - asserts expected database state with `raise exception`
  - verifies padded path handling with `001.jpg`
  - includes a final cleanup section

### Phase 2 follow-up migration added

- Added `supabase/migrations/20260706160000_phase_2_rpc_follow_up_fixes.sql`
- This follow-up migration exists because the original Phase 2 RPC migration had already been applied to the cloud project.
- It fixes:
  - the `join_roll()` PL/pgSQL ambiguity caused by `RETURNS TABLE` output names colliding with unqualified `roll_id` references
  - the canonical padded storage path contract in `complete_exposure()` so exposure paths use `001.jpg` style numbering
- The original Phase 2 migration file was restored to its previously applied form so local migration history matches what was actually deployed.

## Phase 3 – iOS Data Layer Foundation

### Files added

- `ios/snaproll/snaproll/Models/V2/V2DomainTypes.swift`
- `ios/snaproll/snaproll/Models/V2/LocalRoll.swift`
- `ios/snaproll/snaproll/Models/V2/LocalParticipant.swift`
- `ios/snaproll/snaproll/Models/V2/LocalExposure.swift`
- `ios/snaproll/snaproll/Models/V2/LocalInvite.swift`
- `ios/snaproll/snaproll/Repositories/V2RepositoryProtocols.swift`
- `ios/snaproll/snaproll/App/V2/V2DataLayer.swift`

### Models added

SwiftData models:

- `LocalRoll`
- `LocalParticipant`
- `LocalExposure`
- `LocalInvite`

Supporting V2 domain types:

- `V2Domain.RollType`
- `V2Domain.RollStatus`
- `V2Domain.ParticipantStatus`
- `V2Domain.ExposureSyncState`

### Repository protocols added

- `AuthRepository`
- `RollRepository`
- `ParticipantRepository`
- `ExposureRepository`
- `InviteRepository`
- `SyncRepository`
- `RenderCacheRepository`

### Assumptions made

- The V2 enums were namespaced under `V2Domain` to avoid colliding with the existing V1 `RollStatus` type and to keep V1 behavior unchanged.
- The SwiftData models currently store cloud identifiers and local workflow state as scalar fields rather than introducing relationships, keeping the foundation simple and non-invasive for this phase.
- `LocalExposure` includes a canonical padded storage-path helper using the agreed convention:
  `rolls/{roll_id}/participants/{participant_id}/001.jpg`
- No SwiftData `ModelContainer` was attached to the app yet, because this phase introduces the local model layer only and must not alter current V1 runtime behavior.
- The build environment used for this phase cannot successfully expand SwiftData macros, so the SwiftData-backed `@Model` definitions are present behind a compile-time gate and a shape-compatible fallback path keeps the V1 app buildable today.

### Deviations

- The architecture names the enums generically (`RollType`, `RollStatus`, etc.), but the implementation wraps them in a `V2Domain` namespace for coexistence with the V1 app model layer.
- The SwiftData model definitions are gated behind `V2_SWIFTDATA_MODELS` so the project can compile reliably in the current toolchain environment without changing V1 behavior. The active compiled path preserves the same local model shapes and repository boundaries for this foundation phase.

## Phase 4 – iOS Supabase Networking Foundation

### Supabase client setup

- Reused the existing Swift Package Manager dependency on `supabase-swift` already present in the Xcode project.
- Added `ios/snaproll/snaproll/App/V2/V2SupabaseConfiguration.swift` to load:
  - `SNAPROLL_SUPABASE_URL`
  - `SNAPROLL_SUPABASE_PUBLISHABLE_KEY`
- The configuration can come from:
  - generated Info.plist keys in the Xcode target build settings
  - or scheme environment variables with the same names
- Added `V2SupabaseClientProvider` as a lazy actor-backed provider so the app creates at most one `SupabaseClient` instance and only when a V2 repository is first used.

### Dependency injection changes

- Added `ios/snaproll/snaproll/App/V2/V2DependencyContainer.swift`
- Added a non-invasive `v2Dependencies` app-level container in `SnaprollApp`
- The current V1 UI does not consume these dependencies yet, but the repository graph now exists at the app layer for later feature integration.

### Repositories implemented

- `SupabaseAuthRepository`
- `SupabaseRollRepository`
- `SupabaseParticipantRepository`
- `SupabaseExposureRepository`
- `SupabaseInviteRepository`

### Repository operations implemented

- Auth:
  - `currentSession()`
  - `currentUserID()`
- Rolls:
  - `fetchRoll(id:)`
  - `fetchRolls()`
  - `createRoll(...)`
- Participants:
  - `fetchParticipants(forRollID:)`
  - `fetchParticipant(id:)`
  - `joinRoll(inviteToken:)`
  - `leaveRoll(rollID:)`
- Exposures:
  - `fetchExposures(forRollID:)`
  - `fetchExposures(forParticipantID:)`
  - `fetchExposure(id:)`
- Invites:
  - `fetchInvite(forRollID:)`
  - `fetchInvite(token:)`
  - `regenerateInvite(forRollID:)`

### Error mapping

- Added `ios/snaproll/snaproll/Repositories/V2RepositoryError.swift`
- Repository calls now map Supabase/PostgREST/network/decoding failures into domain-facing repository errors instead of exposing raw database errors directly to callers.

### Read-access support added

- Added `supabase/migrations/20260707021000_phase_4_read_rls_for_ios.sql`
- This migration introduces the minimal read-side RLS policies required for the iOS networking layer to function with the anon/authenticated client:
  - authenticated profile reads
  - roll reads for creators/participants
  - participant-list reads for accessible rolls
  - exposure reads for accessible rolls
  - invite reads for creators
- Business-state mutations remain RPC-owned; no direct write policies were added.

### Assumptions made

- Because Phase 1 intentionally enabled RLS with deny-by-default and Phase 2 lifecycle RPCs are security-definer only for writes, the iOS read path required the smallest possible read-side RLS layer in order to make repository fetches functional.
- V2 write methods that depend on future local SwiftData syncing or later feature phases remain intentionally unsupported in the concrete repositories for now rather than silently performing partial behavior.
- V1 screens and flows remain unchanged; the new networking layer is app-scoped infrastructure for later V2 feature integration.

## Phase 5 – V2 Auth / Session Bootstrap Integration

### Files added

- `ios/snaproll/snaproll/App/V2/V2SessionBootstrap.swift`

### Files updated

- `ios/snaproll/snaproll/App/SnaprollApp.swift`
- `ios/snaproll/snaproll/Utilities/AppConfig.swift`

### Bootstrap layer added

- Added `V2SessionState` with:
  - `loading`
  - `signedOut`
  - `signedIn(AuthSession)`
  - `failed(String)`
- Added `V2SessionBootstrapper` to orchestrate the initial auth/session check through `AuthRepository`
- Added `V2SessionStore` as the app-owned observable bootstrap/session state holder
- Added lightweight OSLog-backed state transition logging for:
  - bootstrap start
  - signed out resolution
  - signed in resolution
  - bootstrap failure

### App integration

- `SnaprollApp` now owns:
  - the V2 dependency container
  - a V2 session store created from that container
- Added `AppConfig.V2.isSessionBootstrapEnabled` feature flag
- Default remains `false` so the live app still enters through the V1 `HomeView`
- When enabled later, the app enters through `V2BootstrapEntryView`, which:
  - starts in loading state
  - bootstraps once
  - shows signed-out / failed placeholder states
  - routes signed-in users to the existing `HomeView`

### Assumptions made

- For this phase, `AuthRepository.currentSession()` is the bootstrap boundary that both detects an auth session and fetches the current profile-backed session information.
- A dedicated V2 sign-in UI and explicit profile-creation/repair flow are deferred to later auth phases.
- Because the feature flag remains off by default, no V1 user-visible behavior changes in normal app usage.

## Phase 11B – Shared Lobby Management & Start Roll

### Files changed

- `supabase/migrations/20260710033000_phase_11b_remove_participant_rpc.sql`
- `ios/snaproll/snaproll/Repositories/SupabaseRepositories.swift`
- `ios/snaproll/snaproll/ViewModels/V2SharedRollLobbyViewModel.swift`
- `ios/snaproll/snaproll/App/V2/V2SharedRollLobbyView.swift`
- `ios/snaproll/snaprollTests/V2SharedRollLobbyViewModelTests.swift`

### Lobby management

- Added a dedicated `remove_participant(uuid)` RPC so shared-lobby participant removal remains backend-owned and lifecycle-validated.
- Wired `SupabaseParticipantRepository.deleteParticipant(id:)` to the new RPC instead of leaving participant removal as an unsupported placeholder.
- Extended the V2 shared lobby view model with creator/participant management actions:
  - remove participant
  - leave roll
  - regenerate invite
  - start roll
- Added explicit action status/error messaging so backend lifecycle violations surface cleanly in the development lobby UI.

### Start roll flow

- The creator can now start a shared roll only while the roll remains in `WAITING_FOR_PARTICIPANTS`.
- `V2SharedRollLobbyViewModel.startRoll()` calls `RollRepository.startRoll(...)`, then reloads the authoritative roll/participant state from Supabase.
- Once the roll transitions to `SHOOTING`, the lobby switches into a locked state and hides creator/participant mutation controls.

### Immutable lobby behaviour

- Lobby mutating controls are now derived from backend lifecycle state:
  - `canStartRoll`
  - `canRegenerateInvite`
  - `canLeaveRoll`
  - `canRemoveParticipant(...)`
- After `SHOOTING`, the UI removes join-management affordances and instead shows a locked-lobby message plus the exposure plan summary.

### Exposure slot generation and local mirroring

- After a successful shared `start_roll()`, the lobby fetches the current participant's cloud-created exposures through `ExposureRepository.fetchExposures(forParticipantID:)`.
- The returned exposures are mirrored into the existing local exposure mirror store, matching the personal-roll approach and proving that shared rolls now have an authoritative backend-created shooting plan.
- This phase intentionally stops at mirroring; it does not implement shared capture, upload, or reveal yet.

### Tests added

- Added focused shared-lobby view-model coverage for:
  - creator can remove participant
  - participant can leave
  - creator cannot leave own roll
  - regenerate invite refreshes invite state
  - start roll fetches/mirrors current participant exposures
  - lobby actions become unavailable after `SHOOTING`
  - backend lifecycle errors surface clearly

### Manual validation

- Launch with V2 enabled and a development identity selected.
- Create a shared roll as the creator and open the shared lobby.
- Join from another development identity.
- Remove and rejoin participants from the creator view.
- Regenerate the invite and confirm the new token is shown.
- Start the roll and confirm:
  - roll status changes to `SHOOTING`
  - creator/participant mutation controls disappear
  - exposure rows are created in Supabase
  - current-participant exposure mirrors appear locally in the lobby diagnostics

### Build and test commands

- Test:
  - `xcodebuild -quiet -project ios/snaproll/snaproll.xcodeproj -scheme snaproll -destination 'platform=iOS Simulator,id=EAC195FF-FF23-4BCF-A389-B7550AF27B53' -derivedDataPath /Users/zhengyu/Desktop/projects/snaproll/.deriveddata-tests-phase11b CODE_SIGNING_ALLOWED=NO -only-testing:snaprollTests/V2SharedRollLobbyViewModelTests -only-testing:snaprollTests/V2CloudHomeViewModelTests test`
- Build:
  - `xcodebuild -quiet -project ios/snaproll/snaproll.xcodeproj -scheme snaproll -destination 'generic/platform=iOS' -derivedDataPath /Users/zhengyu/Desktop/projects/snaproll/.deriveddata-phase11b CODE_SIGNING_ALLOWED=NO build`

### Results

- Focused V2 cloud-home and shared-lobby tests passed.
- Full iOS project build passed.
- Existing warnings remain around deprecated camera orientation APIs and one pre-existing actor-isolation warning in `V2SupabaseConfiguration`, but they did not block this phase.

### Assumptions / follow-up

- Shared-lobby joining from the home surface remains Phase 11A behavior; this phase only completes the pre-start lobby management and start-roll transition.
- The new `remove_participant` RPC assumes creator-owned moderation only and intentionally rejects removal after the roll starts.
- Shared capture, upload/sync, reveal, and participant gallery flows remain future work.

## Phase 12 – V2 Shared Capture, Sync, Reveal & Gallery

### Files changed

- `ios/snaproll/snaproll/Repositories/V2RepositoryProtocols.swift`
- `ios/snaproll/snaproll/Repositories/SupabaseRepositories.swift`
- `ios/snaproll/snaproll/Services/V2LocalCapturePipeline.swift`
- `ios/snaproll/snaproll/Services/V2ExposureSyncRunner.swift`
- `ios/snaproll/snaproll/ViewModels/V2CaptureViewModel.swift`
- `ios/snaproll/snaproll/App/V2/V2CaptureView.swift`
- `ios/snaproll/snaproll/ViewModels/V2PersonalRollDetailViewModel.swift`
- `ios/snaproll/snaproll/App/V2/V2PersonalRollDetailView.swift`
- `ios/snaproll/snaproll/ViewModels/V2PersonalRevealGalleryViewModel.swift`
- `ios/snaproll/snaproll/ViewModels/V2SharedRevealGalleryViewModel.swift`
- `ios/snaproll/snaproll/App/V2/V2SharedRevealGalleryView.swift`
- `ios/snaproll/snaproll/App/V2/V2CloudHomeView.swift`
- `ios/snaproll/snaproll/App/V2/V2SharedRollLobbyView.swift`
- `ios/snaproll/snaprollTests/V2LocalCapturePipelineTests.swift`
- `ios/snaproll/snaprollTests/V2ExposureSyncRunnerTests.swift`
- `ios/snaproll/snaprollTests/V2PersonalRollDetailViewModelTests.swift`
- `ios/snaproll/snaprollTests/V2SharedRevealGalleryViewModelTests.swift`
- `ios/snaproll/snaprollTests/V2ExposureUploadPipelineTests.swift`

### Shared execution flow

- Shared rolls now reuse the existing V2 personal-roll execution path rather than introducing a second capture/sync architecture.
- The active shared-roll flow is now:
  - creator starts the shared roll in the lobby
  - the app routes into the existing V2 roll detail surface once the roll is no longer waiting
  - the current participant captures only their own mirrored exposures
  - sync uploads and metadata completion operate only on the current participant's exposures
  - reveal remains backend-authoritative and becomes available only when the roll reaches `READY_TO_REVEAL`
  - revealed shared rolls open a grouped shared gallery

### Code reuse from the personal pipeline

- `V2LocalCapturePipeline` was extended with optional participant scoping so shared capture still uses the same local-first exposure filling logic.
- `V2ExposureSyncRunner` was extended with optional participant scoping so the same upload + metadata pipeline can process only the current participant's work in shared rolls.
- `V2PersonalRollDetailViewModel` and `V2PersonalRollDetailView` were expanded to understand shared-roll state, participant ownership, creator-only reveal permissions, and shared participant progress while continuing to serve personal rolls.
- `V2CaptureViewModel` and `V2CaptureView` now accept an optional participant context so the same capture UI can be reused for both personal and shared flows.

### Participant ownership

- Shared execution now loads the current authenticated session plus the roll's participant list.
- During shared shooting/ready/revealed states, the roll detail view fetches and mirrors only the current participant's exposure slots.
- Capture fills only the next empty exposure for the current participant.
- Sync processes only the current participant's pending exposures.
- Shared participant progress is displayed from the backend participant list rather than inferred from local capture state alone.

### Shared gallery

- Added `V2SharedRevealGalleryViewModel` and `V2SharedRevealGalleryView`.
- Shared galleries are grouped by participant in joined order.
- Exposures are sorted within each participant group by `exposure_number`.
- Rendering continues to use the existing on-device renderer and render seed logic.
- Rendering now prefers:
  - local original image first
  - downloaded cloud JPEG second
- To support shared galleries on devices that did not capture a given photo, `ExposureAssetStorageRepository` now supports downloading the uploaded JPEG from Supabase Storage.

### Navigation updates

- The cloud home surface now routes shared rolls to:
  - the shared lobby while the roll is `WAITING_FOR_PARTICIPANTS`
  - the shared execution/detail flow once the roll has started
- The shared lobby now exposes a "Continue Roll" / "Open Gallery" path after the lobby becomes immutable, so the creator can move straight from start into execution without backing out first.

### Manual validation

- With V2 enabled and multiple development identities:
  - create a shared roll
  - join from additional identities
  - start the roll
  - confirm each identity only sees its own capture progress and capture UI
  - capture through each participant
  - trigger sync and confirm only the current participant's exposures upload/complete on that device
  - confirm the roll reaches `READY_TO_REVEAL` only after all participants finish
  - reveal as the creator
  - confirm all identities can load the grouped shared gallery
  - confirm same-device captures use local originals while other participants fall back to cloud JPEG downloads

### Build and test commands

- Focused tests:
  - `xcodebuild -quiet -project ios/snaproll/snaproll.xcodeproj -scheme snaproll -destination 'platform=iOS Simulator,id=EAC195FF-FF23-4BCF-A389-B7550AF27B53' -derivedDataPath /Users/zhengyu/Desktop/projects/snaproll/.deriveddata-tests-phase12 CODE_SIGNING_ALLOWED=NO -only-testing:snaprollTests/V2LocalCapturePipelineTests -only-testing:snaprollTests/V2ExposureSyncRunnerTests -only-testing:snaprollTests/V2PersonalRollDetailViewModelTests -only-testing:snaprollTests/V2SharedRollLobbyViewModelTests -only-testing:snaprollTests/V2SharedRevealGalleryViewModelTests test`
- Full build:
  - `xcodebuild -quiet -project ios/snaproll/snaproll.xcodeproj -scheme snaproll -destination 'generic/platform=iOS' -derivedDataPath /Users/zhengyu/Desktop/projects/snaproll/.deriveddata-phase12 CODE_SIGNING_ALLOWED=NO build`

### Results

- Focused shared execution / gallery / participant-scoped pipeline tests passed.
- Full iOS project build passed.
- Pre-existing warnings remain around deprecated camera orientation APIs and one actor-isolation warning in `V2SupabaseConfiguration`, but they did not block this phase.

### Assumptions

- The repository did not contain the exact `phase-12-shared-roll-execution-context.md` filename referenced in the task prompt, so implementation followed `v2-docs/ARCHITECTURE.md` plus the current Phase 11/Phase 8/Phase 9 V2 code paths as the authoritative execution baseline.
- Shared reveal remains creator-only, matching the shared-roll lifecycle defined in the architecture.
- Cloud download fallback is used only for revealed shared-gallery viewing, not for capture or sync.

## Phase 13 – V2 Shared State Synchronization

### Files changed

- `ios/snaproll/snaproll/Services/V2SharedStateSynchronizer.swift`
- `ios/snaproll/snaproll/Utilities/AppConfig.swift`
- `ios/snaproll/snaproll/ViewModels/V2SharedRollLobbyViewModel.swift`
- `ios/snaproll/snaproll/ViewModels/V2PersonalRollDetailViewModel.swift`
- `ios/snaproll/snaproll/App/V2/V2SharedRollLobbyView.swift`
- `ios/snaproll/snaproll/App/V2/V2PersonalRollDetailView.swift`
- `ios/snaproll/snaprollTests/V2SharedStateSynchronizerTests.swift`

### SharedStateSynchronizer architecture

- Added a dedicated `V2SharedStateSynchronizer` abstraction so shared-roll polling is isolated from SwiftUI screens and repository implementations.
- The synchronizer is intentionally read-only:
  - it refreshes authoritative cloud state
  - it updates local UI-facing state through existing view-model reload paths
  - it never uploads photos
  - it never mutates backend lifecycle directly
- Added a registry actor to ensure only one synchronizer can actively poll a given roll at a time.
- Added a polling snapshot model so development mode can expose diagnostics without leaking internal state into normal user mode.

### Polling lifecycle

- Polling intervals are now configurable through `AppConfig.V2`:
  - `waitingForParticipantsPollingInterval`
  - `sharedShootingPollingInterval`
  - `readyToRevealPollingInterval`
- Implemented lifecycle-aware polling behavior:
  - `WAITING_FOR_PARTICIPANTS` polls every 5 seconds by default
  - `SHOOTING` polls every 10 seconds by default
  - `READY_TO_REVEAL` polls every 5 seconds by default
  - `REVEALED` stops polling
  - `DRAFT` does not poll
- Polling starts when a shared lobby or shared roll detail screen becomes active.
- Polling stops when:
  - the screen disappears
  - the app backgrounds
  - the roll reaches a non-polling terminal state
- The synchronizer now waits for its polling task to unwind cleanly on stop so view teardown does not leave orphaned polling work behind.

### Immediate refresh triggers

- Shared lobby:
  - first load
  - manual refresh
  - app foreground
  - start roll
  - regenerate invite
  - remove participant
- Shared execution/detail:
  - first load
  - app foreground
  - capture session end
  - process pending exposures
  - retry failed synchronization
  - reveal roll
- These refreshes reuse the same repository-backed view-model reload methods as polling rather than introducing separate sync paths.

### UI integration

- `V2SharedRollLobbyView` now owns a synchronizer instance tied to the current roll ID.
- `V2PersonalRollDetailView` now enables the synchronizer only for shared rolls.
- Shared lobby and shared roll detail development diagnostics now include:
  - whether polling is active
  - whether polling is blocked by another synchronizer
  - current polling interval
  - latest backend lifecycle state
  - poll count
  - last refresh time
  - last refresh duration
  - last polling error

### Testing

- Added `V2SharedStateSynchronizerTests` covering:
  - polling start
  - interval changes by lifecycle state
  - stop on screen disappearance
  - foreground resume
  - automatic failure recovery
  - single active synchronizer per roll
  - stopping after reveal
- The test sleep harness was hardened so cancellation resumes suspended polling waits instead of leaving dangling continuations behind.

### Manual validation

- With V2 enabled and multiple development identities:
  - open a shared lobby as creator
  - join from another development identity
  - confirm the creator sees the participant list update within the waiting poll interval
  - start the roll as creator
  - confirm participants transition into `SHOOTING` without manual refresh
  - complete captures and sync from each participant
  - confirm `READY_TO_REVEAL` appears automatically
  - reveal as creator
  - confirm other participants observe `REVEALED` without manual refresh
  - background and foreground the app to verify polling stops and immediately refreshes on resume

### Build and test commands

- Build:
  - `xcodebuild -quiet -project ios/snaproll/snaproll.xcodeproj -scheme snaproll -destination 'generic/platform=iOS' -derivedDataPath /Users/zhengyu/Desktop/projects/snaproll/.deriveddata-phase13-build CODE_SIGNING_ALLOWED=NO build`
- Focused test attempts:
  - `xcodebuild -quiet -project ios/snaproll/snaproll.xcodeproj -scheme snaproll -destination 'platform=iOS Simulator,id=EAC195FF-FF23-4BCF-A389-B7550AF27B53' -derivedDataPath /Users/zhengyu/Desktop/projects/snaproll/.deriveddata-phase13-tests CODE_SIGNING_ALLOWED=NO -only-testing:snaprollTests/V2SharedStateSynchronizerTests -only-testing:snaprollTests/V2SharedRollLobbyViewModelTests -only-testing:snaprollTests/V2PersonalRollDetailViewModelTests test`
  - `xcodebuild -project ios/snaproll/snaproll.xcodeproj -scheme snaproll -destination 'platform=iOS Simulator,OS=26.5,name=iPhone 17 Pro' -derivedDataPath /Users/zhengyu/Desktop/projects/snaproll/.deriveddata-phase13-sync-tests CODE_SIGNING_ALLOWED=NO -only-testing:snaprollTests/V2SharedStateSynchronizerTests test`

### Results

- Full iOS project build passed after adding the new shared-state synchronization layer.
- Focused simulator test execution was attempted multiple times and compiled successfully, but the local simulator runner was unstable after a simulator service failure and did not produce a clean completed test run within this session.
- Existing warnings remain around deprecated camera orientation APIs and a pre-existing actor-isolation warning in `V2SupabaseConfiguration`.

### Assumptions

- The repository did not contain the exact `phase-13-shared-state-synchronization-context.md` filename referenced in the task prompt, so implementation followed `v2-docs/ARCHITECTURE.md` and the current shared-roll V2 code paths as the source of truth.
- Manual refresh remains available, but shared state no longer depends on it for normal collaborative lifecycle transitions.
- Polling is intentionally isolated behind `V2SharedStateSynchronizer` so Supabase Realtime can replace the transport later without rewriting view models or screen logic.

## Phase 14A – Durable Pending Work & Restart Recovery

### Files changed

- `ios/snaproll/snaproll/Models/V2/LocalExposure.swift`
- `ios/snaproll/snaproll/Repositories/V2LocalExposureMirrorStore.swift`
- `ios/snaproll/snaproll/Repositories/V2RepositoryProtocols.swift`
- `ios/snaproll/snaproll/Services/V2PendingExposureRecoveryCoordinator.swift`
- `ios/snaproll/snaproll/App/V2/V2DependencyContainer.swift`
- `ios/snaproll/snaproll/App/V2/V2CloudHomeView.swift`
- `ios/snaproll/snaproll/App/V2/V2PersonalRollDetailView.swift`
- `ios/snaproll/snaproll/ViewModels/V2PersonalRollDetailViewModel.swift`
- `ios/snaproll/snaprollTests/V2PendingExposureRecoveryCoordinatorTests.swift`

### Recovery normalization rules

- Recovery is now driven entirely from persisted `LocalExposure` records rather than any in-memory queue.
- On recovery:
  - `LOCAL_ONLY` stays `LOCAL_ONLY` and remains eligible for upload.
  - `UPLOADING` is normalized back to `LOCAL_ONLY` because an upload cannot still be in progress after process restart.
  - `METADATA_PENDING` stays `METADATA_PENDING` and resumes metadata completion only.
  - `FAILED` resumes from the correct stage by deriving failure stage from persisted state:
    - if `cloud_storage_path` exists, the upload already succeeded and recovery resumes metadata completion only
    - if `cloud_storage_path` is empty, recovery resumes upload
  - `EMPTY` and `SYNCED` are ignored.

### Recovery triggers

- Added a dedicated `V2PendingExposureRecoveryCoordinator`.
- Recovery now runs at these V2 lifecycle points:
  - after the V2 app enters a signed-in cloud session
  - when the V2 app returns to foreground
  - when a V2 personal or shared roll detail screen opens
- The coordinator keeps per-roll in-process tracking so the same roll is not obviously recovered twice at the same time during this phase.

### How failure stage is preserved or derived

- No new backend state was introduced for failure-stage recovery.
- The existing local model already preserves enough information:
  - `cloud_storage_path` means the Storage upload completed
  - absence of `cloud_storage_path` means the failure happened before upload completion
- To make recovery observable in development mode, `LocalExposure` now persists:
  - `last_recovery_from_state`
  - `last_recovery_to_state`
  - `last_recovery_reason`
  - `last_recovery_error`
  - `last_recovered_at`

### Development diagnostics

- V2 roll diagnostics now show recovery details in development mode, including:
  - state before normalization
  - recovered state
  - recovery reason
  - last recovery time
  - recovery errors
- These diagnostics remain hidden in normal user mode.

### Testing

- Added focused unit coverage for:
  - `LOCAL_ONLY` restart recovery
  - `UPLOADING` normalization
  - `METADATA_PENDING` resuming metadata only
  - failed upload-stage recovery
  - failed metadata-stage recovery
  - `SYNCED` and `EMPTY` no-op behavior
  - persisted file-backed recovery after restart
  - current-user and roll scoping
  - preservation of local originals and uploaded-path metadata on recovery failure

### Manual validation

- Code-level recovery hooks were added for the Phase 14A restart scenarios, but manual device validation was not performed in this implementation pass.
- Recommended manual validation:
  - create and start a V2 roll
  - capture into `LOCAL_ONLY`
  - terminate and relaunch
  - confirm recovery resumes upload
  - stop after upload reaches `METADATA_PENDING`
  - relaunch and confirm recovery resumes metadata completion without re-uploading

### Build and test commands

- Full build:
  - `xcodebuild -quiet -project ios/snaproll/snaproll.xcodeproj -scheme snaproll -destination 'generic/platform=iOS' -derivedDataPath /Users/zhengyu/Desktop/projects/snaproll/.deriveddata-phase14a-build CODE_SIGNING_ALLOWED=NO build`
- Focused tests:
  - `xcodebuild -project ios/snaproll/snaproll.xcodeproj -scheme snaproll -destination 'platform=iOS Simulator,OS=26.5,name=iPhone 17 Pro' -derivedDataPath /Users/zhengyu/Desktop/projects/snaproll/.deriveddata-phase14a-tests CODE_SIGNING_ALLOWED=NO -only-testing:snaprollTests/V2PendingExposureRecoveryCoordinatorTests -only-testing:snaprollTests/V2ExposureSyncRunnerTests -only-testing:snaprollTests/V2PersonalRollDetailViewModelTests test`

### Results

- Full iOS project build passed.
- Focused recovery-related tests were added and executed against the simulator target in this phase.

### Assumptions and follow-up work for Phases 14B–14D

- Phase 14A intentionally avoids broader duplicate-trigger hardening beyond per-roll in-process guarding during a single app lifetime.
- Backoff, scheduled retries, and broader local/cloud reconciliation remain deferred to later failure-recovery phases.
- Identity-switch hardening is only basic in this phase: recovery is scoped to the current session user and relevant participant/roll, but more defensive handling for rapid identity changes belongs in Phase 14D.

## Phase 14B – Single-Runner Retry and Idempotent Sync

### Files changed

- `ios/snaproll/snaproll/Services/V2ExposureSyncRunner.swift`
- `ios/snaproll/snaproll/Services/V2ExposureUploadPipeline.swift`
- `ios/snaproll/snaproll/Services/V2ExposureMetadataCompletionPipeline.swift`
- `ios/snaproll/snaproll/Repositories/SupabaseRepositories.swift`
- `ios/snaproll/snaprollTests/V2ExposureSyncRunnerTests.swift`
- `ios/snaproll/snaprollTests/V2ExposureUploadPipelineTests.swift`
- `supabase/migrations/20260714090000_phase_14b_idempotent_complete_exposure.sql`
- `supabase/tests/rpc_complete_exposure_idempotency.sql`
- `v2-docs/implementation-log.md`

### Single active runner strategy

- The live V2 dependency container continues to create one shared `V2ExposureSyncRunner` instance.
- `V2ExposureSyncRunner` now enforces one active sync pass at a time across the instance.
- If another trigger fires while a sync pass is active, the duplicate trigger is skipped and reported in the returned summary instead of starting overlapping work.
- A later sync request can run normally after the active pass finishes.
- Exposure processing remains sequential and ordered by `exposure_number`.

### Idempotency rules

- `LOCAL_ONLY` uploads to the canonical path, then proceeds to metadata completion.
- `METADATA_PENDING` skips upload and retries metadata completion only.
- `FAILED` with no `cloud_storage_path` retries upload.
- `FAILED` with a valid `cloud_storage_path` retries metadata completion only.
- `SYNCED` and `EMPTY` are ignored.
- If `cloud_storage_path` already exists locally, the upload stage treats upload as completed and moves the exposure back to `METADATA_PENDING` without regenerating or re-uploading the JPEG.

### Storage behavior

- Storage uploads continue to use the canonical path:
  - `rolls/{roll_id}/participants/{participant_id}/{exposure_number_padded}.jpg`
- The Supabase Storage implementation now uploads with `upsert: true`.
- This means a retry after a crash that happened after Storage accepted bytes but before local state saved `cloud_storage_path` writes the same exposure JPEG back to the same canonical object path rather than creating alternate objects.
- Once `cloud_storage_path` is persisted locally, the app skips upload entirely for that exposure.
- This phase does not attempt broad object-content reconciliation for already-existing Storage objects; that remains future recovery hardening.

### complete_exposure() idempotency

- Added migration `20260714090000_phase_14b_idempotent_complete_exposure.sql`.
- `complete_exposure()` now behaves as:
  - empty exposure + expected canonical path: complete the exposure and return success
  - already completed exposure + same canonical path: return success
  - already completed exposure + different path: reject clearly
- The function still validates ownership and canonical path layout.
- Repeated successful calls no longer corrupt participant or roll lifecycle state.

### Bounded retry policy

- The sync runner now retries each exposure a small bounded number of times within one sync pass.
- Default attempts per exposure: `2`.
- Default delay between attempts: `250ms`.
- Tests use a zero retry delay for deterministic execution.
- After retries are exhausted:
  - the exposure is marked `FAILED`
  - `last_error` is persisted
  - local original paths are preserved
  - valid `cloud_storage_path` values are preserved
  - later exposures continue to process sequentially

### Testing

- Added or updated tests covering:
  - overlapping sync requests produce only one active pass
  - later sync requests can run after the first pass finishes
  - exposure processing order is sequential by exposure number
  - `LOCAL_ONLY` upload retry
  - `METADATA_PENDING` skipping upload
  - `FAILED` with and without `cloud_storage_path`
  - bounded retry success and retry exhaustion
  - `SYNCED` and `EMPTY` no-op behavior
  - existing canonical Storage object retry behavior
  - Phase 14A recovered work flowing through the same runner
- Added SQL smoke test:
  - `supabase/tests/rpc_complete_exposure_idempotency.sql`

### Manual validation

- Manual device validation was not performed in this implementation pass.
- Recommended manual validation:
  - capture multiple V2 exposures
  - trigger sync from roll open, foreground, and manual retry close together
  - confirm only one sync pass runs at a time in diagnostics
  - confirm Storage receives only canonical paths
  - force `METADATA_PENDING` and retry metadata completion without upload
  - run the SQL smoke test against a disposable Supabase project after applying the migration

### Build and test commands

- Focused tests:
  - `xcodebuild -project ios/snaproll/snaproll.xcodeproj -scheme snaproll -destination 'platform=iOS Simulator,OS=26.5,name=iPhone 17 Pro' -derivedDataPath /Users/zhengyu/Desktop/projects/snaproll/.deriveddata-phase14b-tests CODE_SIGNING_ALLOWED=NO -only-testing:snaprollTests/V2ExposureSyncRunnerTests -only-testing:snaprollTests/V2ExposureUploadPipelineTests -only-testing:snaprollTests/V2ExposureMetadataCompletionPipelineTests -only-testing:snaprollTests/V2PendingExposureRecoveryCoordinatorTests test`
- Full build:
  - `xcodebuild -quiet -project ios/snaproll/snaproll.xcodeproj -scheme snaproll -destination 'generic/platform=iOS' -derivedDataPath /Users/zhengyu/Desktop/projects/snaproll/.deriveddata-phase14b-build CODE_SIGNING_ALLOWED=NO build`
- SQL smoke test:
  - `supabase/tests/rpc_complete_exposure_idempotency.sql` is intended to be run manually in Supabase SQL Editor after the migration is pushed.

### Results

- Focused iOS sync, upload, metadata, and recovery tests passed.
- Full iOS project build passed.
- SQL smoke test was added but not executed locally in this pass because it targets the linked Supabase database.

### Assumptions and remaining Phase 14 work

- The repository still does not contain `v2-docs/phase-14-failure-recovery-context.md`; implementation followed `ARCHITECTURE.md`, the attached Phase 14B brief, and the current Phase 14A code.
- Duplicate triggers are skipped rather than queued for an automatic follow-up pass. Later lifecycle triggers or manual retry can start another pass after the current one finishes.
- This phase intentionally avoids parallel upload workers, background execution, long-term retry scheduling, and broad local/cloud reconciliation.

## Phase 14C – Local/Cloud Reconciliation and Identity Safety

### Files changed

- `ios/snaproll/snaproll/Models/V2/LocalExposure.swift`
- `ios/snaproll/snaproll/Repositories/V2LocalExposureMirrorStore.swift`
- `ios/snaproll/snaproll/Repositories/V2RepositoryProtocols.swift`
- `ios/snaproll/snaproll/Services/V2ExposureReconciliationCoordinator.swift`
- `ios/snaproll/snaproll/Services/V2ExposureSyncRunner.swift`
- `ios/snaproll/snaproll/Services/V2PendingExposureRecoveryCoordinator.swift`
- `ios/snaproll/snaproll/App/V2/V2DependencyContainer.swift`
- `ios/snaproll/snaproll/ViewModels/V2PersonalRollDetailViewModel.swift`
- `ios/snaproll/snaproll/App/V2/V2PersonalRollDetailView.swift`
- `ios/snaproll/snaprollTests/V2ExposureReconciliationCoordinatorTests.swift`
- `v2-docs/implementation-log.md`

### Reconciliation entry points

- Added `ExposureReconciling` as the repository/service boundary for local/cloud reconciliation.
- Added `V2ExposureReconciliationCoordinator` to compare cloud exposure state against the local exposure mirror.
- The live V2 dependency container now creates one reconciliation coordinator and injects it into pending-work recovery.
- Restart recovery now reconciles the roll before deciding which pending local work to resume.
- This phase does not add destructive repair, cloud image download, or background reconciliation.

### Field authority

- Cloud remains authoritative for:
  - exposure slot existence
  - `storage_path` / `cloud_storage_path`
  - `uploaded_at`
  - render seed
  - participant ownership
  - roll and participant lifecycle state fetched through repositories
- The device remains authoritative for:
  - `local_original_path`
  - `upload_jpeg_path`
  - `rendered_cache_path`
  - pending local workflow state
  - local diagnostics and retry metadata
- Reconciliation never deletes local originals, upload copies, rendered cache files, or cloud metadata.

### Local exposure metadata

- `LocalExposure` now stores:
  - `owner_user_id`
  - `last_reconciliation_rule`
  - `last_reconciliation_error`
  - `last_reconciled_at`
- The file-backed local exposure mirror persists these fields.
- Development diagnostics now show owner and reconciliation details when development visibility is enabled.

### Exposure reconciliation matrix

- Local `METADATA_PENDING` + cloud filled with the same canonical path:
  - mark local exposure `SYNCED`
  - clear local sync error
- Local `FAILED` with a cloud path + cloud filled with the same canonical path:
  - mark local exposure `SYNCED`
  - clear local sync error
- Local `LOCAL_ONLY` or `UPLOADING` + cloud empty:
  - normalize to `LOCAL_ONLY`
  - keep it retryable
- Local `METADATA_PENDING` + cloud empty:
  - keep `METADATA_PENDING`
  - retry metadata completion later
- Local `SYNCED` + cloud empty:
  - mark `FAILED`
  - record an unresolved consistency error
- Local and cloud both have non-null but different storage paths:
  - mark `FAILED`
  - record a hard `PATH_MISMATCH`
- Cloud exposure exists but local mirror is missing:
  - recreate a local mirror from cloud metadata
  - preserve participant ownership
- Local original is missing:
  - do not crash
  - do not delete cloud metadata
  - record a reconciliation diagnostic

### Identity safety

- Reconciled local exposure rows are stamped with `owner_user_id` from the participant record.
- `V2ExposureSyncRunner` now consults `AuthRepository` and skips locally mirrored exposures owned by a different current user.
- Pending-work recovery already scopes by current participant; reconciliation adds an additional guard for local rows that may survive development identity switching.
- Existing local rows without `owner_user_id` remain eligible for backward compatibility.

### Testing

- Added tests covering:
  - metadata-pending exposure becoming synced when cloud confirms the same path
  - failed exposure with a confirmed cloud path becoming synced
  - local-only exposure staying retryable when cloud is empty
  - metadata-pending exposure staying metadata-only when cloud is empty
  - synced exposure staying consistent when cloud matches
  - synced local exposure becoming failed when cloud is empty
  - non-null path mismatch becoming a hard failure
  - cloud exposure recreating a missing local mirror
  - missing local original preserving metadata and recording diagnostics
  - sync runner skipping exposure rows owned by a different development identity

### Build and test commands

- Focused tests:
  - `xcodebuild -project ios/snaproll/snaproll.xcodeproj -scheme snaproll -destination 'platform=iOS Simulator,OS=26.5,name=iPhone 17 Pro' -derivedDataPath /Users/zhengyu/Desktop/projects/snaproll/.deriveddata-phase14c-tests CODE_SIGNING_ALLOWED=NO -only-testing:snaprollTests/V2ExposureReconciliationCoordinatorTests -only-testing:snaprollTests/V2ExposureSyncRunnerTests -only-testing:snaprollTests/V2PendingExposureRecoveryCoordinatorTests test`
- Full build:
  - `xcodebuild -quiet -project ios/snaproll/snaproll.xcodeproj -scheme snaproll -destination 'generic/platform=iOS' -derivedDataPath /Users/zhengyu/Desktop/projects/snaproll/.deriveddata-phase14c-build CODE_SIGNING_ALLOWED=NO build`

### Results

- Focused Phase 14 recovery, reconciliation, and sync-runner tests passed.
- Full iOS project build passed.
- The full build emitted existing warnings around camera orientation APIs and V2 Supabase configuration actor isolation; these were not introduced by Phase 14C.

### Assumptions and follow-up work

- The repository still does not contain `v2-docs/phase-14-failure-recovery-context.md`; implementation followed `ARCHITECTURE.md`, the attached Phase 14C brief, and the current Phase 14A/14B code.
- This phase intentionally does not download missing cloud originals back to the device.
- This phase intentionally does not perform destructive local cleanup for orphaned files.
- Broader conflict resolution UI, repair tooling, background reconciliation, and cloud-original fallback remain future hardening work.

## Phase 15A – Join Shared Rolls via Invite Link

### Files changed

- `ios/snaproll/snaproll.xcodeproj/project.pbxproj`
- `ios/snaproll/snaproll/App/SnaprollApp.swift`
- `ios/snaproll/snaproll/App/V2/V2CloudHomeView.swift`
- `ios/snaproll/snaproll/App/V2/V2DependencyContainer.swift`
- `ios/snaproll/snaproll/App/V2/V2InviteRoutingCoordinator.swift`
- `ios/snaproll/snaproll/App/V2/V2RollInvitePreviewView.swift`
- `ios/snaproll/snaproll/App/V2/V2SessionBootstrap.swift`
- `ios/snaproll/snaproll/App/V2/V2SharedRollLobbyView.swift`
- `ios/snaproll/snaproll/Models/V2/RollInviteLink.swift`
- `ios/snaproll/snaproll/Repositories/SupabaseRepositories.swift`
- `ios/snaproll/snaproll/Repositories/V2RepositoryProtocols.swift`
- `ios/snaproll/snaproll/Utilities/AppConfig.swift`
- `ios/snaproll/snaproll/ViewModels/V2RollInvitePreviewViewModel.swift`
- `ios/snaproll/snaprollTests/RollInviteLinkTests.swift`
- `ios/snaproll/snaprollTests/V2InviteRoutingCoordinatorTests.swift`
- `ios/snaproll/snaprollTests/V2RollInvitePreviewViewModelTests.swift`
- `supabase/migrations/20260714120000_phase_15a_invite_preview_rpc.sql`
- `v2-docs/implementation-log.md`

### Invite link model

- Added `RollInviteLink` as the centralized invite-link generator/parser.
- Development links currently use the custom URL scheme:
  - `snaproll://join?token=<invite-token>`
- HTTPS links are supported by the same parser/generator once `AppConfig.V2.inviteHTTPSDomain` is configured:
  - `https://<domain>/join/<invite-token>`
  - `https://<domain>/join?token=<invite-token>`
- Invite tokens remain the backend source of truth. The URL is only a transport wrapper around the existing invite token.
- HTTPS path parsing uses `percentEncodedPath` so encoded token characters such as `/` cannot be mistaken for extra route segments.
- The custom scheme is registered in the generated app Info.plist build settings. Production Universal Links still require the Associated Domains entitlement and an Apple App Site Association file when the final domain exists.

### App-level routing

- Added `V2InviteRoutingCoordinator` to own pending invite routing state.
- `SnaprollApp` handles incoming URLs through `.onOpenURL` on the root SwiftUI view and forwards valid Snaproll invite URLs to the coordinator.
- Pending invite state is retained while the V2 session bootstrap resolves authentication, so a cold-start invite can be presented after sign-in.
- Successful join clears the pending invite and routes to the joined shared lobby.
- Invalid Snaproll invite links surface a lightweight alert instead of crashing or silently failing.

### Invite preview and join flow

- Added `InvitePreviewRepository` and `RollInvitePreview`.
- Added `SupabaseInvitePreviewRepository`, backed by the new read-only RPC `get_roll_invite_preview(token)`.
- Added `V2RollInvitePreviewViewModel` and `V2RollInvitePreviewView`.
- Opening an invite link now presents a preview before joining:
  - roll title
  - creator display name when available
  - participant count/cap
  - exposure count
  - status
- Joining still calls the existing `ParticipantRepository.joinRoll(...)` path, which uses the approved `join_roll()` RPC. No join business logic moved into iOS.
- Already-joined errors route the user to the existing roll when the preview has enough context.
- Invalid, inactive, already-started, full, and network failure states are mapped into user-readable messages.

### Shared-roll UI changes

- Creator invite actions now use native `ShareLink` instead of manual token copying in normal UI.
- Manual token entry remains available only when `AppConfig.V2.showsDeveloperUI` is true.
- Shared lobby invite display now shares the generated invite link. Raw token/link diagnostics are shown only in developer UI.

### Database migration

- Added `20260714120000_phase_15a_invite_preview_rpc.sql`.
- The migration creates `public.get_roll_invite_preview(p_invite_token text)`.
- The function is read-only, security-definer, requires an authenticated profile, and returns only the preview fields required before explicit join.
- The function does not replace `join_roll()` and does not mutate invite, roll, participant, exposure, or storage state.
- The migration must be applied with `supabase db push` before cloud-backed invite previews work on device.

### Build and test commands

- Focused tests:
  - `xcodebuild -quiet -project ios/snaproll/snaproll.xcodeproj -scheme snaproll -destination 'platform=iOS Simulator,OS=26.5,name=iPhone 17 Pro' -derivedDataPath /Users/zhengyu/Desktop/projects/snaproll/.deriveddata-phase15a-tests CODE_SIGNING_ALLOWED=NO -only-testing:snaprollTests/RollInviteLinkTests -only-testing:snaprollTests/V2InviteRoutingCoordinatorTests -only-testing:snaprollTests/V2RollInvitePreviewViewModelTests -only-testing:snaprollTests/V2CloudHomeViewModelTests -only-testing:snaprollTests/V2SharedRollLobbyViewModelTests test`
- Full build:
  - `xcodebuild -quiet -project ios/snaproll/snaproll.xcodeproj -scheme snaproll -destination 'generic/platform=iOS' -derivedDataPath /Users/zhengyu/Desktop/projects/snaproll/.deriveddata-phase15a-build CODE_SIGNING_ALLOWED=NO build`

### Results

- Focused Phase 15A invite-link, routing, preview, cloud-home, and shared-lobby tests passed.
- Full iOS project build passed.
- The full build emitted existing warnings around camera orientation APIs and V2 Supabase configuration actor isolation; these were not introduced by Phase 15A.

### Assumptions and follow-up work

- Manual device validation was not performed in this implementation pass.
- Production HTTPS Universal Links are prepared in code but not fully enabled until the production invite domain, Associated Domains entitlement, and AASA file exist.
- Invite routing state is intentionally in-memory; iOS should deliver the opening URL at launch, after which the coordinator retains it through bootstrap.
- Manual token entry is retained for developer/debug workflows only.
