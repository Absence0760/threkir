-- Pins migration 20270901000001 (issue #1186): every run write links to a
-- planned workout in the database, on the runner's local day, honouring
-- metadata.plan_workout_id, at 75% of the target or more with no upper bound,
-- only in active non-template plans, never on a skipped workout, with the
-- closest run winning, and never stealing a link the runner made by hand.
begin;
select plan(43);

set local timezone = 'UTC';

create function pg_temp.mk_user(p_id uuid, p_zone text) returns uuid
language plpgsql as $$
begin
  insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
  values (p_id, 'authenticated', 'authenticated', p_id::text || '@match.local', '', now(), now());
  insert into user_profiles (id, display_name) values (p_id, 'Matcher') on conflict (id) do nothing;
  if p_zone is not null then
    insert into user_settings (user_id, prefs) values (p_id, jsonb_build_object('time_zone', p_zone))
      on conflict (user_id) do update set prefs = excluded.prefs;
  end if;
  return p_id;
end;
$$;

-- One plan with a single week; returns the week id.
create function pg_temp.mk_plan(p_user uuid, p_status text, p_template boolean default false,
                                p_start date default '2031-01-05', p_end date default '2031-02-28')
returns uuid
language plpgsql as $$
declare
  v_plan uuid;
  v_week uuid;
begin
  insert into training_plans (user_id, name, goal_event, goal_distance_m, start_date, end_date,
                              days_per_week, status, is_template)
  values (p_user, 'Plan', 'distance_10k', 10000, p_start, p_end, 4, p_status, p_template)
  returning id into v_plan;
  insert into plan_weeks (plan_id, week_index) values (v_plan, 0) returning id into v_week;
  return v_week;
end;
$$;

create function pg_temp.mk_workout(p_week uuid, p_day date, p_kind workout_kind, p_target_m numeric,
                                   p_target_s int default null)
returns uuid
language sql as $$
  insert into plan_workouts (week_id, scheduled_date, kind, target_distance_m, target_duration_seconds)
  values (p_week, p_day, p_kind, p_target_m, p_target_s)
  returning id;
$$;

create function pg_temp.mk_run(p_user uuid, p_at timestamptz, p_distance_m double precision,
                               p_metadata jsonb default null, p_activity text default 'run',
                               p_duration_s int default 3000)
returns uuid
language sql as $$
  insert into runs (user_id, started_at, duration_s, distance_m, source, activity_type, metadata)
  values (p_user, p_at, p_duration_s, p_distance_m, 'app', p_activity, p_metadata)
  returning id;
$$;

create function pg_temp.linked(p_workout uuid) returns uuid
language sql as $$ select completed_run_id from plan_workouts where id = p_workout $$;

-- ─────────── local day, not UTC ───────────

create temp table t (k text primary key, v uuid);

do $$
declare
  w uuid;
  u uuid;
begin
  -- UTC-8 (Pacific, January): 18:30 local on the 15th is 02:30 UTC on the 16th.
  u := pg_temp.mk_user('11860000-0000-0000-0000-0000000000a1', 'America/Los_Angeles');
  w := pg_temp.mk_plan(u, 'active');
  insert into t values ('pac_15', pg_temp.mk_workout(w, '2031-01-15', 'easy', 8000));
  insert into t values ('pac_16', pg_temp.mk_workout(w, '2031-01-16', 'easy', 8000));
  insert into t values ('pac_run', pg_temp.mk_run(u, '2031-01-16 02:30:00+00', 8100));

  -- UTC+10 (Brisbane, no DST): 07:00 local on the 16th is 21:00 UTC on the 15th.
  u := pg_temp.mk_user('11860000-0000-0000-0000-0000000000b1', 'Australia/Brisbane');
  w := pg_temp.mk_plan(u, 'active');
  insert into t values ('bne_15', pg_temp.mk_workout(w, '2031-01-15', 'easy', 8000));
  insert into t values ('bne_16', pg_temp.mk_workout(w, '2031-01-16', 'easy', 8000));
  insert into t values ('bne_run', pg_temp.mk_run(u, '2031-01-15 21:00:00+00', 8100));

  -- No zone stored: the server (UTC) date.
  u := pg_temp.mk_user('11860000-0000-0000-0000-0000000000c1', null);
  w := pg_temp.mk_plan(u, 'active');
  insert into t values ('utc_15', pg_temp.mk_workout(w, '2031-01-15', 'easy', 8000));
  insert into t values ('utc_16', pg_temp.mk_workout(w, '2031-01-16', 'easy', 8000));
  insert into t values ('utc_run', pg_temp.mk_run(u, '2031-01-16 02:30:00+00', 8100));
end;
$$;

select is(pg_temp.linked((select v from t where k = 'pac_15')), (select v from t where k = 'pac_run'),
  'UTC-8 evening: the run links the workout on the runner''s local day');
select is(pg_temp.linked((select v from t where k = 'pac_16')), null,
  'UTC-8 evening: the next UTC day''s workout stays open');
select is(pg_temp.linked((select v from t where k = 'bne_16')), (select v from t where k = 'bne_run'),
  'UTC+10 morning: the run links the workout on the runner''s local day');
select is(pg_temp.linked((select v from t where k = 'bne_15')), null,
  'UTC+10 morning: the previous UTC day''s workout stays open');
select is(pg_temp.linked((select v from t where k = 'utc_16')), (select v from t where k = 'utc_run'),
  'no stored zone falls back to the server date');
select ok(exists (select 1 from private.plan_workout_auto_links where workout_id = (select v from t where k = 'pac_15')),
  'a matcher link is recorded as the matcher''s');
select ok((select completed_at is not null and skipped_at is null and not manually_completed
           from plan_workouts where id = (select v from t where k = 'pac_15')),
  'a matcher link stamps completed_at');

-- ─────────── distance bounds and activity ───────────

do $$
declare
  w uuid;
  u uuid;
begin
  u := pg_temp.mk_user('11860000-0000-0000-0000-0000000000d1', 'UTC');
  w := pg_temp.mk_plan(u, 'active');
  insert into t values ('over', pg_temp.mk_workout(w, '2031-01-10', 'long', 10000));
  insert into t values ('over_run', pg_temp.mk_run(u, '2031-01-10 08:00:00+00', 13000));
  insert into t values ('under', pg_temp.mk_workout(w, '2031-01-11', 'easy', 10000));
  perform pg_temp.mk_run(u, '2031-01-11 08:00:00+00', 7400);
  insert into t values ('edge', pg_temp.mk_workout(w, '2031-01-12', 'easy', 10000));
  insert into t values ('edge_run', pg_temp.mk_run(u, '2031-01-12 08:00:00+00', 7500));
  insert into t values ('ride', pg_temp.mk_workout(w, '2031-01-13', 'easy', 10000));
  perform pg_temp.mk_run(u, '2031-01-13 08:00:00+00', 30000, null, 'cycle');
  insert into t values ('rest', pg_temp.mk_workout(w, '2031-01-14', 'rest', 5000));
  perform pg_temp.mk_run(u, '2031-01-14 08:00:00+00', 5000);
  insert into t values ('walkrun', pg_temp.mk_workout(w, '2031-01-15', 'walk_run', null, 1800));
  insert into t values ('walkrun_run', pg_temp.mk_run(u, '2031-01-15 08:00:00+00', 3000, null, 'run', 1900));
  insert into t values ('early', pg_temp.mk_workout(w, '2031-01-17', 'long', 10000));
  perform pg_temp.mk_run(u, '2031-01-16 08:00:00+00', 10000);
end;
$$;

select is(pg_temp.linked((select v from t where k = 'over')), (select v from t where k = 'over_run'),
  'a run 30% over the target links (no upper bound)');
select is(pg_temp.linked((select v from t where k = 'under')), null,
  'a run under 75% of the target does not link');
select is(pg_temp.linked((select v from t where k = 'edge')), (select v from t where k = 'edge_run'),
  'exactly 75% of the target links');
select is(pg_temp.linked((select v from t where k = 'ride')), null,
  'a ride never links a planned workout');
select is(pg_temp.linked((select v from t where k = 'rest')), null,
  'a rest day never links');
select is(pg_temp.linked((select v from t where k = 'walkrun')), (select v from t where k = 'walkrun_run'),
  'a duration-only walk-run session links on duration');
select is(pg_temp.linked((select v from t where k = 'early')), null,
  'a run the day before never links silently');

-- ─────────── plan scope and skips ───────────

do $$
declare
  u uuid;
begin
  u := pg_temp.mk_user('11860000-0000-0000-0000-0000000000e1', 'UTC');
  insert into t values ('abandoned', pg_temp.mk_workout(pg_temp.mk_plan(u, 'abandoned'), '2031-01-10', 'easy', 8000));
  insert into t values ('paused', pg_temp.mk_workout(pg_temp.mk_plan(u, 'paused'), '2031-01-10', 'easy', 8000));
  insert into t values ('template', pg_temp.mk_workout(pg_temp.mk_plan(u, 'completed', true), '2031-01-10', 'easy', 8000));
  insert into t values ('active', pg_temp.mk_workout(pg_temp.mk_plan(u, 'active'), '2031-01-10', 'easy', 8000));
  insert into t values ('scope_run', pg_temp.mk_run(u, '2031-01-10 08:00:00+00', 8000));

  u := pg_temp.mk_user('11860000-0000-0000-0000-0000000000e2', 'UTC');
  insert into t values ('skipped', pg_temp.mk_workout(pg_temp.mk_plan(u, 'active'), '2031-01-10', 'easy', 8000));
  update plan_workouts set skipped_at = now() where id = (select v from t where k = 'skipped');
  perform pg_temp.mk_run(u, '2031-01-10 08:00:00+00', 8000);
end;
$$;

select is(pg_temp.linked((select v from t where k = 'active')), (select v from t where k = 'scope_run'),
  'the active plan''s workout links');
select is(pg_temp.linked((select v from t where k = 'abandoned')), null, 'an abandoned plan is never matched');
select is(pg_temp.linked((select v from t where k = 'paused')), null, 'a paused plan is never matched');
select is(pg_temp.linked((select v from t where k = 'template')), null, 'a template copy is never matched');
select ok((select completed_run_id is null and skipped_at is not null from plan_workouts
           where id = (select v from t where k = 'skipped')),
  'a skipped workout is never matched and stays skipped');

-- ─────────── explicit plan_workout_id ───────────

do $$
declare
  w uuid;
  u uuid;
  other uuid;
begin
  u := pg_temp.mk_user('11860000-0000-0000-0000-0000000000f1', 'UTC');
  w := pg_temp.mk_plan(u, 'active');
  insert into t values ('expl', pg_temp.mk_workout(w, '2031-01-20', 'tempo', 10000));
  insert into t values ('expl_run', pg_temp.mk_run(u, '2031-01-19 08:00:00+00', 2000,
    jsonb_build_object('plan_workout_id', (select v from t where k = 'expl'))));

  insert into t values ('expl_skipped', pg_temp.mk_workout(w, '2031-01-21', 'easy', 10000));
  update plan_workouts set skipped_at = now() where id = (select v from t where k = 'expl_skipped');
  insert into t values ('expl_skipped_run', pg_temp.mk_run(u, '2031-01-21 08:00:00+00', 4000,
    jsonb_build_object('plan_workout_id', (select v from t where k = 'expl_skipped'))));

  -- Linked by hand to another run first: the explicit run must not take it.
  insert into t values ('hand', pg_temp.mk_workout(w, '2031-01-22', 'easy', 10000));
  insert into t values ('hand_run', pg_temp.mk_run(u, '2031-01-24 08:00:00+00', 3000));
  update plan_workouts set completed_run_id = (select v from t where k = 'hand_run'), completed_at = now()
  where id = (select v from t where k = 'hand');
  perform pg_temp.mk_run(u, '2031-01-22 08:00:00+00', 10000,
    jsonb_build_object('plan_workout_id', (select v from t where k = 'hand')));

  -- Someone else's workout.
  other := pg_temp.mk_user('11860000-0000-0000-0000-0000000000f2', 'UTC');
  insert into t values ('foreign', pg_temp.mk_workout(pg_temp.mk_plan(other, 'active'), '2031-01-20', 'easy', 2000));
  perform pg_temp.mk_run(u, '2031-01-20 18:00:00+00', 2000,
    jsonb_build_object('plan_workout_id', (select v from t where k = 'foreign')));

  -- An explicit link takes the workout from an auto-matched run.
  insert into t values ('taken', pg_temp.mk_workout(w, '2031-01-25', 'easy', 10000));
  insert into t values ('taken_auto', pg_temp.mk_run(u, '2031-01-25 07:00:00+00', 10000));
  insert into t values ('taken_expl', pg_temp.mk_run(u, '2031-01-25 18:00:00+00', 5000,
    jsonb_build_object('plan_workout_id', (select v from t where k = 'taken'))));
end;
$$;

select is(pg_temp.linked((select v from t where k = 'expl')), (select v from t where k = 'expl_run'),
  'plan_workout_id links at any distance, on any day');
select ok(not exists (select 1 from private.plan_workout_auto_links where workout_id = (select v from t where k = 'expl')),
  'an explicit link is not an auto match');
select ok((select completed_run_id = (select v from t where k = 'expl_skipped_run') and skipped_at is null
           from plan_workouts where id = (select v from t where k = 'expl_skipped')),
  'running a skipped workout from its card links it and clears the skip');
select is(pg_temp.linked((select v from t where k = 'hand')), (select v from t where k = 'hand_run'),
  'plan_workout_id never takes a workout linked by hand');
select is(pg_temp.linked((select v from t where k = 'foreign')), null,
  'plan_workout_id naming another user''s workout is ignored');
select is(pg_temp.linked((select v from t where k = 'taken')), (select v from t where k = 'taken_expl'),
  'plan_workout_id takes the workout from an auto-matched run');

-- ─────────── two runs on one day ───────────

do $$
declare
  w uuid;
  u uuid;
begin
  u := pg_temp.mk_user('11860000-0000-0000-0000-0000000000a2', 'UTC');
  w := pg_temp.mk_plan(u, 'active');
  insert into t values ('two', pg_temp.mk_workout(w, '2031-01-10', 'long', 10000));
  insert into t values ('two_first', pg_temp.mk_run(u, '2031-01-10 07:00:00+00', 8000));
  insert into t values ('two_after_first', pg_temp.linked((select v from t where k = 'two')));
  insert into t values ('two_closer', pg_temp.mk_run(u, '2031-01-10 18:00:00+00', 9800));
  insert into t values ('two_farther', pg_temp.mk_run(u, '2031-01-10 20:00:00+00', 12500));

  -- A hand link is sticky: a closer run later never steals it.
  insert into t values ('sticky', pg_temp.mk_workout(w, '2031-01-12', 'long', 10000));
  insert into t values ('sticky_a', pg_temp.mk_run(u, '2031-01-09 07:00:00+00', 8000));
  update plan_workouts set completed_run_id = (select v from t where k = 'sticky_a'), completed_at = now()
  where id = (select v from t where k = 'sticky');
  perform pg_temp.mk_run(u, '2031-01-12 18:00:00+00', 10000);

  -- A run moved to another day leaves its old workout and matches the new one.
  insert into t values ('move_from', pg_temp.mk_workout(w, '2031-01-13', 'easy', 6000));
  insert into t values ('move_to', pg_temp.mk_workout(w, '2031-01-14', 'easy', 6000));
  insert into t values ('move_run', pg_temp.mk_run(u, '2031-01-13 08:00:00+00', 6000));
  update runs set started_at = '2031-01-14 08:00:00+00' where id = (select v from t where k = 'move_run');

  -- Unlink is sticky: the runner takes the auto-matched run off; a later run
  -- write that day re-matches the day, and must not put it back.
  insert into t values ('unlinked', pg_temp.mk_workout(w, '2031-01-16', 'easy', 10000));
  insert into t values ('unlinked_a', pg_temp.mk_run(u, '2031-01-16 07:00:00+00', 10000));
  update plan_workouts set completed_run_id = null, completed_at = null
  where id = (select v from t where k = 'unlinked');
  perform pg_temp.mk_run(u, '2031-01-16 12:00:00+00', 3000);
  insert into t values ('unlinked_after_short', pg_temp.linked((select v from t where k = 'unlinked')));
  insert into t values ('unlinked_b', pg_temp.mk_run(u, '2031-01-16 18:00:00+00', 9000));
end;
$$;

select is((select v from t where k = 'two_after_first'), (select v from t where k = 'two_first'),
  'the first run of the day links while it is the only one');
select is(pg_temp.linked((select v from t where k = 'two')), (select v from t where k = 'two_closer'),
  'a later, closer run takes the workout; a farther one does not');
select ok(exists (select 1 from private.plan_workout_auto_links where workout_id = (select v from t where k = 'two')),
  'the re-link is still an auto match');
select is(pg_temp.linked((select v from t where k = 'sticky')), (select v from t where k = 'sticky_a'),
  'a link made by hand is never stolen by a closer run');
select ok(pg_temp.linked((select v from t where k = 'move_from')) is null
          and pg_temp.linked((select v from t where k = 'move_to')) = (select v from t where k = 'move_run'),
  'a run moved to another day leaves its old workout and matches the new day');

-- ─────────── a runner's own write, through RLS ───────────

do $$
declare
  u uuid;
begin
  u := pg_temp.mk_user('11860000-0000-0000-0000-0000000000a3', 'Europe/Berlin');
  update user_profiles set age_confirmed_at = now() where id = u;
  insert into t values ('own', pg_temp.mk_workout(pg_temp.mk_plan(u, 'active'), '2031-01-10', 'easy', 5000));
end;
$$;

grant select, insert on t to authenticated;
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"11860000-0000-0000-0000-0000000000a3","role":"authenticated"}';
insert into t values ('own_run', pg_temp.mk_run('11860000-0000-0000-0000-0000000000a3', '2031-01-10 07:00:00+00', 5200));
select throws_ok(
  $$ select * from private.plan_workout_auto_links $$,
  '42501', null,
  'the matcher''s bookkeeping is not readable by a client'
);
reset role;
set local "request.jwt.claims" = '';

select is(pg_temp.linked((select v from t where k = 'own')), (select v from t where k = 'own_run'),
  'a run the runner saves themselves links through the same trigger');

delete from runs where id = (select v from t where k = 'own_run');
select ok(pg_temp.linked((select v from t where k = 'own')) is null
          and not exists (select 1 from private.plan_workout_auto_links where workout_id = (select v from t where k = 'own')),
  'deleting the run reopens the workout and drops the matcher''s record');

select is((select v from t where k = 'unlinked_after_short'), null,
  'a run the runner unlinked is never put back by a later write that day');
select is(pg_temp.linked((select v from t where k = 'unlinked')), (select v from t where k = 'unlinked_b'),
  'another qualifying run can still take the unlinked workout');

-- ─────────── a delete re-matches the day ───────────

do $$
declare
  w uuid;
  u uuid;
begin
  u := pg_temp.mk_user('11860000-0000-0000-0000-0000000000a4', 'UTC');
  w := pg_temp.mk_plan(u, 'active');
  insert into t values ('del', pg_temp.mk_workout(w, '2031-01-10', 'long', 10000));
  insert into t values ('del_closer', pg_temp.mk_run(u, '2031-01-10 07:00:00+00', 10000));
  insert into t values ('del_shorter', pg_temp.mk_run(u, '2031-01-10 18:00:00+00', 8000));
  insert into t values ('del_before', pg_temp.linked((select v from t where k = 'del')));
  delete from runs where id = (select v from t where k = 'del_closer');
end;
$$;

select is((select v from t where k = 'del_before'), (select v from t where k = 'del_closer'),
  'the closer run held the workout');
select is(pg_temp.linked((select v from t where k = 'del')), (select v from t where k = 'del_shorter'),
  'deleting it hands the workout to the next closest run that day');

-- ─────────── a matcher failure is a warning, never a lost run ───────────

create function public.t1186_refuse_plan_workout_update() returns trigger
language plpgsql as $$ begin raise exception 'simulated plan_workouts failure'; end; $$;
create trigger t1186_refuse before update on plan_workouts
  for each row execute function public.t1186_refuse_plan_workout_update();

do $$
declare
  u uuid := pg_temp.mk_user('11860000-0000-0000-0000-0000000000a5', 'UTC');
begin
  insert into t values ('boom', pg_temp.mk_workout(pg_temp.mk_plan(u, 'active'), '2031-01-10', 'easy', 5000));
end;
$$;

select lives_ok(
  $$ insert into t values ('boom_run', pg_temp.mk_run('11860000-0000-0000-0000-0000000000a5', '2031-01-10 08:00:00+00', 5000,
       jsonb_build_object('plan_workout_id', (select v from t where k = 'boom')))) $$,
  'a run insert survives the explicit link and the re-match both failing'
);
select ok(exists (select 1 from runs where id = (select v from t where k = 'boom_run')),
  'the run is saved');
select ok(pg_temp.linked((select v from t where k = 'boom')) is null
          and coalesce(current_setting('threkir.plan_matcher', true), '') <> 'on',
  'nothing was linked, and the failed step did not leave the matcher flag on');

drop trigger t1186_refuse on plan_workouts;

select ok(
  (select bool_and(relrowsecurity) from pg_class
   where oid in ('private.plan_workout_auto_links'::regclass, 'private.plan_workout_link_refusals'::regclass)),
  'both private tables have RLS enabled'
);

-- ─────────── the core write never fails on matching ───────────

select lives_ok(
  $$ select pg_temp.mk_run('11860000-0000-0000-0000-0000000000a2', '2031-01-15 08:00:00+00', 5000,
       '{"plan_workout_id":"not-a-uuid"}') $$,
  'a malformed plan_workout_id never blocks the run insert'
);
select is(
  (select count(*)::int from runs where user_id = '11860000-0000-0000-0000-0000000000a2'
     and started_at = '2031-01-15 08:00:00+00'),
  1,
  'the run with a malformed plan_workout_id is saved'
);

select * from finish();
rollback;
