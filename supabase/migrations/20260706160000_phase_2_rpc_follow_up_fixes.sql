-- Snaproll V2 Phase 2 follow-up fixes
--
-- This migration preserves append-only migration history by moving post-apply
-- RPC fixes out of the original Phase 2 migration and into a new deployment.
--
-- Fixes included:
-- 1. Resolve PL/pgSQL ambiguity in join_roll() caused by RETURNS TABLE output
--    names colliding with unqualified column references.
-- 2. Align complete_exposure() with the approved padded storage path contract:
--    rolls/{roll_id}/participants/{participant_id}/001.jpg

create or replace function public.join_roll(p_invite_token text)
returns table (
  roll_id uuid,
  participant_id uuid
)
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_user_id uuid;
  v_roll public.rolls%rowtype;
  v_participant_id uuid;
  v_participant_count integer;
  v_display_name text;
begin
  v_user_id := public.require_authenticated_profile_id();

  if p_invite_token is null or btrim(p_invite_token) = '' then
    raise exception using
      errcode = '22023',
      message = 'invite_token is required.';
  end if;

  select r.*
  into v_roll
  from public.invites i
  join public.rolls r on r.id = i.roll_id
  where i.token = btrim(p_invite_token)
    and i.is_active = true
    and i.revoked_at is null
  for update of i, r;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'Invite is invalid or inactive.';
  end if;

  if v_roll.type <> 'SHARED' then
    raise exception using
      errcode = 'P0001',
      message = 'Only shared rolls can be joined by invite.';
  end if;

  select display_name
  into v_display_name
  from public.profiles
  where id = v_user_id;

  if v_display_name is null or btrim(v_display_name) = '' then
    raise exception using
      errcode = 'P0001',
      message = 'A display name must be configured before participating in shared rolls.';
  end if;

  if v_roll.status <> 'WAITING_FOR_PARTICIPANTS' then
    raise exception using
      errcode = '55000',
      message = 'This roll has already started and cannot accept new participants.';
  end if;

  if exists (
    select 1
    from public.roll_participants
    where public.roll_participants.roll_id = v_roll.id
      and public.roll_participants.user_id = v_user_id
  ) then
    raise exception using
      errcode = '23505',
      message = 'You are already a participant in this roll.';
  end if;

  select count(*)
  into v_participant_count
  from public.roll_participants
  where public.roll_participants.roll_id = v_roll.id;

  if v_participant_count >= v_roll.participant_cap then
    raise exception using
      errcode = 'P0001',
      message = 'This roll has reached its participant cap.';
  end if;

  insert into public.roll_participants (
    roll_id,
    user_id,
    status
  )
  values (
    v_roll.id,
    v_user_id,
    'JOINED'
  )
  returning id into v_participant_id;

  return query
  select v_roll.id, v_participant_id;
end;
$$;

create or replace function public.complete_exposure(
  p_exposure_id uuid,
  p_storage_path text
)
returns table (
  participant_finished boolean,
  roll_ready_to_reveal boolean
)
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_user_id uuid;
  v_exposure record;
  v_participant_finished boolean;
  v_roll_ready boolean;
  v_expected_storage_path text;
begin
  v_user_id := public.require_authenticated_profile_id();

  if p_exposure_id is null then
    raise exception using
      errcode = '22023',
      message = 'exposure_id is required.';
  end if;

  if p_storage_path is null or btrim(p_storage_path) = '' then
    raise exception using
      errcode = '22023',
      message = 'storage_path is required.';
  end if;

  select
    e.id,
    e.roll_id,
    e.participant_id,
    e.exposure_number,
    e.storage_path,
    rp.user_id,
    rp.status as participant_status,
    r.status as roll_status
  into v_exposure
  from public.exposures e
  join public.roll_participants rp on rp.id = e.participant_id
  join public.rolls r on r.id = e.roll_id
  where e.id = p_exposure_id
  for update of e, rp, r;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'Exposure not found.';
  end if;

  if v_exposure.user_id <> v_user_id then
    raise exception using
      errcode = '42501',
      message = 'You do not own this exposure.';
  end if;

  if v_exposure.roll_status <> 'SHOOTING' then
    raise exception using
      errcode = '55000',
      message = 'Exposures can only be completed while the roll is SHOOTING.';
  end if;

  if v_exposure.participant_status <> 'SHOOTING' then
    raise exception using
      errcode = '55000',
      message = 'This participant is not currently in SHOOTING status.';
  end if;

  if v_exposure.storage_path is not null then
    raise exception using
      errcode = '55000',
      message = 'This exposure has already been completed.';
  end if;

  v_expected_storage_path := format(
    'rolls/%s/participants/%s/%s.jpg',
    v_exposure.roll_id,
    v_exposure.participant_id,
    lpad(v_exposure.exposure_number::text, 3, '0')
  );

  if btrim(p_storage_path) <> v_expected_storage_path then
    raise exception using
      errcode = '22023',
      message = format(
        'storage_path must match the canonical exposure path: %s',
        v_expected_storage_path
      );
  end if;

  update public.exposures
  set
    storage_path = btrim(p_storage_path),
    uploaded_at = timezone('utc', now())
  where id = p_exposure_id;

  select not exists (
    select 1
    from public.exposures
    where participant_id = v_exposure.participant_id
      and storage_path is null
  )
  into v_participant_finished;

  if v_participant_finished then
    update public.roll_participants
    set
      status = 'FINISHED',
      finished_at = coalesce(finished_at, timezone('utc', now()))
    where id = v_exposure.participant_id;
  end if;

  select not exists (
    select 1
    from public.exposures
    where roll_id = v_exposure.roll_id
      and storage_path is null
  )
  into v_roll_ready;

  if v_roll_ready then
    update public.rolls
    set
      status = 'READY_TO_REVEAL',
      ready_to_reveal_at = coalesce(ready_to_reveal_at, timezone('utc', now()))
    where id = v_exposure.roll_id;
  end if;

  return query
  select v_participant_finished, v_roll_ready;
end;
$$;
