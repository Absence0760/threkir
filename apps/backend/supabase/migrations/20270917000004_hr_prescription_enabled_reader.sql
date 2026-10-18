-- The clients read the heart-rate prescription gate from the server (issue
-- #1186 second review; decisions § 2108).
--
-- 20270915000004 made the gate a private.feature_flags row the database
-- enforces, but web and mobile still decided what to render from their own
-- build-time flags (PUBLIC_HR_PRESCRIPTION_ENABLED / HR_PRESCRIPTION_ENABLED).
-- Two switches for one decision can disagree, and with the client on and the
-- server shut the workout editor offered a bpm target that every save then
-- refused. public.hr_prescription_enabled() is the one reader clients get, the
-- shape audience_sharing_enabled() set (20270802000001), and the client flags
-- are retired in the same change. Catalogue-only.

create or replace function public.hr_prescription_enabled()
returns boolean
language sql
stable
security definer
set search_path = public, private
as $$
  select private.hr_prescription_enabled();
$$;

revoke execute on function public.hr_prescription_enabled() from public, anon;
grant execute on function public.hr_prescription_enabled() to authenticated, service_role;

comment on function public.hr_prescription_enabled() is
  'Whether the heart-rate prescription surfaces are live: bpm targets, the '
  'hr_medication_affected pref and the roster HR drift (decisions § 2108). '
  'Clients render none of them when false.';
