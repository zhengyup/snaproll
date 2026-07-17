-- Phase 14 follow-up: allow idempotent Storage upload retries.
--
-- Context:
-- - The iOS upload client uses Supabase Storage upload with upsert enabled.
-- - The original Phase 9A Storage policy allowed INSERT only.
-- - If a previous upload created the object but local metadata completion did
--   not finish, retrying the upload may take the UPDATE/upsert path and fail
--   with:
--   "new row violates row-level security policy"
--
-- Safety:
-- - UPDATE is allowed only for the same canonical pending exposure path.
-- - Once complete_exposure() stores exposures.storage_path, the helper returns
--   false and the object can no longer be replaced through this policy.
-- - Deletes remain unsupported.

grant update on table storage.objects to authenticated;

drop policy if exists "authenticated users can retry pending snaproll original uploads" on storage.objects;

create policy "authenticated users can retry pending snaproll original uploads"
on storage.objects
for update
to authenticated
using (
  public.can_upload_snaproll_original(storage.objects.bucket_id, storage.objects.name, auth.uid())
)
with check (
  public.can_upload_snaproll_original(storage.objects.bucket_id, storage.objects.name, auth.uid())
);
