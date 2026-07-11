alter table public.rolls
drop constraint if exists rolls_exposures_per_participant_check;

alter table public.rolls
add constraint rolls_exposures_per_participant_check
check (exposures_per_participant >= 1 and exposures_per_participant <= 36);

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
  v_roll_status text;
  v_roll_type text;
  v_invite_token text;
begin
  v_user_id := public.require_authenticated_profile_id();

  if p_title is null or btrim(p_title) = '' then
    raise exception using
      errcode = '22023',
      message = 'title is required.';
  end if;

  if p_type is null or btrim(p_type) = '' then
    raise exception using
      errcode = '22023',
      message = 'type is required.';
  end if;

  if p_film_stock_id is null or btrim(p_film_stock_id) = '' then
    raise exception using
      errcode = '22023',
      message = 'film_stock_id is required.';
  end if;

  v_roll_type := upper(btrim(p_type));

  if v_roll_type not in ('PERSONAL', 'SHARED') then
    raise exception using
      errcode = '22023',
      message = 'type must be PERSONAL or SHARED.';
  end if;

  if p_exposures_per_participant is null
     or p_exposures_per_participant < 1
     or p_exposures_per_participant > 36 then
    raise exception using
      errcode = '22023',
      message = 'exposures_per_participant must be between 1 and 36.';
  end if;

  if p_participant_cap is null or p_participant_cap < 1 or p_participant_cap > 10 then
    raise exception using
      errcode = '22023',
      message = 'participant_cap must be between 1 and 10.';
  end if;

  if v_roll_type = 'SHARED' then
    perform 1
    from public.profiles
    where id = v_user_id
      and display_name is not null;

    if not found then
      raise exception using
        errcode = 'P0001',
        message = 'Shared rolls require a display name. Configure your profile before participating in shared rolls.';
    end if;
  end if;

  if v_roll_type = 'PERSONAL' then
    v_roll_status := 'DRAFT';
  else
    v_roll_status := 'WAITING_FOR_PARTICIPANTS';
  end if;

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
    v_roll_type,
    v_roll_status,
    btrim(p_film_stock_id),
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

  if v_roll_type = 'SHARED' then
    v_invite_token := encode(gen_random_bytes(16), 'hex');

    insert into public.invites (
      roll_id,
      token,
      is_active
    )
    values (
      v_roll_id,
      v_invite_token,
      true
    );
  else
    v_invite_token := null;
  end if;

  roll_id := v_roll_id;
  invite_token := v_invite_token;
  return next;
end;
$$;

create or replace function public.start_roll(p_roll_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_user_id uuid;
  v_roll public.rolls%rowtype;
  v_participant_count integer;
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

  if v_roll.type = 'PERSONAL' then
    if v_roll.status <> 'DRAFT' then
      raise exception using
        errcode = '55000',
        message = 'Personal rolls can only be started from DRAFT.';
    end if;
  else
    if v_roll.status <> 'WAITING_FOR_PARTICIPANTS' then
      raise exception using
        errcode = '55000',
        message = 'Shared rolls can only be started from WAITING_FOR_PARTICIPANTS.';
    end if;
  end if;

  if v_roll.exposures_per_participant < 1 or v_roll.exposures_per_participant > 36 then
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

  if v_participant_count = 0 then
    raise exception using
      errcode = '55000',
      message = 'A roll must have at least one participant before it can start.';
  end if;

  if v_participant_count > v_roll.participant_cap then
    raise exception using
      errcode = '55000',
      message = 'The current participant count exceeds participant_cap.';
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
    gen_random_uuid()::text
  from public.roll_participants rp
  cross join generate_series(1, v_roll.exposures_per_participant) as gs(exposure_number)
  where rp.roll_id = v_roll.id;

  update public.roll_participants
  set
    status = 'SHOOTING',
    finished_at = null
  where roll_id = v_roll.id;

  update public.rolls
  set
    status = 'SHOOTING',
    started_at = now(),
    updated_at = now()
  where id = v_roll.id;
end;
$$;
