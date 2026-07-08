-- Snaproll V2 Phase 7 follow-up
--
-- Harden the read-side RLS helper path after replacing recursive policies.
--
-- Problem observed:
-- - after the recursion fix, authenticated reads could still fail with
--   "permission denied for table rows"
-- - that indicates the helper path is still being evaluated under row-level
--   restrictions instead of acting as a trusted membership/ownership check
--
-- Fix strategy:
-- - recreate the helper functions as explicit security-definer helpers with
--   row_security disabled in their execution context
-- - reapply the read policies against those hardened helpers

drop policy if exists "participants can read accessible rolls" on public.rolls;
drop policy if exists "participants can read participant lists for accessible rolls" on public.roll_participants;
drop policy if exists "participants can read exposures for accessible rolls" on public.exposures;
drop policy if exists "creators can read active invites for their rolls" on public.invites;

drop function if exists public.is_roll_participant(uuid, uuid);
drop function if exists public.is_roll_creator(uuid, uuid);

create function public.is_roll_participant(
  p_roll_id uuid,
  p_user_id uuid default auth.uid()
)
returns boolean
language sql
security definer
set search_path = public
set row_security = off
stable
as $$
  select exists (
    select 1
    from public.roll_participants rp
    where rp.roll_id = p_roll_id
      and rp.user_id = p_user_id
  );
$$;

create function public.is_roll_creator(
  p_roll_id uuid,
  p_user_id uuid default auth.uid()
)
returns boolean
language sql
security definer
set search_path = public
set row_security = off
stable
as $$
  select exists (
    select 1
    from public.rolls r
    where r.id = p_roll_id
      and r.creator_id = p_user_id
  );
$$;

alter function public.is_roll_participant(uuid, uuid) owner to postgres;
alter function public.is_roll_creator(uuid, uuid) owner to postgres;

revoke all on function public.is_roll_participant(uuid, uuid) from public;
revoke all on function public.is_roll_creator(uuid, uuid) from public;
grant execute on function public.is_roll_participant(uuid, uuid) to authenticated;
grant execute on function public.is_roll_creator(uuid, uuid) to authenticated;

create policy "participants can read accessible rolls"
on public.rolls
for select
to authenticated
using (
  creator_id = auth.uid()
  or public.is_roll_participant(public.rolls.id, auth.uid())
);

create policy "participants can read participant lists for accessible rolls"
on public.roll_participants
for select
to authenticated
using (
  user_id = auth.uid()
  or public.is_roll_participant(public.roll_participants.roll_id, auth.uid())
);

create policy "participants can read exposures for accessible rolls"
on public.exposures
for select
to authenticated
using (
  public.is_roll_participant(public.exposures.roll_id, auth.uid())
);

create policy "creators can read active invites for their rolls"
on public.invites
for select
to authenticated
using (
  public.is_roll_creator(public.invites.roll_id, auth.uid())
);
