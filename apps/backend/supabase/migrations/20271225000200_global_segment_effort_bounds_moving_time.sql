-- The client bounds on a catalogue effort read runs.duration_s as the run's
-- wall-clock span, and it is not one (corrects 20271224000500).
--
-- duration_s is moving time: RunRecorder.pause() stops the stopwatch, and a
-- Strava import stores moving_time. A run started 08:00, paused 08:20-08:30
-- and stopped 09:00 has duration_s 3000, so an effort starting at 08:52 is
-- genuinely inside it but fell after started_at + duration_s and was
-- refused; so was a segment whose crossing spanned the pause, as "longer
-- than the run". runs carries no wall-clock end: concluded_at is stamped
-- only by a live broadcast, and the track's last timestamp is in Storage, out
-- of a trigger's reach. Neither rule has a sound bound to compare against, so
-- both are dropped.
--
-- What stays:
--   * started_at no more than 60 s before the run's started_at. A pause only
--     ever moves an effort later, the effort's timestamps and the run's start
--     come from the same device clock, and the slack covers the recorder
--     stamping the run a fix or two after the first track point.
--   * the speed cap, segment distance over time_seconds: 11 m/s on foot
--     (run, walk, hike, stroller -- the 100 m world record averages
--     10.44 m/s), 25 m/s on a ride. This is the rule that refuses a forged
--     1 s effort, which fits inside any run. 25 m/s (90 km/h) is not taken
--     from a published record: it is far above any ridden hour, but riders do
--     pass it on steep descents, so a genuine descent effort that fast is
--     refused here and left to segment-match, which is not held to it.
--
-- What the bound does not do: a plausible forged time (a fast but humanly
-- possible effort on a run the caller owns) still lands. That stays open
-- until segment-match is the only writer and the client INSERT is dropped
-- (issue #1313).
--
-- Locks: CREATE OR REPLACE FUNCTION only; the trigger is unchanged and no
-- table lock is taken.

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
  v_activity text;
  v_distance_m numeric;
begin
  if current_user not in ('anon', 'authenticated') then
    return new;
  end if;

  select r.started_at, r.activity_type
    into v_started_at, v_activity
    from runs r
   where r.id = new.run_id;
  -- A run the caller cannot see is not theirs, and the INSERT policy, which
  -- admits only the run's owner, refuses the write with 42501.
  if not found then
    return new;
  end if;

  if new.started_at < v_started_at - c_start_slack then
    raise exception 'global_segment_effort_implausible: starts before the run'
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
