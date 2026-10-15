-- A linked coach sees an athlete's run map, clipped (decisions § 1968,
-- reversing § 98 in part).
--
-- § 98 gave an active coach the athlete's run rows and stats but kept the GPS
-- track owner-only, because handing a coach the raw track would bypass the
-- privacy-zone clip — the athlete's home on every map. The clip answers that:
-- a coach is served exactly what a stranger reading a public run is served,
-- the track with the athlete's zones trimmed out (§ 33), and never the raw
-- bytes. The Storage policy stays owner-only.
--
-- 1. private.coach_run_map_enabled() / public.coach_run_map_enabled(): a row
--    in private.feature_flags that NO MIGRATION WRITES. Who can read an
--    athlete's location changes, so the widening waits on a CISO / Security
--    Analyst review before it reaches real users (§ 150); seed.sql opens it
--    for local + CI. Enforced in SQL so a client cannot read past it; the
--    public reader is how both clients decide whether to draw the map.
--
-- 2. coached_runs: the runs of athletes whose coaching link with the caller is
--    `active` — the same consent § 98 reads (redeeming the invite is the
--    athlete's consent; ending the link revokes it on the next read). Only the
--    columns clip-public-track reads. Never the caller's own runs. Empty while
--    the gate is closed.
--
-- clip-public-track asks it third, after public_runs and shared_runs, for a
-- signed-in caller, and clips the result against the athlete's zones like
-- every other non-owner read. Photos stay out (§ 98 amendment, § 1877).
--
-- Locks: function and view creation are catalogue-only.

create or replace function private.coach_run_map_enabled()
returns boolean
language sql
stable
security definer
set search_path = public, private
as $$
  select coalesce(
    (select f.enabled from private.feature_flags f where f.name = 'coach_run_map'),
    false
  );
$$;

revoke execute on function private.coach_run_map_enabled() from public, anon;
grant execute on function private.coach_run_map_enabled() to authenticated, service_role;

create or replace function public.coach_run_map_enabled()
returns boolean
language sql
stable
security definer
set search_path = public, private
as $$
  select private.coach_run_map_enabled();
$$;

revoke execute on function public.coach_run_map_enabled() from public, anon;
grant execute on function public.coach_run_map_enabled() to authenticated, service_role;

comment on function public.coach_run_map_enabled() is
  'Whether a linked coach is served the athlete''s clipped run map (decisions '
  '§ 1968). Clients hide the map when false.';

create or replace view coached_runs as
select
  r.id,
  r.user_id,
  r.is_public,
  coalesce(r.metadata, '{}'::jsonb) as metadata
from runs r
where r.user_id <> (select auth.uid())
  and private.coach_run_map_enabled()
  and private.is_active_coach_of((select auth.uid()), r.user_id);

revoke all on public.coached_runs from public, anon, authenticated;
grant select on public.coached_runs to authenticated;

comment on view public.coached_runs is
  'Runs of the caller''s actively-linked athletes, for clip-public-track only: '
  'the id, owner, visibility and metadata it reads. Empty while the '
  'coach_run_map gate is closed. decisions § 1968.';
