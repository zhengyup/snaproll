# Phase 2 RPC Test Plan

## Purpose

This document is a manual SQL test plan for the Snaproll V2 RPC layer before iOS integration begins.

It covers:

- roll creation
- invite flow
- participant flow
- start and exposure-slot creation
- exposure completion
- reveal and force reveal
- invite regeneration

It does **not** apply migrations or modify application code.

---

## Scope

RPCs under test:

- `create_roll(...)`
- `join_roll(...)`
- `leave_roll(...)`
- `start_roll(...)`
- `reveal_roll(...)`
- `force_reveal_roll(...)`
- `regenerate_invite(...)`
- `complete_exposure(...)`

Relevant architecture invariants:

- creator is also a participant
- shared-roll joins are invite-driven
- exposures are created only by `start_roll()`
- roll lifecycle is RPC-owned
- invite links remain viewable after start
- joining after start must fail
- exposure completion must enforce canonical storage path

Important verification note:

- The approved architecture shows padded exposure filenames, for example `001.jpg`, even though the current Phase 2 RPC migration still formats paths as unpadded values such as `1.jpg`.
- This test plan follows the approved architecture and intended product contract:
  `rolls/{roll_id}/participants/{participant_id}/{exposure_number_padded_to_3_digits}.jpg`
- Before executing the `complete_exposure()` tests exactly as written, the RPC migration should be aligned to this padded-number convention.

---

## Recommended Test Environment

Use the Supabase SQL Editor or a privileged Postgres session where you can:

- insert fixture rows into `auth.users`
- insert/update fixture rows in `public.profiles`
- call SQL functions
- inspect table state directly

Recommended approach:

1. Run the Phase 1 and Phase 2 migrations in a disposable local or staging database.
2. Run the setup SQL in this document.
3. Execute each test case in order.
4. Clean up by deleting the fixture users/rolls after the run.

---

## Test Data Setup

### Fixture IDs

Use fixed UUIDs so the queries stay readable.

```sql
-- User IDs
-- creator_shared
-- participant_a
-- participant_b
-- no_display_name_user
-- creator_personal

-- These are example UUIDs. Replace only if your environment requires it.
```

```sql
-- Clean old fixture rows if re-running.
delete from public.exposures where roll_id in (
  '10000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000002'
);
delete from public.invites where roll_id in (
  '10000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000002'
);
delete from public.roll_participants where roll_id in (
  '10000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000002'
);
delete from public.rolls where id in (
  '10000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000002'
);

delete from public.profiles where id in (
  '00000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000002',
  '00000000-0000-0000-0000-000000000003',
  '00000000-0000-0000-0000-000000000004',
  '00000000-0000-0000-0000-000000000005'
);

delete from auth.users where id in (
  '00000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000002',
  '00000000-0000-0000-0000-000000000003',
  '00000000-0000-0000-0000-000000000004',
  '00000000-0000-0000-0000-000000000005'
);
```

### Create auth.users fixtures

Note:

- `auth.users` required columns may vary slightly by Supabase version.
- If your environment rejects this exact insert, adapt only the non-essential auth metadata columns.

```sql
insert into auth.users (
  id,
  instance_id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
)
values
  (
    '00000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'creator-shared@example.com',
    crypt('password', gen_salt('bf')),
    timezone('utc', now()),
    '{}'::jsonb,
    '{}'::jsonb,
    timezone('utc', now()),
    timezone('utc', now())
  ),
  (
    '00000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'participant-a@example.com',
    crypt('password', gen_salt('bf')),
    timezone('utc', now()),
    '{}'::jsonb,
    '{}'::jsonb,
    timezone('utc', now()),
    timezone('utc', now())
  ),
  (
    '00000000-0000-0000-0000-000000000003',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'participant-b@example.com',
    crypt('password', gen_salt('bf')),
    timezone('utc', now()),
    '{}'::jsonb,
    '{}'::jsonb,
    timezone('utc', now()),
    timezone('utc', now())
  ),
  (
    '00000000-0000-0000-0000-000000000004',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'no-display-name@example.com',
    crypt('password', gen_salt('bf')),
    timezone('utc', now()),
    '{}'::jsonb,
    '{}'::jsonb,
    timezone('utc', now()),
    timezone('utc', now())
  ),
  (
    '00000000-0000-0000-0000-000000000005',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'creator-personal@example.com',
    crypt('password', gen_salt('bf')),
    timezone('utc', now()),
    '{}'::jsonb,
    '{}'::jsonb,
    timezone('utc', now()),
    timezone('utc', now())
  );
```

### Create profiles fixtures

```sql
insert into public.profiles (id, display_name)
values
  ('00000000-0000-0000-0000-000000000001', 'Shared Creator'),
  ('00000000-0000-0000-0000-000000000002', 'Participant A'),
  ('00000000-0000-0000-0000-000000000003', 'Participant B'),
  ('00000000-0000-0000-0000-000000000004', null),
  ('00000000-0000-0000-0000-000000000005', 'Personal Creator');
```

---

## Acting As A User

The RPCs rely on `auth.uid()`. In SQL testing, simulate the caller by setting the JWT subject claim before each RPC call.

Use this pattern:

```sql
select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000001',
  true
);
```

Suggested actor mapping:

- `00000000-0000-0000-0000-000000000001` = shared creator
- `00000000-0000-0000-0000-000000000002` = participant A
- `00000000-0000-0000-0000-000000000003` = participant B
- `00000000-0000-0000-0000-000000000004` = no-display-name user
- `00000000-0000-0000-0000-000000000005` = personal creator

---

## Helpful Inspection Queries

### Inspect a roll

```sql
select *
from public.rolls
where id = '10000000-0000-0000-0000-000000000001';
```

### Inspect participants

```sql
select id, roll_id, user_id, status, joined_at, finished_at
from public.roll_participants
where roll_id = '10000000-0000-0000-0000-000000000001'
order by joined_at, user_id;
```

### Inspect invites

```sql
select id, roll_id, token, is_active, created_at, revoked_at
from public.invites
where roll_id = '10000000-0000-0000-0000-000000000001'
order by created_at;
```

### Inspect exposures

```sql
select id, roll_id, participant_id, exposure_number, storage_path, uploaded_at
from public.exposures
where roll_id = '10000000-0000-0000-0000-000000000001'
order by participant_id, exposure_number;
```

---

## Test Cases

### 1. Create personal roll

Goal:

- verify personal roll creation succeeds
- verify personal roll starts in `DRAFT`
- verify no invite is created
- verify no exposures are created yet

SQL:

```sql
select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000005',
  true
);

select *
from public.create_roll(
  p_title => 'Solo Summer',
  p_type => 'PERSONAL',
  p_film_stock_id => 'kodakGold200',
  p_exposures_per_participant => 12,
  p_participant_cap => 1
);
```

Expected database state:

- one new row in `rolls`
- `rolls.type = 'PERSONAL'`
- `rolls.status = 'DRAFT'`
- `rolls.creator_id = personal creator id`
- one new row in `roll_participants`
- participant row belongs to creator
- participant status is `JOINED`
- zero rows in `invites` for this roll
- zero rows in `exposures` for this roll

Verification SQL:

```sql
select type, status, creator_id, film_stock_id, exposures_per_participant, participant_cap
from public.rolls
where creator_id = '00000000-0000-0000-0000-000000000005'
order by created_at desc
limit 1;
```

---

### 2. Create shared roll

Goal:

- verify shared roll creation succeeds
- verify shared roll starts in `WAITING_FOR_PARTICIPANTS`
- verify invite is created

SQL:

```sql
select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000001',
  true
);

select *
from public.create_roll(
  p_title => 'Weekend Trip',
  p_type => 'SHARED',
  p_film_stock_id => 'fujifilmSuperia400',
  p_exposures_per_participant => 12,
  p_participant_cap => 3
);
```

Expected database state:

- one new row in `rolls`
- `rolls.type = 'SHARED'`
- `rolls.status = 'WAITING_FOR_PARTICIPANTS'`
- exactly one participant row for creator
- exactly one invite row
- invite `is_active = true`
- invite `revoked_at is null`
- zero exposures

Store the resulting `roll_id` and `invite_token` for the next tests.

For the rest of this document, assume:

- shared roll id = `:shared_roll_id`
- active invite token = `:invite_token_1`

---

### 3. Creator becomes participant

Goal:

- verify `create_roll()` inserted the creator into `roll_participants`

SQL:

```sql
select user_id, status
from public.roll_participants
where roll_id = :shared_roll_id;
```

Expected database state:

- exactly one row
- `user_id = shared creator id`
- `status = 'JOINED'`

---

### 4. Shared roll creates active invite

Goal:

- verify shared creation produced one active invite

SQL:

```sql
select token, is_active, revoked_at
from public.invites
where roll_id = :shared_roll_id;
```

Expected database state:

- exactly one invite row
- `token = :invite_token_1`
- `is_active = true`
- `revoked_at is null`

---

### 5. Join via invite

Goal:

- verify another user can join a waiting shared roll

SQL:

```sql
select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000002',
  true
);

select *
from public.join_roll(:invite_token_1);
```

Expected database state:

- one additional row in `roll_participants`
- user `participant_a` is now present on the roll
- participant status is `JOINED`
- invite remains active

Verification SQL:

```sql
select user_id, status
from public.roll_participants
where roll_id = :shared_roll_id
order by user_id;
```

---

### 6. Duplicate join rejection

Goal:

- verify the same user cannot join twice

SQL:

```sql
select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000002',
  true
);

select *
from public.join_roll(:invite_token_1);
```

Expected result:

- RPC raises an error
- message should indicate the caller is already a participant

Expected database state:

- participant count remains unchanged

---

### 7. Participant cap enforcement

Goal:

- verify a roll at cap rejects additional joins

Setup:

1. `participant_b` joins successfully.
2. no-display-name user should not be used here because that failure path is covered separately by the shared-display-name validation and would mask participant-cap behavior.
3. create one more fixture user with a display name only if needed in your environment.

Suggested variant with current fixtures:

- create a separate shared roll with `participant_cap = 2`
- creator joins automatically
- `participant_a` joins
- `participant_b` should be rejected

SQL:

```sql
select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000001',
  true
);

select *
from public.create_roll(
  p_title => 'Cap Two Roll',
  p_type => 'SHARED',
  p_film_stock_id => 'kodakGold200',
  p_exposures_per_participant => 12,
  p_participant_cap => 2
);
```

Then:

```sql
select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000002',
  true
);
select * from public.join_roll(:cap_two_invite_token);
```

Then:

```sql
select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000003',
  true
);
select * from public.join_roll(:cap_two_invite_token);
```

Expected result:

- third participant attempt fails with participant-cap error

Expected database state:

- exactly two participants on that roll

---

### 8. Start roll creates exposure slots

Goal:

- verify `start_roll()` creates `exposures_per_participant * participant_count` slots

Setup:

- ensure `participant_b` has joined the main shared roll first

SQL:

```sql
select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000003',
  true
);

select *
from public.join_roll(:invite_token_1);
```

Start:

```sql
select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000001',
  true
);

select public.start_roll(:shared_roll_id);
```

Expected database state:

- roll status becomes `SHOOTING`
- `started_at` is populated
- all participants status become `SHOOTING`
- exposures count = `3 participants * 12 exposures = 36`
- each participant has exposure numbers `1..12`

Verification SQL:

```sql
select status, started_at
from public.rolls
where id = :shared_roll_id;

select user_id, status, finished_at
from public.roll_participants
where roll_id = :shared_roll_id
order by user_id;

select participant_id, count(*) as exposure_count, min(exposure_number), max(exposure_number)
from public.exposures
where roll_id = :shared_roll_id
group by participant_id
order by participant_id;
```

---

### 9. Start roll locks participants

Goal:

- verify join attempts after start fail
- verify invite still exists and is still viewable in the database

SQL:

```sql
select token, is_active, revoked_at
from public.invites
where roll_id = :shared_roll_id;
```

Expected database state:

- invite row still exists
- token remains available for lookup
- join logic, not invite revocation, prevents entry

Join attempt:

```sql
select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000004',
  true
);

select *
from public.join_roll(:invite_token_1);
```

Expected result:

- RPC fails
- error should indicate the roll has already started

Note:

- because this fixture user also lacks a display name, use another valid-display-name user if you want to isolate only the “already started” failure path
- if you use this user, the display-name validation will fire earlier and is still a valid result for shared participation rules

---

### 10. Complete one exposure successfully

Goal:

- verify `complete_exposure()` fills exactly one empty exposure

Setup:

- pick one exposure owned by `participant_a`

SQL:

```sql
select e.id, e.roll_id, e.participant_id, e.exposure_number
from public.exposures e
join public.roll_participants rp on rp.id = e.participant_id
where e.roll_id = :shared_roll_id
  and rp.user_id = '00000000-0000-0000-0000-000000000002'
order by e.exposure_number
limit 1;
```

Assume:

- exposure id = `:participant_a_exposure_1`
- participant id = `:participant_a_id`

Expected canonical path:

```text
rolls/{shared_roll_id}/participants/{participant_a_id}/001.jpg
```

Call:

```sql
select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000002',
  true
);

select *
from public.complete_exposure(
  :participant_a_exposure_1,
  format(
    'rolls/%s/participants/%s/%s.jpg',
    :shared_roll_id,
    :participant_a_id,
    lpad('1', 3, '0')
  )
);
```

Expected database state:

- that exposure now has `storage_path`
- `uploaded_at` is populated
- participant still remains `SHOOTING` because only 1 of 12 is complete
- roll remains `SHOOTING`

---

### 11. complete_exposure rejects wrong storage path

Goal:

- verify canonical storage path enforcement works

SQL:

```sql
select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000002',
  true
);

select *
from public.complete_exposure(
  :another_empty_exposure_for_participant_a,
  'rolls/wrong/participants/wrong/999.jpg'
);
```

Expected result:

- RPC fails
- error should mention canonical exposure path mismatch

Expected database state:

- target exposure remains empty
- `storage_path is null`
- `uploaded_at is null`

---

### 12. Participant becomes FINISHED when all exposures complete

Goal:

- verify participant status flips to `FINISHED` only after their final exposure is completed

Setup:

- complete all 12 exposures for `participant_a`

Suggested helper query:

```sql
select e.id, e.roll_id, e.participant_id, e.exposure_number
from public.exposures e
join public.roll_participants rp on rp.id = e.participant_id
where e.roll_id = :shared_roll_id
  and rp.user_id = '00000000-0000-0000-0000-000000000002'
order by e.exposure_number;
```

For each exposure, call:

```sql
select *
from public.complete_exposure(
  :exposure_id,
  format(
    'rolls/%s/participants/%s/%s.jpg',
    :shared_roll_id,
    :participant_a_id,
    lpad(:exposure_number::text, 3, '0')
  )
);
```

Expected database state after exposure 12:

- all participant A exposures are filled
- participant A status = `FINISHED`
- participant A `finished_at` is populated
- roll remains `SHOOTING` unless every participant is also complete

Verification SQL:

```sql
select status, finished_at
from public.roll_participants
where id = :participant_a_id;
```

---

### 13. Roll becomes READY_TO_REVEAL when all participants finish

Goal:

- verify roll status becomes `READY_TO_REVEAL` only after every participant has completed all exposures

Setup:

- complete all exposures for creator and participant B as well

Expected database state after the final remaining exposure:

- every exposure in the roll has non-null `storage_path`
- every participant status = `FINISHED`
- roll status = `READY_TO_REVEAL`
- `ready_to_reveal_at` is populated

Verification SQL:

```sql
select status, ready_to_reveal_at, revealed_at
from public.rolls
where id = :shared_roll_id;

select user_id, status, finished_at
from public.roll_participants
where roll_id = :shared_roll_id
order by user_id;
```

---

### 14. reveal_roll only works when READY_TO_REVEAL

Goal:

- verify premature reveal fails
- verify valid reveal succeeds once ready

Premature reveal setup:

- create a second shared roll
- start it
- do not complete all exposures

Call:

```sql
select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000001',
  true
);

select public.reveal_roll(:not_ready_roll_id);
```

Expected result:

- RPC fails
- error says roll must be `READY_TO_REVEAL`

Valid reveal call:

```sql
select public.reveal_roll(:shared_roll_id);
```

Expected database state:

- roll status = `REVEALED`
- `revealed_at` is populated

---

### 15. force_reveal_roll works with incomplete exposures

Goal:

- verify creator can reveal a started roll before all exposures are complete

Setup:

- create a separate shared roll
- join at least one participant
- start the roll
- complete only some exposures

Call:

```sql
select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000001',
  true
);

select public.force_reveal_roll(:force_reveal_roll_id);
```

Expected database state:

- roll status = `REVEALED`
- `revealed_at` is populated
- completed exposures retain their `storage_path`
- empty exposures remain empty
- no exposure rows are deleted

Verification SQL:

```sql
select status, revealed_at
from public.rolls
where id = :force_reveal_roll_id;

select exposure_number, storage_path
from public.exposures
where roll_id = :force_reveal_roll_id
order by participant_id, exposure_number;
```

---

### 16. regenerate_invite revokes old invite and creates new active invite

Goal:

- verify invite regeneration produces exactly one new active invite and revokes the old one

Setup:

- use a waiting shared roll that has not started yet

Call:

```sql
select set_config(
  'request.jwt.claim.sub',
  '00000000-0000-0000-0000-000000000001',
  true
);

select public.regenerate_invite(:waiting_roll_id);
```

Expected database state:

- previous invite row now has:
  - `is_active = false`
  - `revoked_at is not null`
- one new invite row exists with:
  - new token
  - `is_active = true`
  - `revoked_at is null`
- total invite history for the roll is now at least 2 rows
- only one active invite exists

Verification SQL:

```sql
select token, is_active, revoked_at, created_at
from public.invites
where roll_id = :waiting_roll_id
order by created_at;
```

---

## Optional Negative Tests

These are useful but not required for the minimum Phase 2 signoff:

- `create_roll(type = 'SHARED')` fails for profile with `display_name is null`
- `join_roll()` fails for profile with `display_name is null`
- `leave_roll()` fails for creator
- `start_roll()` fails for non-creator
- `reveal_roll()` fails for non-creator
- `force_reveal_roll()` fails for non-creator
- `complete_exposure()` fails when caller does not own the exposure
- `complete_exposure()` fails on already-filled exposure

---

## Cleanup

If you want to remove all fixture data after the run:

```sql
delete from public.exposures;
delete from public.invites;
delete from public.roll_participants;
delete from public.rolls;

delete from public.profiles where id in (
  '00000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000002',
  '00000000-0000-0000-0000-000000000003',
  '00000000-0000-0000-0000-000000000004',
  '00000000-0000-0000-0000-000000000005'
);

delete from auth.users where id in (
  '00000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000002',
  '00000000-0000-0000-0000-000000000003',
  '00000000-0000-0000-0000-000000000004',
  '00000000-0000-0000-0000-000000000005'
);
```

---

## Exit Criteria

Phase 2 RPCs are ready for iOS integration when all of the following pass:

- personal roll creation works
- shared roll creation works
- creator is inserted as participant
- active invite is created for shared rolls
- join works before start
- duplicate joins fail
- joins fail after start
- participant cap is enforced
- `start_roll()` creates the expected exposure slots
- `complete_exposure()` fills only valid empty slots
- wrong storage paths are rejected
- participant completion updates correctly
- roll completion updates correctly
- `reveal_roll()` only succeeds from `READY_TO_REVEAL`
- `force_reveal_roll()` preserves filled exposures and reveals incomplete rolls
- `regenerate_invite()` revokes the old invite and creates one active replacement
