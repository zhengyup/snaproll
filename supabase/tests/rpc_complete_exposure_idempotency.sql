-- Snaproll V2 complete_exposure() idempotency smoke test
--
-- Run this file top-to-bottom in Supabase SQL Editor against a disposable or
-- non-production cloud project after the Phase 14B migration has been applied.

do $$
declare
  test_user_id constant uuid := '00000000-0000-0000-0000-000000001401';
  test_roll_id constant uuid := '00000000-0000-0000-0000-000000001402';
  test_participant_id constant uuid := '00000000-0000-0000-0000-000000001403';
  test_exposure_id constant uuid := '00000000-0000-0000-0000-000000001404';
  auth_instance_id constant uuid := '00000000-0000-0000-0000-000000000000';
  canonical_path text := 'rolls/00000000-0000-0000-0000-000000001402/participants/00000000-0000-0000-0000-000000001403/001.jpg';
  different_path_failed boolean := false;
  first_result record;
  second_result record;
begin
  raise notice 'Starting complete_exposure() idempotency smoke test';

  delete from public.rolls where id = test_roll_id;
  delete from public.profiles where id = test_user_id;
  delete from auth.users where id = test_user_id;

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
  values (
    test_user_id,
    auth_instance_id,
    'authenticated',
    'authenticated',
    'phase14b@example.com',
    crypt('password', gen_salt('bf')),
    timezone('utc', now()),
    '{}'::jsonb,
    '{}'::jsonb,
    timezone('utc', now()),
    timezone('utc', now())
  );

  insert into public.profiles (id, display_name)
  values (test_user_id, 'Phase 14B Tester');

  insert into public.rolls (
    id,
    creator_id,
    title,
    type,
    status,
    film_stock_id,
    exposures_per_participant,
    participant_cap,
    started_at
  )
  values (
    test_roll_id,
    test_user_id,
    'Phase 14B Idempotency Roll',
    'PERSONAL',
    'SHOOTING',
    'kodakGold200',
    12,
    1,
    timezone('utc', now())
  );

  insert into public.roll_participants (
    id,
    roll_id,
    user_id,
    status
  )
  values (
    test_participant_id,
    test_roll_id,
    test_user_id,
    'SHOOTING'
  );

  insert into public.exposures (
    id,
    roll_id,
    participant_id,
    exposure_number,
    render_seed
  )
  values (
    test_exposure_id,
    test_roll_id,
    test_participant_id,
    1,
    'phase-14b-seed'
  );

  perform set_config('request.jwt.claim.sub', test_user_id::text, true);

  select *
  into first_result
  from public.complete_exposure(test_exposure_id, canonical_path);

  if not exists (
    select 1
    from public.exposures e
    where e.id = test_exposure_id
      and e.storage_path = canonical_path
      and e.uploaded_at is not null
  ) then
    raise exception 'Expected first complete_exposure() call to fill the exposure';
  end if;

  select *
  into second_result
  from public.complete_exposure(test_exposure_id, canonical_path);

  if second_result.participant_finished is distinct from first_result.participant_finished then
    raise exception 'Expected repeated same-path completion to return stable participant_finished';
  end if;

  if second_result.roll_ready_to_reveal is distinct from first_result.roll_ready_to_reveal then
    raise exception 'Expected repeated same-path completion to return stable roll_ready_to_reveal';
  end if;

  begin
    perform public.complete_exposure(
      test_exposure_id,
      'rolls/00000000-0000-0000-0000-000000001402/participants/00000000-0000-0000-0000-000000001403/999.jpg'
    );
  exception
    when others then
      different_path_failed := true;
  end;

  if not different_path_failed then
    raise exception 'Expected repeated completion with a different path to fail';
  end if;

  raise notice 'complete_exposure() idempotency assertions passed';

  delete from public.rolls where id = test_roll_id;
  delete from public.profiles where id = test_user_id;
  delete from auth.users where id = test_user_id;
end;
$$;
