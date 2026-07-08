-- Snaproll V2 Phase 7 follow-up
--
-- Grant read privileges required for authenticated client reads.
--
-- Root cause:
-- - read-side RLS policies were present
-- - but the authenticated role still lacked plain SELECT privileges on the
--   underlying V2 tables
-- - PostgreSQL therefore rejected reads before RLS policy evaluation with:
--   "permission denied for table rolls"
--
-- Fix:
-- - grant the minimum read privileges needed for the V2 authenticated client
-- - keep lifecycle mutations RPC-owned; no direct write grants are added

grant usage on schema public to authenticated;

grant select on table public.profiles to authenticated;
grant select on table public.rolls to authenticated;
grant select on table public.roll_participants to authenticated;
grant select on table public.exposures to authenticated;
grant select on table public.invites to authenticated;
