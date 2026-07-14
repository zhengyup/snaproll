-- Phase 14B: make complete_exposure() idempotent for safe sync retries.
--
-- Repeated calls with the same canonical storage path now resolve as success.
-- Repeated calls with a different path are still rejected.

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

  if v_exposure.storage_path is not null then
    if v_exposure.storage_path <> v_expected_storage_path then
      raise exception using
        errcode = '55000',
        message = 'This exposure has already been completed with a different storage path.';
    end if;

    select not exists (
      select 1
      from public.exposures e
      where e.participant_id = v_exposure.participant_id
        and e.storage_path is null
    )
    into v_participant_finished;

    select not exists (
      select 1
      from public.exposures e
      where e.roll_id = v_exposure.roll_id
        and e.storage_path is null
    )
    into v_roll_ready;

    return query
    select v_participant_finished, v_roll_ready;
    return;
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

  update public.exposures
  set
    storage_path = v_expected_storage_path,
    uploaded_at = timezone('utc', now())
  where id = p_exposure_id;

  select not exists (
    select 1
    from public.exposures e
    where e.participant_id = v_exposure.participant_id
      and e.storage_path is null
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
    from public.exposures e
    where e.roll_id = v_exposure.roll_id
      and e.storage_path is null
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
