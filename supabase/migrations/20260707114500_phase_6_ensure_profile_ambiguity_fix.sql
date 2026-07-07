-- Snaproll V2 Phase 6 follow-up fix
--
-- Root cause:
-- ensure_profile() returns TABLE(id, display_name), which creates PL/pgSQL
-- output variables named `id` and `display_name`. That shape is easy to break
-- if the function body also needs to reference columns with the same names.
--
-- Fix:
-- preserve the external RPC contract, but avoid SELECT/WHERE patterns that can
-- collide with output-variable names. Instead, capture the upserted row into a
-- local record and assign the output values explicitly.

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
  v_profile public.profiles%rowtype;
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
  on conflict on constraint profiles_pkey do update
  set display_name = coalesce(excluded.display_name, public.profiles.display_name)
  returning public.profiles.* into v_profile;

  id := v_profile.id;
  display_name := v_profile.display_name;
  return next;
end;
$$;

revoke all on function public.ensure_profile(text) from public;
grant execute on function public.ensure_profile(text) to authenticated;
