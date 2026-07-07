# V2 Implementation Log

## Documentation Update – Roadmap and Authentication Strategy

- Reordered the V2 implementation roadmap to reflect the approved sequence from Phase 0 through Phase 13.
- Added a Development Authentication strategy to the architecture:
  - authentication remains provider-agnostic
  - `AuthRepository` remains the only auth boundary
  - shared-roll features depend on `AuthRepository`, not directly on Google Sign-In or Apple Sign In
- Deferred production authentication to Phase 12:
  - Google Sign-In initially
  - Apple Sign In before App Store release
- Rationale:
  - faster product iteration
  - easier manual testing
  - avoids blocking development on Apple Developer Program enrollment
  - preserves clean architecture

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
  - `SNAPROLL_SUPABASE_ANON_KEY`
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
