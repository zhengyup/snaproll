-- Snaproll V2 Phase 6 support
-- Development authentication needs a minimal way to ensure that the
-- authenticated user has a corresponding public.profiles row before
-- shared-roll RPCs execute.

create or replace function public.ensure_profile(p_display_name text default null)
returns table (
  id uuid,
  display_name text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
  v_display_name text;
begin
  v_user_id := auth.uid();

  if v_user_id is null then
    raise exception using
      errcode = '28000',
      message = 'Authentication is required to ensure a Snaproll profile.';
  end if;

  v_display_name := nullif(trim(p_display_name), '');

  insert into public.profiles (
    id,
    display_name,
    created_at
  )
  values (
    v_user_id,
    v_display_name,
    timezone('utc', now())
  )
  on conflict (id) do update
  set display_name = coalesce(excluded.display_name, public.profiles.display_name);

  return query
  select
    p.id,
    p.display_name
  from public.profiles p
  where p.id = v_user_id;
end;
$$;

revoke all on function public.ensure_profile(text) from public;
grant execute on function public.ensure_profile(text) to authenticated;
