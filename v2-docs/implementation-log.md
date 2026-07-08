# V2 Implementation Log

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
