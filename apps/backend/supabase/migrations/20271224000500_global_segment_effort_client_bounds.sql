-- A client-written catalogue effort must fit inside its run (audit of PR
-- #1359, Medium).
--
-- "run owner inserts catalogue efforts on their runs" (20271219001313) admits
-- an effort on any active segment for any run the caller owns, with whatever
-- time_seconds the caller sends, so a signed-in runner could post a 1 s
-- effort on a park course and take its record, its season board and the park
-- achievement. The durable fix is to make segment-match the only writer and
-- drop the client INSERT (issue #1313); that waits on the server job running
-- in production (roadmap § Park courses), because the run-detail fallback
-- (computeGlobalSegmentEffortsForRun) is still the writer for runs it has not
-- scored. Until then the client path is bounded at the root, on the row:
--
--   global_segment_efforts_client_bounds, BEFORE INSERT OR UPDATE, refuses a
--   write by a client role (anon, authenticated) to a run it can see with
--   23514 `global_segment_effort_implausible: <rule>` when
--     * time_seconds is longer than the run's duration_s,
--     * started_at is more than a minute before the run started or after the
--       run's started_at + duration_s, or
--     * the segment's distance over time_seconds is faster than anyone covers
--       ground on foot (11 m/s, above the 100 m world record's average) or on
--       a bike (25 m/s) for the run's activity type.
--   The first two bind the effort to its run; the last is what refuses the
--   forged 1 s, which fits inside any run. The writers that are not a client
--   role -- record_segment_match (SECURITY DEFINER, called by the service
--   role from segment-match), the service role itself, operator SQL -- are
--   not checked, so the server matcher is unaffected.
--
-- duration_s is elapsed time for a recorded run but moving time for a Strava
-- import (_shared/strava.ts), so the end of the span is a lower bound on the
-- truth there: an effort that starts after a long stop late in such a run is
-- refused on the fallback path and recorded by segment-match instead. The
-- fallback writes nothing it is refused (it retries on the next view), so
-- nothing is lost.
--
-- Locks: CREATE TRIGGER takes SHARE ROW EXCLUSIVE on global_segment_efforts
-- until commit; nothing is scanned.

create or replace function private.global_segment_effort_client_bounds()
returns trigger
language plpgsql
security invoker
set search_path = public, pg_temp
as $$
declare
  c_start_slack constant interval := interval '60 seconds';
  c_foot_max_mps constant numeric := 11;
  c_cycle_max_mps constant numeric := 25;
  v_started_at timestamptz;
  v_duration_s integer;
  v_activity text;
  v_distance_m numeric;
begin
  if current_user not in ('anon', 'authenticated') then
    return new;
  end if;

  select r.started_at, r.duration_s, r.activity_type
    into v_started_at, v_duration_s, v_activity
    from runs r
   where r.id = new.run_id;
  -- A run the caller cannot see is not theirs, and the INSERT policy, which
  -- admits only the run's owner, refuses the write with 42501.
  if not found then
    return new;
  end if;

  if new.time_seconds > v_duration_s then
    raise exception 'global_segment_effort_implausible: longer than the run'
      using errcode = 'check_violation';
  end if;

  if new.started_at < v_started_at - c_start_slack
     or new.started_at > v_started_at + make_interval(secs => v_duration_s) then
    raise exception 'global_segment_effort_implausible: starts outside the run'
      using errcode = 'check_violation';
  end if;

  select gs.distance_m into v_distance_m from global_segments gs where gs.id = new.global_segment_id;
  if v_distance_m is not null and v_distance_m > 0
     and v_distance_m / new.time_seconds
         > (case when v_activity = 'cycle' then c_cycle_max_mps else c_foot_max_mps end) then
    raise exception 'global_segment_effort_implausible: faster than the activity allows'
      using errcode = 'check_violation';
  end if;

  return new;
end;
$$;

revoke execute on function private.global_segment_effort_client_bounds() from public, anon, authenticated;

create trigger global_segment_efforts_client_bounds
  before insert or update on global_segment_efforts
  for each row execute function private.global_segment_effort_client_bounds();
