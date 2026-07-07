-- Snaproll V2 Phase 4 support
-- Minimal read-side RLS policies required for the iOS repository layer.
--
-- These policies intentionally add read access only.
-- Lifecycle and business-state mutations remain RPC-owned.

create policy "authenticated users can read basic profiles"
on public.profiles
for select
to authenticated
using (true);

create policy "participants can read accessible rolls"
on public.rolls
for select
to authenticated
using (
  creator_id = auth.uid()
  or exists (
    select 1
    from public.roll_participants rp
    where rp.roll_id = public.rolls.id
      and rp.user_id = auth.uid()
  )
);

create policy "participants can read participant lists for accessible rolls"
on public.roll_participants
for select
to authenticated
using (
  user_id = auth.uid()
  or exists (
    select 1
    from public.roll_participants self_rp
    where self_rp.roll_id = public.roll_participants.roll_id
      and self_rp.user_id = auth.uid()
  )
);

create policy "participants can read exposures for accessible rolls"
on public.exposures
for select
to authenticated
using (
  exists (
    select 1
    from public.roll_participants rp
    where rp.roll_id = public.exposures.roll_id
      and rp.user_id = auth.uid()
  )
);

create policy "creators can read active invites for their rolls"
on public.invites
for select
to authenticated
using (
  exists (
    select 1
    from public.rolls r
    where r.id = public.invites.roll_id
      and r.creator_id = auth.uid()
  )
);
