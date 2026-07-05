-- Snaproll V2 Phase 2
-- RPC foundation for lifecycle-owned business operations.
--
-- This migration adds Postgres functions only.
-- It intentionally does NOT add:
-- - storage buckets or storage policies
-- - RLS policies
-- - Edge Functions
-- - SwiftData or iOS code

create or replace function public.require_authenticated_profile_id()
returns uuid
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_user_id uuid;
begin
  v_user_id := auth.uid();

  if v_user_id is null then
    raise exception using
      errcode = '28000',
      message = 'Authentication is required.';
  end if;

  if not exists (
    select 1
    from public.profiles
    where id = v_user_id
  ) then
    raise exception using
      errcode = 'P0001',
      message = 'A profile must exist before calling Snaproll RPC functions.';
  end if;

  return v_user_id;
end;
$$;

create or replace function public.is_valid_film_stock_id(p_film_stock_id text)
returns boolean
language sql
immutable
as $$
  select p_film_stock_id is not null and btrim(p_film_stock_id) <> '';
$$;

create or replace function public.generate_secure_token()
returns text
language sql
volatile
set search_path = public, auth, extensions
as $$
  select encode(gen_random_bytes(24), 'hex');
$$;

create or replace function public.generate_render_seed()
returns text
language sql
volatile
set search_path = public, auth, extensions
as $$
  select encode(gen_random_bytes(16), 'hex');
$$;

create or replace function public.create_roll(
  p_title text,
  p_type text,
  p_film_stock_id text,
  p_exposures_per_participant integer,
  p_participant_cap integer default 10
)
returns table (
  roll_id uuid,
  invite_token text
)
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_user_id uuid;
  v_roll_id uuid;
  v_status text;
  v_invite_token text;
  v_display_name text;
begin
  v_user_id := public.require_authenticated_profile_id();

  if p_title is null or btrim(p_title) = '' then
    raise exception using
      errcode = '22023',
      message = 'Roll title is required.';
  end if;

  if p_type not in ('PERSONAL', 'SHARED') then
    raise exception using
      errcode = '22023',
      message = 'Roll type must be PERSONAL or SHARED.';
  end if;

  if not public.is_valid_film_stock_id(p_film_stock_id) then
    raise exception using
      errcode = '22023',
      message = 'film_stock_id is invalid.';
  end if;

  if p_exposures_per_participant not in (12, 24, 36) then
    raise exception using
      errcode = '22023',
      message = 'exposures_per_participant must be 12, 24, or 36.';
  end if;

  if p_participant_cap is null or p_participant_cap < 1 or p_participant_cap > 10 then
    raise exception using
      errcode = '22023',
      message = 'participant_cap must be between 1 and 10.';
  end if;

  if p_type = 'SHARED' then
    select display_name
    into v_display_name
    from public.profiles
    where id = v_user_id;

    if v_display_name is null or btrim(v_display_name) = '' then
      raise exception using
        errcode = 'P0001',
        message = 'A display name must be configured before participating in shared rolls.';
    end if;
  end if;

  v_status := case
    when p_type = 'SHARED' then 'WAITING_FOR_PARTICIPANTS'
    else 'DRAFT'
  end;

  insert into public.rolls (
    creator_id,
    title,
    type,
    status,
    film_stock_id,
    exposures_per_participant,
    participant_cap
  )
  values (
    v_user_id,
    btrim(p_title),
    p_type,
    v_status,
    p_film_stock_id,
    p_exposures_per_participant,
    p_participant_cap
  )
  returning id into v_roll_id;

  insert into public.roll_participants (
    roll_id,
    user_id,
    status
  )
  values (
    v_roll_id,
    v_user_id,
    'JOINED'
  );

  if p_type = 'SHARED' then
    loop
      v_invite_token := public.generate_secure_token();

      begin
        insert into public.invites (
          roll_id,
          token,
          created_by,
          is_active
        )
        values (
          v_roll_id,
          v_invite_token,
          v_user_id,
          true
        );

        exit;
      exception
        when unique_violation then
          null;
      end;
    end loop;
  end if;

  return query
  select v_roll_id, v_invite_token;
end;
$$;

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
    where roll_id = v_roll.id
      and user_id = v_user_id
  ) then
    raise exception using
      errcode = '23505',
      message = 'You are already a participant in this roll.';
  end if;

  select count(*)
  into v_participant_count
  from public.roll_participants
  where roll_id = v_roll.id;

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

create or replace function public.leave_roll(p_roll_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_user_id uuid;
  v_roll public.rolls%rowtype;
  v_participant_id uuid;
begin
  v_user_id := public.require_authenticated_profile_id();

  if p_roll_id is null then
    raise exception using
      errcode = '22023',
      message = 'roll_id is required.';
  end if;

  select *
  into v_roll
  from public.rolls
  where id = p_roll_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'Roll not found.';
  end if;

  if v_roll.status not in ('DRAFT', 'WAITING_FOR_PARTICIPANTS') then
    raise exception using
      errcode = '55000',
      message = 'Participants can only leave before the roll starts.';
  end if;

  if v_roll.creator_id = v_user_id then
    raise exception using
      errcode = '42501',
      message = 'The creator cannot leave their own roll.';
  end if;

  delete from public.roll_participants
  where roll_id = p_roll_id
    and user_id = v_user_id
  returning id into v_participant_id;

  if v_participant_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'You are not a participant in this roll.';
  end if;

  return;
end;
$$;

create or replace function public.start_roll(p_roll_id uuid)
returns integer
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_user_id uuid;
  v_roll public.rolls%rowtype;
  v_participant_count integer;
  v_exposures_created integer;
begin
  v_user_id := public.require_authenticated_profile_id();

  if p_roll_id is null then
    raise exception using
      errcode = '22023',
      message = 'roll_id is required.';
  end if;

  select *
  into v_roll
  from public.rolls
  where id = p_roll_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'Roll not found.';
  end if;

  if v_roll.creator_id <> v_user_id then
    raise exception using
      errcode = '42501',
      message = 'Only the roll creator can start the roll.';
  end if;

  -- Shared rolls begin in WAITING_FOR_PARTICIPANTS.
  -- Personal rolls begin in DRAFT and still need a start operation to create exposures.
  if not (
    (v_roll.type = 'SHARED' and v_roll.status = 'WAITING_FOR_PARTICIPANTS')
    or (v_roll.type = 'PERSONAL' and v_roll.status = 'DRAFT')
  ) then
    raise exception using
      errcode = '55000',
      message = 'This roll is not in a startable state.';
  end if;

  if not public.is_valid_film_stock_id(v_roll.film_stock_id) then
    raise exception using
      errcode = '22023',
      message = 'The roll has an invalid film_stock_id.';
  end if;

  if v_roll.exposures_per_participant not in (12, 24, 36) then
    raise exception using
      errcode = '22023',
      message = 'The roll has an invalid exposures_per_participant value.';
  end if;

  if v_roll.participant_cap < 1 or v_roll.participant_cap > 10 then
    raise exception using
      errcode = '22023',
      message = 'The roll has an invalid participant_cap value.';
  end if;

  select count(*)
  into v_participant_count
  from public.roll_participants
  where roll_id = v_roll.id;

  if v_participant_count < 1 then
    raise exception using
      errcode = 'P0001',
      message = 'A roll must have at least one participant before it can start.';
  end if;

  if v_participant_count > v_roll.participant_cap then
    raise exception using
      errcode = 'P0001',
      message = 'The roll has more participants than its participant cap allows.';
  end if;

  if exists (
    select 1
    from public.exposures
    where roll_id = v_roll.id
  ) then
    raise exception using
      errcode = '55000',
      message = 'Exposure slots have already been created for this roll.';
  end if;

  update public.roll_participants
  set
    status = 'SHOOTING',
    finished_at = null
  where roll_id = v_roll.id;

  insert into public.exposures (
    roll_id,
    participant_id,
    exposure_number,
    render_seed
  )
  select
    v_roll.id,
    rp.id,
    gs.exposure_number,
    public.generate_render_seed()
  from public.roll_participants rp
  cross join generate_series(1, v_roll.exposures_per_participant) as gs(exposure_number)
  where rp.roll_id = v_roll.id;

  get diagnostics v_exposures_created = row_count;

  update public.rolls
  set
    status = 'SHOOTING',
    started_at = timezone('utc', now()),
    ready_to_reveal_at = null,
    revealed_at = null
  where id = v_roll.id;

  return v_exposures_created;
end;
$$;

create or replace function public.reveal_roll(p_roll_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_user_id uuid;
  v_roll public.rolls%rowtype;
begin
  v_user_id := public.require_authenticated_profile_id();

  if p_roll_id is null then
    raise exception using
      errcode = '22023',
      message = 'roll_id is required.';
  end if;

  select *
  into v_roll
  from public.rolls
  where id = p_roll_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'Roll not found.';
  end if;

  if v_roll.creator_id <> v_user_id then
    raise exception using
      errcode = '42501',
      message = 'Only the roll creator can reveal the roll.';
  end if;

  if v_roll.status <> 'READY_TO_REVEAL' then
    raise exception using
      errcode = '55000',
      message = 'The roll must be READY_TO_REVEAL before it can be revealed.';
  end if;

  update public.rolls
  set
    status = 'REVEALED',
    revealed_at = timezone('utc', now())
  where id = v_roll.id;

  return;
end;
$$;

create or replace function public.force_reveal_roll(p_roll_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_user_id uuid;
  v_roll public.rolls%rowtype;
begin
  v_user_id := public.require_authenticated_profile_id();

  if p_roll_id is null then
    raise exception using
      errcode = '22023',
      message = 'roll_id is required.';
  end if;

  select *
  into v_roll
  from public.rolls
  where id = p_roll_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'Roll not found.';
  end if;

  if v_roll.creator_id <> v_user_id then
    raise exception using
      errcode = '42501',
      message = 'Only the roll creator can force reveal the roll.';
  end if;

  if v_roll.status not in ('SHOOTING', 'READY_TO_REVEAL') then
    raise exception using
      errcode = '55000',
      message = 'Force reveal is only available after the roll has started and before it is revealed.';
  end if;

  update public.rolls
  set
    status = 'REVEALED',
    revealed_at = timezone('utc', now())
  where id = v_roll.id;

  return;
end;
$$;

create or replace function public.regenerate_invite(p_roll_id uuid)
returns text
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_user_id uuid;
  v_roll public.rolls%rowtype;
  v_new_token text;
begin
  v_user_id := public.require_authenticated_profile_id();

  if p_roll_id is null then
    raise exception using
      errcode = '22023',
      message = 'roll_id is required.';
  end if;

  select *
  into v_roll
  from public.rolls
  where id = p_roll_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'Roll not found.';
  end if;

  if v_roll.creator_id <> v_user_id then
    raise exception using
      errcode = '42501',
      message = 'Only the roll creator can regenerate the invite.';
  end if;

  if v_roll.type <> 'SHARED' then
    raise exception using
      errcode = 'P0001',
      message = 'Only shared rolls can regenerate invites.';
  end if;

  if v_roll.status <> 'WAITING_FOR_PARTICIPANTS' then
    raise exception using
      errcode = '55000',
      message = 'Invites can only be regenerated before the roll starts.';
  end if;

  update public.invites
  set
    is_active = false,
    revoked_at = timezone('utc', now())
  where roll_id = v_roll.id
    and is_active = true
    and revoked_at is null;

  loop
    v_new_token := public.generate_secure_token();

    begin
      insert into public.invites (
        roll_id,
        token,
        created_by,
        is_active
      )
      values (
        v_roll.id,
        v_new_token,
        v_user_id,
        true
      );

      exit;
    exception
      when unique_violation then
        null;
    end;
  end loop;

  return v_new_token;
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
    v_exposure.exposure_number
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
