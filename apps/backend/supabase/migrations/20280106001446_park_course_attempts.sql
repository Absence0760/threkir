-- Why a run that set out on a park course got no time on it (issue #1446).
--
-- The segment-match function times each run against the catalogue segments
-- near it (record_segment_match). For each park course the run left the start
-- box of and got no time on, the matcher now also says which rule it missed
-- and how far along the course it got (`diagnoseGlobalSegmentAttempts` in the
-- `segments` parity pair, docs/features/park_courses.md § Why no time), and
-- the function writes that here through record_park_course_attempts. Run
-- detail shows the owner one "no time" card per row.
--
-- Owner-only: a row says where someone ran and how it went, so only the run's
-- owner may read it, never followers and never the public. Writes come only
-- from the service-role processor. Re-scoring a run replaces its rows; a run
-- delete, a course delete and an account delete each cascade. In the Art 20
-- export beside global_segment_efforts.
--
-- Locks (docs/backend/migration_locks.md): a new table, its indexes and
-- policy, and two new functions. Nothing on a populated table.

create table public.park_course_attempts (
  id                uuid primary key default gen_random_uuid(),
  run_id            uuid not null references public.runs(id) on delete cascade,
  user_id           uuid not null references auth.users(id) on delete cascade,
  park_course_id    uuid not null references public.park_courses(id) on delete cascade,
  outcome           text not null
                      constraint park_course_attempts_outcome_check
                      check (outcome in ('stopped_short', 'skipped_checkpoint', 'off_course', 'gps_gap', 'wrong_direction')),
  progress_m        integer not null
                      constraint park_course_attempts_progress_check check (progress_m >= 0),
  course_m          integer not null
                      constraint park_course_attempts_course_check check (course_m > 0),
  missed_checkpoint smallint,
  checkpoint_count  smallint not null
                      constraint park_course_attempts_checkpoint_count_check check (checkpoint_count >= 0),
  matcher_version   smallint not null
                      constraint park_course_attempts_matcher_version_check check (matcher_version > 0),
  created_at        timestamptz not null default now(),
  constraint park_course_attempts_progress_within_course check (progress_m <= course_m),
  constraint park_course_attempts_missed_checkpoint_check check (
    (outcome = 'skipped_checkpoint') = (missed_checkpoint is not null)
    and (missed_checkpoint is null or missed_checkpoint between 1 and checkpoint_count)
  ),
  constraint park_course_attempts_run_course_key unique (run_id, park_course_id)
);

-- The unique key leads with run_id, so it serves the per-run read and the
-- per-run replace; these two serve the account and course cascades.
create index park_course_attempts_user_idx on public.park_course_attempts (user_id);
create index park_course_attempts_course_idx on public.park_course_attempts (park_course_id);

comment on table public.park_course_attempts is
  'Why a run that left a park course''s start box got no time on it: the first rule it missed and how far along '
  'the course it got (issue #1446). Written by record_park_course_attempts, read by get_run_park_course_attempts. '
  '20280106001446.';

alter table public.park_course_attempts enable row level security;

revoke all on table public.park_course_attempts from public, anon, authenticated;
grant select on table public.park_course_attempts to authenticated;
grant all on table public.park_course_attempts to service_role;

create policy "run owner reads their park course attempts" on public.park_course_attempts
  for select to authenticated
  using (user_id = (select auth.uid()));

-- ─── the write ─────────────────────────────────────────────────────────────

-- Replaces a run's attempts with the processor's. Refused as 'stale' when the
-- track bytes changed under the pass, exactly as record_segment_match is (the
-- rewrite queues a fresh pass), and 'missing' when the run is gone. The owner
-- is read off the run, never taken from the caller; an attempt naming a
-- course that no longer exists is dropped.
create or replace function public.record_park_course_attempts(
  p_run_id uuid,
  p_track_version text,
  p_matcher_version integer,
  p_attempts jsonb
)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid;
  v_track_url text;
begin
  if p_attempts is null or jsonb_typeof(p_attempts) <> 'array' then
    raise exception 'record_park_course_attempts: p_attempts must be an array' using errcode = '22023';
  end if;
  if p_matcher_version is null or p_matcher_version < 1 or p_matcher_version > 32767 then
    raise exception 'record_park_course_attempts: p_matcher_version must be 1..32767' using errcode = '22023';
  end if;

  select r.user_id, r.track_url into v_user_id, v_track_url
    from public.runs r
   where r.id = p_run_id
   for share;
  if not found then
    return 'missing';
  end if;

  if v_track_url is null
     or p_track_version is null
     or public.runs_track_object_version(v_track_url) is distinct from p_track_version then
    return 'stale';
  end if;

  delete from public.park_course_attempts a where a.run_id = p_run_id;

  insert into public.park_course_attempts
    (run_id, user_id, park_course_id, outcome, progress_m, course_m, missed_checkpoint, checkpoint_count, matcher_version)
  select p_run_id, v_user_id, pc.id, m ->> 'outcome', (m ->> 'progress_m')::integer, (m ->> 'course_m')::integer,
         (m ->> 'missed_checkpoint')::smallint, (m ->> 'checkpoint_count')::smallint, p_matcher_version::smallint
    from jsonb_array_elements(p_attempts) m
    join public.park_courses pc on pc.id = (m ->> 'park_course_id')::uuid
  on conflict (run_id, park_course_id) do nothing;

  return 'recorded';
end;
$$;

revoke execute on function public.record_park_course_attempts(uuid, text, integer, jsonb)
  from public, anon, authenticated;
grant execute on function public.record_park_course_attempts(uuid, text, integer, jsonb)
  to service_role;

-- ─── the read ──────────────────────────────────────────────────────────────

-- Run detail's "no time" cards: each attempt on one of the caller's own runs,
-- with the course and park it links to. SECURITY INVOKER: the table's owner
-- policy and the explicit owner predicate both hold, so another user's run
-- (or no session) reads nothing, and a course in a park park_courses' own
-- policy hides drops out with it.
create or replace function public.get_run_park_course_attempts(p_run_id uuid)
returns table (
  park_course_id uuid,
  course_name text,
  park_name text,
  region_code text,
  park_slug text,
  course_slug text,
  outcome text,
  progress_m integer,
  course_m integer,
  missed_checkpoint smallint,
  checkpoint_count smallint
)
language sql
stable
security invoker
set search_path = public
as $$
  select a.park_course_id, gs.name, pk.name, pk.region_code, pk.slug, pc.slug,
         a.outcome, a.progress_m, a.course_m, a.missed_checkpoint, a.checkpoint_count
    from public.park_course_attempts a
    join public.park_courses pc on pc.id = a.park_course_id
    join public.parks pk on pk.id = pc.park_id
    join public.global_segments gs on gs.id = pc.global_segment_id
   where a.run_id = p_run_id
     and a.user_id = (select auth.uid())
   order by gs.name, a.park_course_id;
$$;

revoke execute on function public.get_run_park_course_attempts(uuid) from public, anon;
grant execute on function public.get_run_park_course_attempts(uuid) to authenticated, service_role;
