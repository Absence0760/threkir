-- Run-to-workout matching moves into the database (issue #1186, decisions
-- § 2079).
--
-- Until now each client linked a freshly saved run to a planned workout
-- itself (`autoMatchRunToPlanWorkout` in web data.ts and api_client.dart).
-- Wear OS saves directly and server-side imports never matched at all, and
-- the two client matchers shared six bugs: they used the UTC day, ignored
-- `metadata.plan_workout_id`, capped the distance at +25%, searched every
-- plan the user owned (abandoned, paused, template copies), left
-- `skipped_at` set on mobile, and let the first run saved on a day keep the
-- workout over a closer one saved later.
--
-- One statement-level AFTER trigger pair on `runs` now does it for every
-- writer:
--
-- 1. An explicit link first. A run carrying `metadata.plan_workout_id`
--    (started from that workout) is linked to it at any distance when the
--    workout belongs to the run's owner, is not a template row, and is not
--    already linked to another run by hand or by an earlier explicit link.
--    It takes the workout from an auto-matched run, and clears a skip: the
--    runner ran the very session they had skipped.
-- 2. Then each affected (user, local day) is re-matched as a whole:
--    - the day is the runner's LOCAL calendar day, through the `time_zone`
--      universal pref and private.athlete_local_date (20270830000011),
--      falling back to the server date when unset;
--    - only the user's `active`, non-template plans count;
--    - rest, skipped, manually ticked and hand/explicitly linked workouts
--      are never touched;
--    - a run qualifies at 75% or more of the target distance (or of the
--      target duration for a duration-only walk-run session), with no upper
--      bound;
--    - cycling is excluded: without an upper bound a ride would claim any
--      run workout;
--    - the closest run (smallest relative difference to the target) wins
--      each workout, so a later, closer run re-links it;
--    Only links the matcher made itself are ever moved or cleared, so a run
--    the runner linked by hand is never stolen, and a run the runner took
--    off a workout is never put back on it.
--
-- Two private tables hold the matcher's memory, written by an AFTER UPDATE
-- trigger on plan_workouts for every link, tick or skip change that is not
-- the matcher's own (the matcher sets a transaction-local GUC around its
-- writes), so no client needs to know they exist:
--   - `private.plan_workout_auto_links` marks the links the matcher made; any
--     other change drops the mark, so a hand relink or tick is sticky.
--     Existing links get no mark: the old client matcher and a hand relink
--     cannot be told apart, so both stay sticky.
--   - `private.plan_workout_link_refusals` remembers a run the runner took
--     off a workout (Unlink, relink to another run, skip), so the matcher
--     never puts that run back on that workout. Without it, Unlink would
--     last only until the next run write that day.
-- Both live in `private` because no client reads them, and both cascade
-- away with the workout or the run.
--
-- Matching is an auxiliary effect of the run write (layered resilience,
-- L4): each step runs in its own exception block and a failure raises a
-- WARNING, never the insert. A per-user transaction advisory lock
-- serialises two concurrent saves for one runner so both see each other's
-- run.
--
-- `runs` is a guarded table: CREATE TRIGGER takes a brief SHARE ROW
-- EXCLUSIVE lock and rewrites nothing.

create table private.plan_workout_auto_links (
  workout_id uuid primary key references public.plan_workouts (id) on delete cascade
);

revoke all on private.plan_workout_auto_links from public, anon, authenticated;

comment on table private.plan_workout_auto_links is
  'Plan workouts whose completed_run_id the run-to-workout matcher set '
  '(private.rematch_plan_day), so it may move or clear it again. Any other '
  'write to the link drops the row, making the link sticky.';

create table private.plan_workout_link_refusals (
  workout_id uuid not null references public.plan_workouts (id) on delete cascade,
  run_id     uuid not null references public.runs (id) on delete cascade,
  primary key (workout_id, run_id)
);

create index plan_workout_link_refusals_run on private.plan_workout_link_refusals (run_id);

revoke all on private.plan_workout_link_refusals from public, anon, authenticated;

comment on table private.plan_workout_link_refusals is
  'A run the runner took off a planned workout (unlink, relink, skip). The '
  'run-to-workout matcher never links that run to that workout again.';

create or replace function private.plan_workout_auto_link_guard()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
begin
  if coalesce(current_setting('threkir.plan_matcher', true), '') = 'on' then
    return null;
  end if;
  delete from private.plan_workout_auto_links where workout_id = new.id;
  -- A run deleted out from under its workout (on delete set null) is gone
  -- already by the time this runs, and is no refusal.
  if old.completed_run_id is not null
     and old.completed_run_id is distinct from new.completed_run_id
     and exists (select 1 from runs where id = old.completed_run_id) then
    insert into private.plan_workout_link_refusals (workout_id, run_id)
    values (new.id, old.completed_run_id)
    on conflict do nothing;
  end if;
  return null;
end;
$$;

revoke execute on function private.plan_workout_auto_link_guard() from public, anon, authenticated;

drop trigger if exists plan_workout_auto_link_guard on plan_workouts;
create trigger plan_workout_auto_link_guard
  after update on plan_workouts
  for each row
  when ((old.completed_run_id, old.manually_completed, old.skipped_at)
        is distinct from (new.completed_run_id, new.manually_completed, new.skipped_at))
  execute function private.plan_workout_auto_link_guard();

-- Whether a run of this size qualifies for a workout, and how far off it is.
-- Distance targets win; a duration-only target (walk-run) falls back to time.
-- Null score = does not qualify.
create or replace function private.plan_match_score(
  p_target_distance_m numeric,
  p_target_duration_s integer,
  p_distance_m double precision,
  p_duration_s integer
)
returns numeric
language sql
immutable
set search_path = public, pg_catalog
as $$
  select case
    when p_target_distance_m > 0 then
      case when p_distance_m >= 0.75 * p_target_distance_m
        then abs(p_distance_m::numeric - p_target_distance_m) / p_target_distance_m end
    when p_target_duration_s > 0 then
      case when p_duration_s >= 0.75 * p_target_duration_s
        then abs(p_duration_s - p_target_duration_s)::numeric / p_target_duration_s end
  end;
$$;

revoke execute on function private.plan_match_score(numeric, integer, double precision, integer) from public, anon, authenticated;

-- The workouts the matcher may set or move on one local day: in an active,
-- non-template plan of the user, not rest, not skipped, not ticked by hand,
-- and either open or linked by the matcher itself.
create or replace function private.plan_match_workouts(p_user uuid, p_day date)
returns table (
  id uuid,
  target_distance_m numeric,
  target_duration_seconds integer,
  completed_run_id uuid
)
language sql
stable
set search_path = public, pg_catalog
as $$
  select pw.id, pw.target_distance_m, pw.target_duration_seconds, pw.completed_run_id
  from plan_workouts pw
  join plan_weeks wk on wk.id = pw.week_id
  join training_plans tp on tp.id = wk.plan_id
  where tp.user_id = p_user
    and tp.status = 'active'
    and not tp.is_template
    and pw.scheduled_date = p_day
    and pw.kind <> 'rest'
    and pw.skipped_at is null
    and not pw.manually_completed
    and (pw.completed_run_id is null
         or exists (select 1 from private.plan_workout_auto_links a where a.workout_id = pw.id))
    and (pw.target_distance_m > 0 or pw.target_duration_seconds > 0);
$$;

revoke execute on function private.plan_match_workouts(uuid, date) from public, anon, authenticated;

create or replace function private.rematch_plan_day(p_user uuid, p_day date)
returns void
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_tz text;
  v_pair record;
  v_w record;
  v_ws uuid[] := '{}';
  v_rs uuid[] := '{}';
  v_pos int;
  v_new uuid;
begin
  if not exists (select 1 from private.plan_match_workouts(p_user, p_day)) then
    return;
  end if;

  perform pg_advisory_xact_lock(hashtext('plan_match:' || p_user::text));

  select us.prefs ->> 'time_zone' into v_tz
  from user_settings us where us.user_id = p_user;

  for v_pair in
    with w as (
      select * from private.plan_match_workouts(p_user, p_day)
    ),
    r as (
      select r.id, r.distance_m, r.duration_s
      from runs r
      where r.user_id = p_user
        -- Every zone's local day sits inside this UTC window; the exact
        -- test follows it, so the (user_id, started_at) index does the work.
        and r.started_at >= (p_day - 2)::timestamp at time zone 'UTC'
        and r.started_at < (p_day + 3)::timestamp at time zone 'UTC'
        and private.athlete_local_date(v_tz, r.started_at) = p_day
        and r.activity_type <> 'cycle'
        and not exists (
          select 1 from plan_workouts o
          where o.completed_run_id = r.id
            and o.id not in (select w.id from w)
        )
    )
    select w.id as workout_id,
           r.id as run_id,
           private.plan_match_score(w.target_distance_m, w.target_duration_seconds,
                                    r.distance_m, r.duration_s) as score,
           (w.completed_run_id is not distinct from r.id) as incumbent
    from w cross join r
    where private.plan_match_score(w.target_distance_m, w.target_duration_seconds,
                                   r.distance_m, r.duration_s) is not null
      and not exists (
        select 1 from private.plan_workout_link_refusals f
        where f.workout_id = w.id and f.run_id = r.id
      )
    order by score, incumbent desc, r.id, w.id
  loop
    if v_pair.workout_id = any(v_ws) or v_pair.run_id = any(v_rs) then
      continue;
    end if;
    v_ws := v_ws || v_pair.workout_id;
    v_rs := v_rs || v_pair.run_id;
  end loop;

  perform set_config('threkir.plan_matcher', 'on', true);
  for v_w in select * from private.plan_match_workouts(p_user, p_day) loop
    v_pos := array_position(v_ws, v_w.id);
    v_new := case when v_pos is null then null else v_rs[v_pos] end;
    if v_new is distinct from v_w.completed_run_id then
      update plan_workouts
      set completed_run_id = v_new,
          manually_completed = false,
          completed_at = case when v_new is null then null else now() end,
          skipped_at = null
      where id = v_w.id;
      if v_new is null then
        delete from private.plan_workout_auto_links where workout_id = v_w.id;
      else
        insert into private.plan_workout_auto_links (workout_id) values (v_w.id)
        on conflict (workout_id) do nothing;
      end if;
    end if;
  end loop;
  perform set_config('threkir.plan_matcher', 'off', true);
end;
$$;

revoke execute on function private.rematch_plan_day(uuid, date) from public, anon, authenticated;

-- Link a run to the workout it was started from. Returns the workout's date
-- when the link was made (so the caller re-matches that day for any run it
-- displaced), else null.
create or replace function private.link_explicit_plan_workout(p_run_id uuid, p_user uuid, p_workout_id uuid)
returns date
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_day date;
begin
  perform pg_advisory_xact_lock(hashtext('plan_match:' || p_user::text));

  select pw.scheduled_date into v_day
  from plan_workouts pw
  join plan_weeks wk on wk.id = pw.week_id
  join training_plans tp on tp.id = wk.plan_id
  where pw.id = p_workout_id
    and tp.user_id = p_user
    and not tp.is_template
    and (pw.completed_run_id is null
         or pw.completed_run_id = p_run_id
         or exists (select 1 from private.plan_workout_auto_links a where a.workout_id = pw.id))
    and not exists (
      select 1 from private.plan_workout_link_refusals f
      where f.workout_id = pw.id and f.run_id = p_run_id
    )
  for update of pw;

  if v_day is null then
    return null;
  end if;

  -- Neither change below is the runner taking a run off a workout, so the
  -- guard records no refusal for either.
  perform set_config('threkir.plan_matcher', 'on', true);

  -- The run may already hold another workout through the matcher; the
  -- explicit link replaces it, so the run is never linked twice.
  with released as (
    update plan_workouts pw
    set completed_run_id = null, completed_at = null
    where pw.completed_run_id = p_run_id
      and pw.id <> p_workout_id
      and exists (select 1 from private.plan_workout_auto_links a where a.workout_id = pw.id)
    returning pw.id
  )
  delete from private.plan_workout_auto_links a
  using released
  where a.workout_id = released.id;

  update plan_workouts
  set completed_run_id = p_run_id,
      manually_completed = false,
      completed_at = coalesce(case when completed_run_id = p_run_id then completed_at end, now()),
      skipped_at = null
  where id = p_workout_id;
  -- The link is explicit now, even when the matcher had made the same one.
  delete from private.plan_workout_auto_links where workout_id = p_workout_id;
  perform set_config('threkir.plan_matcher', 'off', true);

  return v_day;
end;
$$;

revoke execute on function private.link_explicit_plan_workout(uuid, uuid, uuid) from public, anon, authenticated;

create or replace function private.match_runs_to_plan_workouts()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_rec record;
  v_day date;
  -- Explicit links to make: run, owner, workout.
  v_link_runs uuid[] := '{}';
  v_link_users uuid[] := '{}';
  v_link_workouts uuid[] := '{}';
  -- Days to re-match: owner, local day, phase (0 = a run's old day).
  v_users uuid[] := '{}';
  v_days date[] := '{}';
  v_phases int[] := '{}';
  i int;
begin
  -- The transition tables differ per operation, and plpgsql plans a query
  -- whole, so each operation reads only the tables it has.
  if tg_op = 'INSERT' then
    select coalesce(array_agg(n.id), '{}'),
           coalesce(array_agg(n.user_id), '{}'),
           coalesce(array_agg((n.metadata ->> 'plan_workout_id')::uuid), '{}')
      into v_link_runs, v_link_users, v_link_workouts
    from new_runs n
    where n.metadata ->> 'plan_workout_id'
            ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';

    select coalesce(array_agg(n.user_id), '{}'),
           coalesce(array_agg(private.athlete_local_date(us.prefs ->> 'time_zone', n.started_at)), '{}'),
           coalesce(array_agg(1), '{}')
      into v_users, v_days, v_phases
    from new_runs n
    left join user_settings us on us.user_id = n.user_id;
  else
    select coalesce(array_agg(n.id), '{}'),
           coalesce(array_agg(n.user_id), '{}'),
           coalesce(array_agg((n.metadata ->> 'plan_workout_id')::uuid), '{}')
      into v_link_runs, v_link_users, v_link_workouts
    from new_runs n
    join old_runs o on o.id = n.id
    where n.metadata ->> 'plan_workout_id'
            ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      and (o.metadata -> 'plan_workout_id', o.user_id)
          is distinct from (n.metadata -> 'plan_workout_id', n.user_id);

    with changed as (
      select o.user_id as old_user, o.started_at as old_started,
             n.user_id as new_user, n.started_at as new_started
      from new_runs n
      join old_runs o on o.id = n.id
      where (o.started_at, o.distance_m, o.duration_s, o.activity_type, o.user_id,
             o.metadata -> 'plan_workout_id')
            is distinct from
            (n.started_at, n.distance_m, n.duration_s, n.activity_type, n.user_id,
             n.metadata -> 'plan_workout_id')
    ),
    days as (
      select c.old_user as user_id,
             private.athlete_local_date(us.prefs ->> 'time_zone', c.old_started) as day,
             0 as phase
      from changed c
      left join user_settings us on us.user_id = c.old_user
      union all
      select c.new_user,
             private.athlete_local_date(us.prefs ->> 'time_zone', c.new_started),
             1
      from changed c
      left join user_settings us on us.user_id = c.new_user
    )
    select coalesce(array_agg(user_id), '{}'),
           coalesce(array_agg(day), '{}'),
           coalesce(array_agg(phase), '{}')
      into v_users, v_days, v_phases
    from days;
  end if;

  -- Pass 1: explicit links, before any day is re-matched. The workout's own
  -- day joins the re-match so a run it displaced can take another workout.
  for i in 1 .. coalesce(array_length(v_link_runs, 1), 0) loop
    begin
      v_day := private.link_explicit_plan_workout(v_link_runs[i], v_link_users[i], v_link_workouts[i]);
      if v_day is not null then
        v_users := v_users || v_link_users[i];
        v_days := v_days || v_day;
        v_phases := v_phases || 1;
      end if;
    exception when others then
      raise warning 'plan workout explicit link failed (%): %', sqlstate, sqlerrm;
    end;
  end loop;

  -- Pass 2: re-match every affected (user, local day). A run's old day goes
  -- first, so a run that moved days is free to match on its new one.
  for v_rec in
    select u as user_id, d as day
    from unnest(v_users, v_days, v_phases) as x(u, d, p)
    group by u, d
    order by min(p), u, d
  loop
    begin
      perform private.rematch_plan_day(v_rec.user_id, v_rec.day);
    exception when others then
      raise warning 'plan workout re-match failed (%): %', sqlstate, sqlerrm;
    end;
  end loop;

  return null;
end;
$$;

revoke execute on function private.match_runs_to_plan_workouts() from public, anon, authenticated;

drop trigger if exists runs_match_plan_workouts_insert on runs;
create trigger runs_match_plan_workouts_insert
  after insert on runs
  referencing new table as new_runs
  for each statement
  execute function private.match_runs_to_plan_workouts();

drop trigger if exists runs_match_plan_workouts_update on runs;
create trigger runs_match_plan_workouts_update
  after update on runs
  referencing old table as old_runs new table as new_runs
  for each statement
  execute function private.match_runs_to_plan_workouts();
