-- Snaproll V2 Phase 15A
-- Read-only invite preview RPC for link-based shared-roll invitations.
--
-- This intentionally does not replace join_roll(). The invite token remains the
-- backend invitation identifier, and join_roll() remains authoritative for
-- joining and lifecycle validation.

create or replace function public.get_roll_invite_preview(p_invite_token text)
returns table (
  roll_id uuid,
  title text,
  creator_display_name text,
  participant_count integer,
  participant_cap integer,
  exposures_per_participant integer,
  status text,
  is_active boolean,
  is_accepting_participants boolean
)
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_invite public.invites%rowtype;
  v_roll public.rolls%rowtype;
begin
  perform public.require_authenticated_profile_id();

  if p_invite_token is null or btrim(p_invite_token) = '' then
    raise exception using
      errcode = '22023',
      message = 'invite_token is required.';
  end if;

  select *
  into v_invite
  from public.invites
  where token = btrim(p_invite_token);

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'Invite not found.';
  end if;

  select *
  into v_roll
  from public.rolls
  where id = v_invite.roll_id;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'Roll not found.';
  end if;

  return query
  select
    v_roll.id,
    v_roll.title,
    p.display_name,
    (
      select count(*)::integer
      from public.roll_participants rp
      where rp.roll_id = v_roll.id
    ) as participant_count,
    v_roll.participant_cap,
    v_roll.exposures_per_participant,
    v_roll.status,
    (v_invite.is_active and v_invite.revoked_at is null) as is_active,
    (
      v_invite.is_active
      and v_invite.revoked_at is null
      and v_roll.type = 'SHARED'
      and v_roll.status = 'WAITING_FOR_PARTICIPANTS'
    ) as is_accepting_participants
  from public.profiles p
  where p.id = v_roll.creator_id;
end;
$$;

grant execute on function public.get_roll_invite_preview(text) to authenticated;
