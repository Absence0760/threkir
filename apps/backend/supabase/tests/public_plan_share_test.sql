-- Pin "Train with me" (migration 20271103000002_public_plan_share,
-- decisions § 2262):
--   * public_plan_share is readable by anon, returns the plan's goal, weeks
--     and workouts by day offset, and withholds physiology, paces, notes,
--     dates and the user id
--   * it returns null for a non-public plan, and while the gate is closed
--   * a private author's name is withheld from anon, the plan still renders
--   * clone_public_plan records source_author_id; plan_started_from reads it
--     back to the copy's owner only
--   * a client cannot write source_author_id

begin;

select plan(22);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000ac001', 'authenticated', 'authenticated',
   'creator@plan-share.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000ac002', 'authenticated', 'authenticated',
   'follower@plan-share.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000000ac003', 'authenticated', 'authenticated',
   'other@plan-share.local', '', now(), now());

insert into user_profiles (id, display_name)
values
  ('00000000-0000-0000-0000-0000000ac001', 'Creator Cat'),
  ('00000000-0000-0000-0000-0000000ac002', 'Follower Fox'),
  ('00000000-0000-0000-0000-0000000ac003', 'Other Owl');

select tests.confirm_consent();

insert into private.feature_flags (name, enabled) values ('public_plan_share', true)
  on conflict (name) do update set enabled = true;

set local role service_role;

insert into training_plans (
  id, user_id, name, goal_event, goal_distance_m, goal_time_seconds,
  start_date, end_date, days_per_week, vdot, current_5k_seconds, notes,
  status, is_template, is_public_template, club_id
) values (
  'aaaaaaaa-0000-0000-0000-0000000ac001',
  '00000000-0000-0000-0000-0000000ac001',
  'Spring marathon block', 'distance_full', 42195, 10800,
  '2026-03-02', '2026-05-24', 5, 55.0, 1200, 'my own notes',
  'completed', true, true, null
), (
  'bbbbbbbb-0000-0000-0000-0000000ac001',
  '00000000-0000-0000-0000-0000000ac001',
  'Private plan', 'distance_full', 42195, null,
  '2026-03-02', '2026-05-24', 4, null, null, null,
  'active', false, false, null
);

insert into plan_weeks (id, plan_id, week_index, phase, target_volume_m, notes)
values
  ('aaaaaaaa-0000-0000-0000-0000000ac101',
   'aaaaaaaa-0000-0000-0000-0000000ac001', 0, 'base', 40000, 'week note'),
  ('aaaaaaaa-0000-0000-0000-0000000ac102',
   'aaaaaaaa-0000-0000-0000-0000000ac001', 1, 'build', 45000, null);

insert into plan_workouts (
  week_id, kind, scheduled_date, target_distance_m, target_pace_sec_per_km,
  target_hr_min_bpm, target_hr_max_bpm, notes, race_name, pace_zone
) values
  ('aaaaaaaa-0000-0000-0000-0000000ac101', 'easy', '2026-03-03', 8000, 330,
   null, null, 'workout note', null, 'easy'),
  ('aaaaaaaa-0000-0000-0000-0000000ac102', 'tempo', '2026-03-11', 10000, 260,
   null, null, null, null, 'threshold'),
  ('aaaaaaaa-0000-0000-0000-0000000ac102', 'race', '2026-03-15', 10000, 250,
   null, null, null, 'Club 10k', null);

-- ── Anonymous reader ──
set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';

-- 1. anon can execute the share lookup and gets the plan.
select is(
  (select public_plan_share('aaaaaaaa-0000-0000-0000-0000000ac001') ->> 'name'),
  'Spring marathon block',
  'anon reads a public plan through public_plan_share'
);

-- 2. Goal + weeks + workouts are there, workouts placed by day offset.
select results_eq(
  $$ select (d ->> 'goal_distance_m')::numeric::int,
            jsonb_array_length(d -> 'weeks'),
            (d #>> '{weeks,1,workouts,0,day}')::int,
            d #>> '{weeks,1,workouts,0,kind}',
            (d #>> '{weeks,1,workouts,0,target_distance_m}')::numeric::int
     from (select public_plan_share('aaaaaaaa-0000-0000-0000-0000000ac001') as d) s $$,
  $$ values (42195, 2, 9, 'tempo'::text, 10000) $$,
  'the share view carries goal, weeks and workouts by day offset'
);

-- 3. The author is named for a public profile.
select is(
  (select public_plan_share('aaaaaaaa-0000-0000-0000-0000000ac001') #>> '{author,name}'),
  'Creator Cat',
  'a public author is named'
);

-- 4–13. Nothing private reaches the anonymous view.
select ok(
  not (public_plan_share('aaaaaaaa-0000-0000-0000-0000000ac001')::text ~ k),
  'the share view never carries ' || k
)
from unnest(array[
  'vdot', 'current_5k', 'goal_time', 'target_pace', 'hr_', 'notes',
  'user_id', '2026-0', 'race_name', 'Club 10k'
]) as k;

-- 14. A non-public plan is not shared.
select is(
  public_plan_share('bbbbbbbb-0000-0000-0000-0000000ac001'),
  null,
  'a non-public plan returns null'
);

-- 15. A private author is unnamed for anon, and the plan still renders.
reset role;
update user_profiles set profile_private = true
 where id = '00000000-0000-0000-0000-0000000ac001';
set local role anon;
select results_eq(
  $$ select d ->> 'name', d ->> 'author'
     from (select public_plan_share('aaaaaaaa-0000-0000-0000-0000000ac001') as d) s $$,
  $$ values ('Spring marathon block'::text, null::text) $$,
  'a private author is unnamed, the plan still renders'
);
reset role;
update user_profiles set profile_private = false
 where id = '00000000-0000-0000-0000-0000000ac001';

-- 16–17. The gate closed: nothing.
update private.feature_flags set enabled = false where name = 'public_plan_share';
set local role anon;
select is(
  public_plan_share('aaaaaaaa-0000-0000-0000-0000000ac001'),
  null,
  'the share view is null while the gate is closed'
);
select is(public_plan_share_enabled(), false, 'the public gate reader reports closed');
reset role;
update private.feature_flags set enabled = true where name = 'public_plan_share';

-- ── The follower starts the plan ──
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000ac002","role":"authenticated"}';

select lives_ok(
  $$ select clone_public_plan('aaaaaaaa-0000-0000-0000-0000000ac001'::uuid, '2026-09-07'::date) $$,
  'the follower starts the public plan'
);

-- 19. The copy remembers its author, and the owner reads it back.
select results_eq(
  $$ select p.source_author_id,
            plan_started_from(p.id) #>> '{author,name}',
            (plan_started_from(p.id) ->> 'template_id')::uuid
     from training_plans p
     where p.user_id = '00000000-0000-0000-0000-0000000ac002'
       and p.parent_template_id = 'aaaaaaaa-0000-0000-0000-0000000ac001' $$,
  $$ values ('00000000-0000-0000-0000-0000000ac001'::uuid, 'Creator Cat'::text,
             'aaaaaaaa-0000-0000-0000-0000000ac001'::uuid) $$,
  'the copy carries source_author_id and plan_started_from names the creator'
);

-- 20. The owner cannot rewrite the attribution.
update training_plans set source_author_id = '00000000-0000-0000-0000-0000000ac003'
 where user_id = '00000000-0000-0000-0000-0000000ac002';
select is(
  (select source_author_id from training_plans
    where user_id = '00000000-0000-0000-0000-0000000ac002'
      and parent_template_id = 'aaaaaaaa-0000-0000-0000-0000000ac001'),
  '00000000-0000-0000-0000-0000000ac001'::uuid,
  'a client update cannot change source_author_id'
);

-- 21. Another account reads nothing about the follower's copy.
reset role;
create temp table follower_copy on commit drop as
  select id from training_plans
   where user_id = '00000000-0000-0000-0000-0000000ac002'
     and parent_template_id = 'aaaaaaaa-0000-0000-0000-0000000ac001';
grant select on follower_copy to authenticated;
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000ac003","role":"authenticated"}';
select is(
  (select plan_started_from(id) from follower_copy),
  null,
  'plan_started_from is null for someone else''s plan'
);

-- 22. A client insert cannot forge an attribution either.
insert into training_plans (
  id, user_id, name, goal_event, goal_distance_m,
  start_date, end_date, days_per_week, status, source_author_id
) values (
  'cccccccc-0000-0000-0000-0000000ac003',
  '00000000-0000-0000-0000-0000000ac003',
  'My own plan', 'distance_10k', 10000,
  '2026-09-07', '2026-10-25', 4, 'active',
  '00000000-0000-0000-0000-0000000ac001'
);
select is(
  (select source_author_id from training_plans
    where id = 'cccccccc-0000-0000-0000-0000000ac003'),
  null,
  'a client insert cannot set source_author_id'
);

select * from finish();

rollback;
