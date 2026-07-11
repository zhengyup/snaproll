create or replace function public.remove_participant(p_participant_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_user_id uuid;
  v_roll public.rolls%rowtype;
  v_participant public.roll_participants%rowtype;
begin
  v_user_id := public.require_authenticated_profile_id();

  if p_participant_id is null then
    raise exception using
      errcode = '22023',
      message = 'participant_id is required.';
  end if;

  select *
  into v_participant
  from public.roll_participants
  where id = p_participant_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'Participant not found.';
  end if;

  select *
  into v_roll
  from public.rolls
  where id = v_participant.roll_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'Roll not found.';
  end if;

  if v_roll.creator_id <> v_user_id then
    raise exception using
      errcode = '42501',
      message = 'Only the roll creator can remove participants.';
  end if;

  if v_roll.status not in ('DRAFT', 'WAITING_FOR_PARTICIPANTS') then
    raise exception using
      errcode = '55000',
      message = 'Participants can only be removed before the roll starts.';
  end if;

  if v_participant.user_id = v_roll.creator_id then
    raise exception using
      errcode = '42501',
      message = 'The creator cannot remove themselves from the roll.';
  end if;

  delete from public.roll_participants
  where id = v_participant.id;
end;
$$;

revoke all on function public.remove_participant(uuid) from public;
grant execute on function public.remove_participant(uuid) to authenticated;
