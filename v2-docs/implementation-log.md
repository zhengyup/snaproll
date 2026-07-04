# V2 Implementation Log

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
