-- Snaproll V2 Phase 9A follow-up
--
-- Provision the canonical Storage bucket and add path-aware policies for
-- Snaproll exposure originals.
--
-- Why this exists:
-- - Phase 9A introduced the client upload pipeline
-- - uploads currently fail with "Bucket not found" because Storage has not
--   been provisioned yet
-- - we also want to avoid repeating the earlier RLS recursion mistake, so the
--   policy checks are implemented through security-definer helpers instead of
--   direct self-referential policy subqueries
--
-- Scope of this migration:
-- - create the private bucket `snaproll-originals`
-- - allow authenticated users to upload only to their own canonical exposure
--   path while the roll is actively shooting
-- - allow authenticated participants to read originals only after the roll has
--   been revealed
-- - do not allow object replacement, updates, or deletes in this phase

insert into storage.buckets (
  id,
  name,
  public
)
values (
  'snaproll-originals',
  'snaproll-originals',
  false
)
on conflict (id) do update
set
  name = excluded.name,
  public = excluded.public;

drop policy if exists "authenticated users can read snaproll originals bucket" on storage.buckets;
drop policy if exists "authenticated users can upload pending snaproll originals" on storage.objects;
drop policy if exists "participants can read revealed snaproll originals" on storage.objects;

drop function if exists public.can_upload_snaproll_original(text, text, uuid);
drop function if exists public.can_read_snaproll_original(text, text, uuid);

create function public.can_upload_snaproll_original(
  p_bucket_id text,
  p_object_name text,
  p_user_id uuid default auth.uid()
)
returns boolean
language plpgsql
security definer
set search_path = public
set row_security = off
stable
as $$
declare
  v_match text[];
  v_roll_id uuid;
  v_participant_id uuid;
  v_exposure_number integer;
begin
  if p_user_id is null or p_bucket_id <> 'snaproll-originals' then
    return false;
  end if;

  v_match := regexp_match(
    p_object_name,
    '^rolls/([0-9a-fA-F-]{8}-[0-9a-fA-F-]{4}-[0-9a-fA-F-]{4}-[0-9a-fA-F-]{4}-[0-9a-fA-F-]{12})/participants/([0-9a-fA-F-]{8}-[0-9a-fA-F-]{4}-[0-9a-fA-F-]{4}-[0-9a-fA-F-]{4}-[0-9a-fA-F-]{12})/([0-9]{3})\.jpg$'
  );

  if v_match is null then
    return false;
  end if;

  v_roll_id := v_match[1]::uuid;
  v_participant_id := v_match[2]::uuid;
  v_exposure_number := v_match[3]::integer;

  return exists (
    select 1
    from public.exposures e
    join public.roll_participants rp
      on rp.id = e.participant_id
     and rp.roll_id = e.roll_id
    join public.rolls r
      on r.id = e.roll_id
    where e.roll_id = v_roll_id
      and e.participant_id = v_participant_id
      and e.exposure_number = v_exposure_number
      and e.storage_path is null
      and rp.user_id = p_user_id
      and r.status = 'SHOOTING'
  );
end;
$$;

create function public.can_read_snaproll_original(
  p_bucket_id text,
  p_object_name text,
  p_user_id uuid default auth.uid()
)
returns boolean
language plpgsql
security definer
set search_path = public
set row_security = off
stable
as $$
declare
  v_match text[];
  v_roll_id uuid;
  v_participant_id uuid;
  v_exposure_number integer;
begin
  if p_user_id is null or p_bucket_id <> 'snaproll-originals' then
    return false;
  end if;

  v_match := regexp_match(
    p_object_name,
    '^rolls/([0-9a-fA-F-]{8}-[0-9a-fA-F-]{4}-[0-9a-fA-F-]{4}-[0-9a-fA-F-]{4}-[0-9a-fA-F-]{12})/participants/([0-9a-fA-F-]{8}-[0-9a-fA-F-]{4}-[0-9a-fA-F-]{4}-[0-9a-fA-F-]{4}-[0-9a-fA-F-]{12})/([0-9]{3})\.jpg$'
  );

  if v_match is null then
    return false;
  end if;

  v_roll_id := v_match[1]::uuid;
  v_participant_id := v_match[2]::uuid;
  v_exposure_number := v_match[3]::integer;

  return exists (
    select 1
    from public.exposures e
    join public.rolls r
      on r.id = e.roll_id
    where e.roll_id = v_roll_id
      and e.participant_id = v_participant_id
      and e.exposure_number = v_exposure_number
      and e.storage_path = p_object_name
      and r.status = 'REVEALED'
      and public.is_roll_participant(v_roll_id, p_user_id)
  );
end;
$$;

alter function public.can_upload_snaproll_original(text, text, uuid) owner to postgres;
alter function public.can_read_snaproll_original(text, text, uuid) owner to postgres;

revoke all on function public.can_upload_snaproll_original(text, text, uuid) from public;
revoke all on function public.can_read_snaproll_original(text, text, uuid) from public;
grant execute on function public.can_upload_snaproll_original(text, text, uuid) to authenticated;
grant execute on function public.can_read_snaproll_original(text, text, uuid) to authenticated;

grant usage on schema storage to authenticated;
grant select on table storage.buckets to authenticated;
grant select, insert on table storage.objects to authenticated;

create policy "authenticated users can read snaproll originals bucket"
on storage.buckets
for select
to authenticated
using (
  id = 'snaproll-originals'
);

create policy "authenticated users can upload pending snaproll originals"
on storage.objects
for insert
to authenticated
with check (
  public.can_upload_snaproll_original(storage.objects.bucket_id, storage.objects.name, auth.uid())
);

create policy "participants can read revealed snaproll originals"
on storage.objects
for select
to authenticated
using (
  public.can_read_snaproll_original(storage.objects.bucket_id, storage.objects.name, auth.uid())
);
