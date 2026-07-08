-- Snaproll V2 Phase 7 support
--
-- Fix read-side RLS recursion introduced by Phase 4's minimal select policies.
--
-- Root cause:
-- - the select policy on public.roll_participants queried public.roll_participants
--   inside its own USING clause
-- - the roll/exposure read policies also queried public.roll_participants
-- - once the iOS V2 read path began fetching cloud-backed rolls, PostgreSQL
--   detected recursive policy evaluation and rejected the query
--
-- Fix strategy:
-- - replace self-referential policy subqueries with security-definer helper
--   functions that answer participation / creator checks directly
-- - preserve the same effective access rules without changing app code

create or replace function public.is_roll_participant(
  p_roll_id uuid,
  p_user_id uuid default auth.uid()
)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1
    from public.roll_participants rp
    where rp.roll_id = p_roll_id
      and rp.user_id = p_user_id
  );
$$;

create or replace function public.is_roll_creator(
  p_roll_id uuid,
  p_user_id uuid default auth.uid()
)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1
    from public.rolls r
    where r.id = p_roll_id
      and r.creator_id = p_user_id
  );
$$;

revoke all on function public.is_roll_participant(uuid, uuid) from public;
revoke all on function public.is_roll_creator(uuid, uuid) from public;
grant execute on function public.is_roll_participant(uuid, uuid) to authenticated;
grant execute on function public.is_roll_creator(uuid, uuid) to authenticated;

drop policy if exists "participants can read accessible rolls" on public.rolls;
drop policy if exists "participants can read participant lists for accessible rolls" on public.roll_participants;
drop policy if exists "participants can read exposures for accessible rolls" on public.exposures;
drop policy if exists "creators can read active invites for their rolls" on public.invites;

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
