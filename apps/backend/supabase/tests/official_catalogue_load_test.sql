-- The official content catalogue load (migrations 20271211000001..004,
-- issue #1190, decisions § 2446): private.load_official_catalogue publishes
-- library plans, library gym routines and per-period challenge boards as the
-- official club, is safe to run on every release (a second identical load
-- writes nothing and reports `unchanged`), retires what the catalogue drops
-- instead of deleting it, holds a disputed takedown, keeps a started board's
-- terms, and loads race courses only while official_race_courses is on.
-- Official is derived (is_official), so the rows must read official through
-- the same computed fields every client reads.

begin;

select plan(59);

-- ── Fixture ──
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000c3a01', 'authenticated', 'authenticated', 'oc-owner@oc.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000c3a02', 'authenticated', 'authenticated', 'oc-outsider@oc.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000c3a03', 'authenticated', 'authenticated', 'oc-other@oc.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000c3a04', 'authenticated', 'authenticated', 'oc-runner@oc.local', '', now(), now());

select tests.confirm_consent();

insert into clubs (id, owner_id, name, slug, is_public)
values
  ('00000000-0000-0000-0000-0000000c3b01', '00000000-0000-0000-0000-0000000c3a01', 'OC Official', 'oc-official', true),
  ('00000000-0000-0000-0000-0000000c3b02', '00000000-0000-0000-0000-0000000c3a03', 'OC Other', 'oc-other', true);

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';
update clubs set is_verified = true
 where id in ('00000000-0000-0000-0000-0000000c3b01', '00000000-0000-0000-0000-0000000c3b02');
reset role;
set local "request.jwt.claims" = '{}';

insert into race_listings (id, provider, provider_race_id, name, race_date, distance_m)
values
  ('00000000-0000-0000-0000-0000000c3c01', 'runsignup', 'oc-1', 'OC Marathon', '2027-10-10', 42195),
  ('00000000-0000-0000-0000-0000000c3c02', 'runsignup', 'oc-2', 'OC Claimed 10K', '2027-10-11', 10000);
update race_listings set organiser_club_id = '00000000-0000-0000-0000-0000000c3b02'
 where id = '00000000-0000-0000-0000-0000000c3c02';

create temp table catalogues (k text primary key, j jsonb not null);
insert into catalogues (k, j) values
('base', $json${
  "plans": [
    {"slug": "oc-5k", "name": "OC 5K", "goal_event": "distance_5k", "goal_distance_m": 5000, "days_per_week": 3,
     "source": "generated", "end_day": 13,
     "weeks": [
       {"week_index": 0, "phase": "base", "target_volume_m": 9000,
        "workouts": [{"day": 0, "kind": "easy", "target_distance_m": 3000},
                     {"day": 2, "kind": "interval", "target_distance_m": 3000,
                      "structure": {"repeats": {"count": 4, "distance_m": 400, "recovery_distance_m": 200,
                                                "recovery_pace": "jog"}}},
                     {"day": 5, "kind": "long", "target_distance_m": 3000}]},
       {"week_index": 1, "phase": "race", "target_volume_m": 8000,
        "workouts": [{"day": 7, "kind": "easy", "target_distance_m": 3000},
                     {"day": 13, "kind": "race", "target_distance_m": 5000}]}]}
  ],
  "gym_routines": [
    {"slug": "oc-strength", "title": "OC Strength", "notes": "Pick a load you can lift with good form.",
     "periodisation": "none",
     "exercises": [
       {"name": "Romanian Deadlift", "modality": "weight_reps",
        "sets": [{"target_reps_min": 8, "target_reps_max": 10, "rest_s": 90, "target_rpe": 7},
                 {"target_reps_min": 8, "target_reps_max": 10, "rest_s": 90, "target_rpe": 7}]},
       {"name": "Plank", "modality": "time", "notes": "Keep a straight line.",
        "sets": [{"target_duration_s": 30, "rest_s": 45}]}]}
  ],
  "challenges": [
    {"slug": "oc-monthly-50k", "recurrence": "monthly", "title": "{period}: run 50 km",
     "description": "An official challenge.", "metric": "distance", "goal_value": 50000, "activity_type": "run"},
    {"slug": "oc-yearly-1000k", "recurrence": "yearly", "title": "Run 1,000 km in {period}",
     "description": null, "metric": "distance", "goal_value": 1000000, "activity_type": null}
  ],
  "race_courses": [
    {"slug": "oc-marathon", "listing": {"provider": "runsignup", "provider_race_id": "oc-1"},
     "name": "OC Marathon course", "description": "Traced from the race's published course map.",
     "surface": "road", "distance_m": 1990, "elevation_m": 4,
     "waypoints": [{"lat": 11.0, "lng": 21.0}, {"lat": 11.0045, "lng": 21.0}, {"lat": 11.0045, "lng": 21.0045}]}
  ]
}$json$::jsonb);
insert into catalogues (k, j)
select 'redraw_plan', jsonb_set(j, '{plans,0,weeks,0,workouts,0,target_distance_m}', '3500') from catalogues where k = 'base'
union all
select 'rename_routine', jsonb_set(j, '{gym_routines,0,title}', '"OC Strength (renamed)"') from catalogues where k = 'base'
union all
select 'goal_up', jsonb_set(j, '{challenges,0,goal_value}', '60000') from catalogues where k = 'base'
union all
select 'drop_plan', jsonb_set(j, '{plans}', '[]') from catalogues where k = 'base'
union all
select 'drop_monthly', j #- '{challenges,0}' from catalogues where k = 'base'
union all
select 'drop_course', jsonb_set(j, '{race_courses}', '[]') from catalogues where k = 'base'
union all
select 'claimed', jsonb_set(j, '{race_courses,0,listing,provider_race_id}', '"oc-2"') from catalogues where k = 'base'
union all
select 'missing', jsonb_set(j, '{race_courses,0,listing,provider_race_id}', '"oc-404"') from catalogues where k = 'base'
union all
select 'no_courses_key', j - 'race_courses' from catalogues where k = 'base'
union all
select 'dup_slug', jsonb_set(j, '{plans}', (j -> 'plans') || (j -> 'plans')) from catalogues where k = 'base';
grant select on catalogues to service_role, authenticated;

create temp table loads (n int, kind text, slug text, target_id uuid, action text);
grant select, insert on loads to service_role;
grant select on loads to authenticated;
create temp table clones (k text, id uuid);
grant select, insert on clones to authenticated;

create function pg_temp.load(p_n int, p_k text, p_now timestamptz default '2027-03-10 12:00+00')
returns void language sql as $$
  insert into loads
  select p_n, l.* from private.load_official_catalogue(
    (select j from catalogues where k = p_k),
    '00000000-0000-0000-0000-0000000c3b01', '00000000-0000-0000-0000-0000000c3a01', p_now) l;
$$;

create function pg_temp.actions(p_n int) returns text language sql as $$
  select string_agg(kind || ':' || slug || '=' || action, ', ' order by kind, slug) from loads where n = p_n;
$$;

-- ── Refusals ──
select ok(not has_function_privilege('authenticated', 'private.load_official_catalogue(jsonb, uuid, uuid, timestamptz)', 'execute'),
  'authenticated cannot execute the loader');
select ok(not has_function_privilege('anon', 'private.load_official_catalogue(jsonb, uuid, uuid, timestamptz)', 'execute'),
  'anon cannot execute the loader');

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';

select throws_ok(
  $$ select * from private.load_official_catalogue((select j from catalogues where k = 'base'),
       '00000000-0000-0000-0000-0000000c3b01', '00000000-0000-0000-0000-0000000c3a02') $$,
  '42501', null, 'an author who is not an owner or admin of the club is refused');
select throws_ok(
  $$ select * from private.load_official_catalogue((select j from catalogues where k = 'no_courses_key'),
       '00000000-0000-0000-0000-0000000c3b01', '00000000-0000-0000-0000-0000000c3a01') $$,
  '22023', null, 'a catalogue missing a list is refused, so a truncated payload cannot retire everything');
select throws_ok(
  $$ select * from private.load_official_catalogue((select j from catalogues where k = 'dup_slug'),
       '00000000-0000-0000-0000-0000000c3b01', '00000000-0000-0000-0000-0000000c3a01') $$,
  '22023', null, 'a repeated slug is refused');

-- ── 1: first load ──
select pg_temp.load(1, 'base');
select is(pg_temp.actions(1),
  'challenge:oc-monthly-50k@2027-03=created, challenge:oc-monthly-50k@2027-04=created, '
  || 'challenge:oc-yearly-1000k@2027=created, gym_routine:oc-strength=created, '
  || 'race_course:oc-marathon=gated, training_plan:oc-5k=created',
  'the first load creates every item, publishes the month in progress and the next one, and gates the course');

select is(
  (select p.is_template and p.is_public_template and p.club_id = '00000000-0000-0000-0000-0000000c3b01'
          and p.status = 'completed' and p.start_date = '2001-01-01' and p.end_date = '2001-01-14'
     from training_plans p where p.id = (select target_id from loads where n = 1 and slug = 'oc-5k')),
  true, 'the plan is a public library template of the club on the reference week');
select is(
  (select count(*)::int from plan_workouts o join plan_weeks w on w.id = o.week_id
    where w.plan_id = (select target_id from loads where n = 1 and slug = 'oc-5k')),
  5, 'the plan carries every workout');
select is(
  (select public.is_official(p) from training_plans p where p.id = (select target_id from loads where n = 1 and slug = 'oc-5k')),
  true, 'the plan reads official');
select is(
  (select public.is_official(r) and r.is_public_template and r.exercise_count = 2
     from gym_routines r where r.id = (select target_id from loads where n = 1 and slug = 'oc-strength')),
  true, 'the routine is a public, official template with its exercise count');
select is(
  (select count(*)::int from gym_routine_sets s join gym_routine_exercises e on e.id = s.routine_exercise_id
    where e.routine_id = (select target_id from loads where n = 1 and slug = 'oc-strength')),
  3, 'the routine carries every set');
select is(
  (select exercise_key from gym_routine_exercises
    where routine_id = (select target_id from loads where n = 1 and slug = 'oc-strength') and position = 0),
  normalise_exercise_name('Romanian Deadlift'), 'the exercise key is stamped as for any routine');
select is(
  (select c.title || '|' || c.starts_at::text || '|' || c.ends_at::text || '|' || c.scope
     from challenges c where c.id = (select target_id from loads where n = 1 and slug = 'oc-monthly-50k@2027-03')),
  'March 2027: run 50 km|2027-03-01 00:00:00+00|2027-04-01 00:00:00+00|individual',
  'a monthly board covers its calendar month in UTC and names it');
select is(
  (select public.is_official(c) and c.is_public from challenges c
    where c.id = (select target_id from loads where n = 1 and slug = 'oc-yearly-1000k@2027')),
  true, 'a board reads official');

reset role;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000c3a04","role":"authenticated"}';
set local role authenticated;
select is(
  (select is_official from public_gym_routines where id = (select target_id from loads where n = 1 and slug = 'oc-strength')),
  true, 'a runner sees the routine in the public library as official');
select is(
  (select public.is_official(t) from training_plans t where t.id = (select target_id from loads where n = 1 and slug = 'oc-5k')),
  true, 'a runner sees the plan in the public library as official');
insert into clones
select 'plan', clone_public_plan((select target_id from loads where n = 1 and slug = 'oc-5k'), '2027-05-03')
union all
select 'routine', clone_gym_routine_template((select target_id from loads where n = 1 and slug = 'oc-strength'));
select is(
  (select count(*)::int from plan_weeks where plan_id = (select id from clones where k = 'plan')),
  2, 'a runner clones the official plan onto their own start date');
select is(
  (select exercise_count from gym_routines where id = (select id from clones where k = 'routine')),
  2, 'and adopts the official routine');
reset role;
set local "request.jwt.claims" = '{"role":"service_role"}';
set local role service_role;

-- ── 2: identical load ──
create temp table plan_stamp on commit drop as
  select updated_at from training_plans where id = (select target_id from loads where n = 1 and slug = 'oc-5k');
select pg_temp.load(2, 'base');
select is(
  (select count(*)::int from loads where n = 2 and action not in ('unchanged', 'gated')), 0,
  'an identical load reports every item unchanged');
select is(
  (select updated_at from training_plans where id = (select target_id from loads where n = 1 and slug = 'oc-5k')),
  (select updated_at from plan_stamp), 'and writes nothing to the plan');
select is(
  (select count(distinct target_id)::int from loads where n in (1, 2) and kind <> 'race_course'),
  5, 'the same rows are kept');

-- ── 3: a changed plan design ──
select pg_temp.load(3, 'redraw_plan');
select is((select action from loads where n = 3 and slug = 'oc-5k'), 'updated', 'a changed workout updates the plan');
select is(
  (select count(*)::int from loads where n = 3 and slug <> 'oc-5k' and action not in ('unchanged', 'gated')), 0,
  'and nothing else');
select is(
  (select o.target_distance_m from plan_workouts o join plan_weeks w on w.id = o.week_id
    where w.plan_id = (select target_id from loads where n = 1 and slug = 'oc-5k') and o.scheduled_date = '2001-01-01'),
  3500.00, 'the new design is stored');
select is((select target_id from loads where n = 3 and slug = 'oc-5k'),
  (select target_id from loads where n = 1 and slug = 'oc-5k'), 'in the same plan row');
select pg_temp.load(4, 'redraw_plan');
select is((select action from loads where n = 4 and slug = 'oc-5k'), 'unchanged', 'and the next load is unchanged');

-- ── 5: a renamed routine ──
select pg_temp.load(5, 'rename_routine');
select is((select action from loads where n = 5 and slug = 'oc-strength'), 'updated', 'a renamed routine updates');
select is((select title from gym_routines where id = (select target_id from loads where n = 1 and slug = 'oc-strength')),
  'OC Strength (renamed)', 'with its new title');

-- ── 6: a started board keeps its terms ──
select pg_temp.load(6, 'goal_up');
select is((select action from loads where n = 6 and slug = 'oc-monthly-50k@2027-03'), 'unchanged',
  'a board whose window has started keeps its goal');
select is((select action from loads where n = 6 and slug = 'oc-monthly-50k@2027-04'), 'updated',
  'a board not yet started takes the new goal');
select is(
  (select goal_value from challenges where id = (select target_id from loads where n = 1 and slug = 'oc-monthly-50k@2027-04')),
  60000::numeric, 'the new goal is stored');

-- ── 7: a later month rolls the boards forward ──
select pg_temp.load(7, 'goal_up', '2027-04-20 12:00+00');
select is(pg_temp.actions(7),
  'challenge:oc-monthly-50k@2027-04=unchanged, challenge:oc-monthly-50k@2027-05=created, '
  || 'challenge:oc-monthly-50k@2027-06=created, challenge:oc-yearly-1000k@2027=unchanged, '
  || 'gym_routine:oc-strength=unchanged, '
  || 'race_course:oc-marathon=gated, training_plan:oc-5k=unchanged',
  'every month starting inside the 45-day lookahead is published and an ended board is left alone');

select pg_temp.load(71, 'goal_up', '2027-12-20 12:00+00');
select is(
  (select string_agg(slug || '=' || action, ', ' order by slug) from loads where n = 71 and kind = 'challenge'),
  'oc-monthly-50k@2028-01=created, oc-monthly-50k@2028-02=created, oc-yearly-1000k@2027=unchanged, '
  || 'oc-yearly-1000k@2028=created',
  'December, more than half over, is not opened late; the months and the year inside the lookahead are');

-- ── 8: a dropped plan is retired once ──
select pg_temp.load(8, 'drop_plan');
select is((select action from loads where n = 8 and slug = 'oc-5k'), 'retired', 'a dropped plan is retired');
select is(
  (select not is_public_template and club_id is null from training_plans
    where id = (select target_id from loads where n = 1 and slug = 'oc-5k')),
  true, 'unpublished and detached from the club, not deleted');
select pg_temp.load(9, 'drop_plan');
select is((select count(*)::int from loads where n = 9 and slug = 'oc-5k'), 0, 'and reported only once');
select pg_temp.load(10, 'base');
select is((select action || ':' || (target_id = (select target_id from loads where n = 1 and slug = 'oc-5k'))::text
             from loads where n = 10 and slug = 'oc-5k'),
  'updated:true', 'naming it again republishes the same row');

-- ── 11: a dropped challenge retires its open boards ──
select pg_temp.load(11, 'drop_monthly');
select is(
  (select string_agg(slug || '=' || action, ', ' order by slug) from loads where n = 11 and kind = 'challenge'),
  'oc-monthly-50k@2027-03=retired, oc-monthly-50k@2027-04=retired, oc-monthly-50k@2027-05=retired, '
  || 'oc-monthly-50k@2027-06=retired, oc-monthly-50k@2028-01=retired, oc-monthly-50k@2028-02=retired, '
  || 'oc-yearly-1000k@2027=unchanged',
  'every open board of a dropped challenge is retired');
select is(
  (select bool_and(not is_public) from challenges c join loads l on l.target_id = c.id
    where l.n = 11 and l.action = 'retired'),
  true, 'made private, so its participants keep it');

-- ── 12: a takedown holds ──
insert into organiser_dispute_actions (target_kind, target_id, organiser_club_name, action)
values ('gym_routine', (select target_id from loads where n = 1 and slug = 'oc-strength'), 'OC Other', 'takedown');
update gym_routines set is_public_template = false
 where id = (select target_id from loads where n = 1 and slug = 'oc-strength');
select pg_temp.load(12, 'base');
select is((select action from loads where n = 12 and slug = 'oc-strength'), 'held',
  'a routine taken down after a dispute is held');
select is(
  (select is_public_template from gym_routines where id = (select target_id from loads where n = 1 and slug = 'oc-strength')),
  false, 'and not republished');

-- ── 13: the course gate ──
select is((select count(*)::int from routes where club_id = '00000000-0000-0000-0000-0000000c3b01'), 0,
  'with the flag off no course route is written');
select is((select organiser_club_id from race_listings where id = '00000000-0000-0000-0000-0000000c3c01'), null::uuid,
  'and no race is claimed');

reset role;
update private.feature_flags set enabled = true where name = 'official_race_courses';
set local role service_role;

select pg_temp.load(13, 'base');
select is((select action from loads where n = 13 and kind = 'race_course'), 'created', 'with the flag on the course loads');
select is(
  (select l.organiser_club_id = '00000000-0000-0000-0000-0000000c3b01' and l.course_source = 'traced'
          and l.route_id = (select target_id from loads where n = 13 and kind = 'race_course') and l.is_verified
     from race_listings l where l.id = '00000000-0000-0000-0000-0000000c3c01'),
  true, 'the race is claimed by the club and linked as traced');
select is(
  (select r.is_public and r.club_id = '00000000-0000-0000-0000-0000000c3b01'
     from routes r where r.id = (select target_id from loads where n = 13 and kind = 'race_course')),
  true, 'on a public club route');
select is(
  (select count(*)::int from race_listing_audit where listing_id = '00000000-0000-0000-0000-0000000c3c01'),
  2, 'the claim and the link are audited');
select pg_temp.load(14, 'base');
select is((select action from loads where n = 14 and kind = 'race_course'), 'unchanged', 'a second load is unchanged');

select pg_temp.load(15, 'claimed');
select is((select action from loads where n = 15 and kind = 'race_course'), 'claimed_elsewhere',
  'a race another club has claimed is left to it');
select is((select organiser_club_id from race_listings where id = '00000000-0000-0000-0000-0000000c3c02'),
  '00000000-0000-0000-0000-0000000c3b02'::uuid, 'and its claim stands');
select pg_temp.load(16, 'missing');
select is((select action from loads where n = 16 and kind = 'race_course'), 'missing_listing',
  'a course whose race is not listed is reported, not loaded');

select pg_temp.load(17, 'drop_course');
select is((select action from loads where n = 17 and kind = 'race_course'), 'retired', 'a dropped course is retired');
select is(
  (select l.route_id is null and l.course_source is null from race_listings l
    where l.id = '00000000-0000-0000-0000-0000000c3c01'),
  true, 'its race is unlinked');
select is(
  (select is_public from routes where id = (select target_id from loads where n = 13 and kind = 'race_course')),
  false, 'and its route made private, not deleted');

-- ── Ownership change re-authors the live rows ──
reset role;
insert into club_members (club_id, user_id, role, status)
values ('00000000-0000-0000-0000-0000000c3b01', '00000000-0000-0000-0000-0000000c3a04', 'admin', 'active');
set local role service_role;
insert into loads
select 18, l.* from private.load_official_catalogue(
  (select j from catalogues where k = 'base'),
  '00000000-0000-0000-0000-0000000c3b01', '00000000-0000-0000-0000-0000000c3a04', '2027-03-10 12:00+00') l;
select is(
  (select user_id from training_plans where id = (select target_id from loads where n = 1 and slug = 'oc-5k')),
  '00000000-0000-0000-0000-0000000c3a04'::uuid, 'a new publishing account re-authors the plan');
select is((select public.is_official(p) from training_plans p
            where p.id = (select target_id from loads where n = 1 and slug = 'oc-5k')),
  true, 'which stays official');

-- ── Client guard on public club routines ──
reset role;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000c3a03","role":"authenticated"}';
set local role authenticated;
select throws_ok(
  $$ insert into gym_routines (author_id, club_id, title, is_public_template)
     values ('00000000-0000-0000-0000-0000000c3a03', '00000000-0000-0000-0000-0000000c3b02', 'Mine', true) $$,
  '23514', null, 'a client still cannot publish a club routine to the public library');
reset role;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000c3a01","role":"authenticated"}';
set local role authenticated;
select lives_ok(
  $$ update gym_routines set title = 'Edited by an admin'
      where id = (select target_id from loads where n = 1 and slug = 'oc-strength') $$,
  'a club admin can still edit the club''s routine');

-- ── Browse keeps an official board with no entrants ──
reset role;
update challenges set created_at = now() - interval '30 days', ends_at = now() + interval '30 days',
                      starts_at = now() - interval '1 day', is_public = true
 where id = (select target_id from loads where n = 1 and slug = 'oc-yearly-1000k@2027');
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000c3a02","role":"authenticated"}';
set local role authenticated;
select ok(
  exists (select 1 from browse_public_challenges(null, 100, 0)
           where id = (select target_id from loads where n = 1 and slug = 'oc-yearly-1000k@2027')),
  'an official board with no entrants stays in the browse list after its first week');

select * from finish();
rollback;
