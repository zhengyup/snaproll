-- Phase 14 follow-up: allow Storage upsert to inspect pending own objects.
--
-- Context:
-- - The iOS upload pipeline intentionally uses Supabase Storage upload with
--   upsert enabled so retries are idempotent.
-- - Supabase Storage's upsert path can require SELECT visibility in addition
--   to INSERT/UPDATE privileges.
-- - The previous Storage policies allowed pending INSERT/UPDATE, but SELECT
--   was restricted to revealed rolls only. That caused pending uploads to fail
--   with:
--   "new row violates row-level security policy"
--
-- Safety:
-- - This does not make the bucket public.
-- - SELECT is allowed only for the authenticated participant's own canonical
--   pending exposure object path.
-- - Other participants' pending originals remain unreadable.
-- - Revealed-roll reads continue to use the existing revealed-read policy.

drop policy if exists "participants can inspect own pending snaproll originals" on storage.objects;

create policy "participants can inspect own pending snaproll originals"
on storage.objects
for select
to authenticated
using (
  public.can_upload_snaproll_original(storage.objects.bucket_id, storage.objects.name, auth.uid())
);
