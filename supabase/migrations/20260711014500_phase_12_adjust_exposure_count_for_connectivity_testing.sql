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
