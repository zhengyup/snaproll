-- Snaproll V2 RPC happy path smoke test
--
-- Run this file top-to-bottom in Supabase SQL Editor against a disposable or
-- non-production cloud project after the Phase 1 and Phase 2 migrations have
-- been applied.
--
-- What this script covers:
-- - clean previous fixture data
-- - create fixture auth.users
-- - create fixture profiles
-- - simulate auth.uid() with set_config
-- - create a shared roll
-- - verify creator becomes participant
-- - verify invite is created
-- - join as another participant
-- - start the roll
-- - verify exposure slots are created
-- - verify invite still exists after start
-- - verify join after start fails
-- - complete one exposure using padded path 001.jpg
-- - verify wrong storage path fails
--
-- Cleanup runs at the end. If you want to inspect the final state first,
-- comment out the final cleanup section before running.

do $$
declare
  creator_shared_id constant uuid := '00000000-0000-0000-0000-000000000001';
  participant_a_id constant uuid := '00000000-0000-0000-0000-000000000002';
  participant_b_id constant uuid := '00000000-0000-0000-0000-000000000003';
  no_display_name_id constant uuid := '00000000-0000-0000-0000-000000000004';
  creator_personal_id constant uuid := '00000000-0000-0000-0000-000000000005';
  auth_instance_id constant uuid := '00000000-0000-0000-0000-000000000000';

  shared_roll_id uuid;
  invite_token_1 text;
  joined_participant_id uuid;
  creator_participant_id uuid;
  exposure_slot_count integer;
  active_invite_count integer;
  participant_count integer;
  participant_a_roll_participant_id uuid;
  participant_a_exposure_001_id uuid;
  participant_finished boolean;
  roll_ready_to_reveal boolean;
  wrong_path_failed boolean := false;
  join_after_start_failed boolean := false;
begin
  raise notice 'Starting Snaproll RPC happy path smoke test';

  -- Cleanup from any previous run.
  delete from public.rolls
  where creator_id in (
    creator_shared_id,
    participant_a_id,
    participant_b_id,
    no_display_name_id,
    creator_personal_id
  );

  delete from public.profiles
  where id in (
    creator_shared_id,
    participant_a_id,
    participant_b_id,
    no_display_name_id,
    creator_personal_id
  );

  delete from auth.users
  where id in (
    creator_shared_id,
    participant_a_id,
    participant_b_id,
    no_display_name_id,
    creator_personal_id
  );

  -- Create fixture auth.users.
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
      creator_shared_id,
      auth_instance_id,
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
      participant_a_id,
      auth_instance_id,
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
      participant_b_id,
      auth_instance_id,
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
      no_display_name_id,
      auth_instance_id,
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
      creator_personal_id,
      auth_instance_id,
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

  -- Create fixture profiles.
  insert into public.profiles (id, display_name)
  values
    (creator_shared_id, 'Shared Creator'),
    (participant_a_id, 'Participant A'),
    (participant_b_id, 'Participant B'),
    (no_display_name_id, null),
    (creator_personal_id, 'Personal Creator');

  raise notice 'Fixtures created';

  -- Create shared roll as creator.
  perform set_config('request.jwt.claim.sub', creator_shared_id::text, true);

  select cr.roll_id, cr.invite_token
  into shared_roll_id, invite_token_1
  from public.create_roll(
    p_title => 'RPC Happy Path Shared Roll',
    p_type => 'SHARED',
    p_film_stock_id => 'fujifilmSuperia400',
    p_exposures_per_participant => 12,
    p_participant_cap => 3
  ) as cr;

  if shared_roll_id is null then
    raise exception 'Expected create_roll() to return a roll_id';
  end if;

  if invite_token_1 is null or btrim(invite_token_1) = '' then
    raise exception 'Expected create_roll() to return an active invite token for shared rolls';
  end if;

  if not exists (
    select 1
    from public.rolls
    where id = shared_roll_id
      and creator_id = creator_shared_id
      and type = 'SHARED'
      and status = 'WAITING_FOR_PARTICIPANTS'
      and exposures_per_participant = 12
      and participant_cap = 3
  ) then
    raise exception 'Shared roll was not created in the expected initial state';
  end if;

  -- Verify creator becomes participant.
  select id
  into creator_participant_id
  from public.roll_participants
  where roll_id = shared_roll_id
    and user_id = creator_shared_id
    and status = 'JOINED';

  if creator_participant_id is null then
    raise exception 'Creator was not inserted into roll_participants';
  end if;

  -- Verify active invite exists.
  select count(*)
  into active_invite_count
  from public.invites
  where roll_id = shared_roll_id
    and token = invite_token_1
    and is_active = true
    and revoked_at is null;

  if active_invite_count <> 1 then
    raise exception 'Expected exactly one active invite after create_roll(), found %', active_invite_count;
  end if;

  raise notice 'Shared roll creation assertions passed';

  -- Join as participant A.
  perform set_config('request.jwt.claim.sub', participant_a_id::text, true);

  select jr.roll_id, jr.participant_id
  into shared_roll_id, joined_participant_id
  from public.join_roll(invite_token_1) as jr;

  if joined_participant_id is null then
    raise exception 'Expected join_roll() to return a participant_id';
  end if;

  select count(*)
  into participant_count
  from public.roll_participants
  where roll_id = shared_roll_id;

  if participant_count <> 2 then
    raise exception 'Expected 2 participants after join, found %', participant_count;
  end if;

  if not exists (
    select 1
    from public.roll_participants
    where id = joined_participant_id
      and roll_id = shared_roll_id
      and user_id = participant_a_id
      and status = 'JOINED'
  ) then
    raise exception 'Participant A was not inserted in JOINED state';
  end if;

  raise notice 'Join assertions passed';

  -- Start the roll as creator.
  perform set_config('request.jwt.claim.sub', creator_shared_id::text, true);

  exposure_slot_count := public.start_roll(shared_roll_id);

  if exposure_slot_count <> 24 then
    raise exception 'Expected 24 exposure slots after start_roll(), found %', exposure_slot_count;
  end if;

  if not exists (
    select 1
    from public.rolls
    where id = shared_roll_id
      and status = 'SHOOTING'
      and started_at is not null
  ) then
    raise exception 'Roll did not transition to SHOOTING after start_roll()';
  end if;

  if exists (
    select 1
    from public.roll_participants
    where roll_id = shared_roll_id
      and status <> 'SHOOTING'
  ) then
    raise exception 'Not all participants transitioned to SHOOTING after start_roll()';
  end if;

  select count(*)
  into active_invite_count
  from public.invites
  where roll_id = shared_roll_id
    and token = invite_token_1;

  if active_invite_count <> 1 then
    raise exception 'Expected original invite row to remain after start_roll(), found % rows', active_invite_count;
  end if;

  raise notice 'Start assertions passed';

  -- Join after start should fail.
  perform set_config('request.jwt.claim.sub', participant_b_id::text, true);

  begin
    perform *
    from public.join_roll(invite_token_1);
  exception
    when others then
      join_after_start_failed := position('already started' in lower(sqlerrm)) > 0
        or position('cannot accept new participants' in lower(sqlerrm)) > 0;
  end;

  if not join_after_start_failed then
    raise exception 'Expected join_roll() to fail after start_roll()';
  end if;

  select count(*)
  into participant_count
  from public.roll_participants
  where roll_id = shared_roll_id;

  if participant_count <> 2 then
    raise exception 'Participant count changed after failed post-start join attempt';
  end if;

  raise notice 'Post-start join rejection passed';

  -- Complete one valid exposure as participant A.
  select id
  into participant_a_roll_participant_id
  from public.roll_participants
  where roll_id = shared_roll_id
    and user_id = participant_a_id;

  if participant_a_roll_participant_id is null then
    raise exception 'Could not find participant A roll_participants row';
  end if;

  select id
  into participant_a_exposure_001_id
  from public.exposures
  where roll_id = shared_roll_id
    and participant_id = participant_a_roll_participant_id
    and exposure_number = 1;

  if participant_a_exposure_001_id is null then
    raise exception 'Could not find participant A exposure #1';
  end if;

  perform set_config('request.jwt.claim.sub', participant_a_id::text, true);

  select ce.participant_finished, ce.roll_ready_to_reveal
  into participant_finished, roll_ready_to_reveal
  from public.complete_exposure(
    participant_a_exposure_001_id,
    format(
      'rolls/%s/participants/%s/%s.jpg',
      shared_roll_id,
      participant_a_roll_participant_id,
      lpad('1', 3, '0')
    )
  ) as ce;

  if participant_finished then
    raise exception 'Participant should not be FINISHED after only one completed exposure';
  end if;

  if roll_ready_to_reveal then
    raise exception 'Roll should not be READY_TO_REVEAL after only one completed exposure';
  end if;

  if not exists (
    select 1
    from public.exposures
    where id = participant_a_exposure_001_id
      and storage_path = format(
        'rolls/%s/participants/%s/%s.jpg',
        shared_roll_id,
        participant_a_roll_participant_id,
        lpad('1', 3, '0')
      )
      and uploaded_at is not null
  ) then
    raise exception 'Exposure #1 was not populated with the expected padded storage path';
  end if;

  if not exists (
    select 1
    from public.roll_participants
    where id = participant_a_roll_participant_id
      and status = 'SHOOTING'
  ) then
    raise exception 'Participant A should still be SHOOTING after one completed exposure';
  end if;

  if not exists (
    select 1
    from public.rolls
    where id = shared_roll_id
      and status = 'SHOOTING'
  ) then
    raise exception 'Roll should still be SHOOTING after one completed exposure';
  end if;

  raise notice 'Valid exposure completion passed';

  -- Wrong storage path should fail.
  begin
    perform *
    from public.complete_exposure(
      (
        select id
        from public.exposures
        where roll_id = shared_roll_id
          and participant_id = participant_a_roll_participant_id
          and exposure_number = 2
      ),
      'rolls/wrong/participants/wrong/999.jpg'
    );
  exception
    when others then
      wrong_path_failed := position('canonical exposure path' in lower(sqlerrm)) > 0
        or position('storage_path must match' in lower(sqlerrm)) > 0;
  end;

  if not wrong_path_failed then
    raise exception 'Expected complete_exposure() to reject the wrong storage path';
  end if;

  if exists (
    select 1
    from public.exposures
    where roll_id = shared_roll_id
      and participant_id = participant_a_roll_participant_id
      and exposure_number = 2
      and storage_path is not null
  ) then
    raise exception 'Exposure #2 should remain empty after wrong path rejection';
  end if;

  raise notice 'Wrong-path rejection passed';
  raise notice 'Snaproll RPC happy path smoke test PASSED';
end;
$$;

-- Final cleanup section.
-- Comment this out if you want to inspect the resulting fixture state manually.
do $$
declare
  creator_shared_id constant uuid := '00000000-0000-0000-0000-000000000001';
  participant_a_id constant uuid := '00000000-0000-0000-0000-000000000002';
  participant_b_id constant uuid := '00000000-0000-0000-0000-000000000003';
  no_display_name_id constant uuid := '00000000-0000-0000-0000-000000000004';
  creator_personal_id constant uuid := '00000000-0000-0000-0000-000000000005';
begin
  delete from public.rolls
  where creator_id in (
    creator_shared_id,
    participant_a_id,
    participant_b_id,
    no_display_name_id,
    creator_personal_id
  );

  delete from public.profiles
  where id in (
    creator_shared_id,
    participant_a_id,
    participant_b_id,
    no_display_name_id,
    creator_personal_id
  );

  delete from auth.users
  where id in (
    creator_shared_id,
    participant_a_id,
    participant_b_id,
    no_display_name_id,
    creator_personal_id
  );

  raise notice 'Fixture cleanup complete';
end;
$$;
