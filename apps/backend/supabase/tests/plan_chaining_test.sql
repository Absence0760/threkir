-- Pins migration 20270830000001 (decisions § 2008): several active plans may
-- coexist when their date windows do not overlap; the writers that used to
-- complete every active plan now complete only overlapping ones; and
-- trim_training_plan ends a plan early.

begin;
select plan(14);

insert into auth.users (id, email, encrypted_password, email_confirmed_at, instance_id, aud, role)
values
  ('99999999-9999-9999-9999-99999c4a1001', 'chain-a@example.com', '', now(),
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('99999999-9999-9999-9999-99999c4a1002', 'chain-b@example.com', '', now(),
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated')
on conflict (id) do nothing;
insert into user_profiles (id, display_name, preferred_unit, subscription_tier)
values
  ('99999999-9999-9999-9999-99999c4a1001', 'Chain A', 'km', 'free'),
  ('99999999-9999-9999-9999-99999c4a1002', 'Chain B', 'km', 'free')
on conflict (id) do nothing;

-- A marathon block, then an ultra block starting the day after it ends.
insert into training_plans (id, user_id, name, goal_event, goal_distance_m,
                            start_date, end_date, days_per_week, status)
values ('aaaaaaaa-0000-0000-0000-0000000c4a01', '99999999-9999-9999-9999-99999c4a1001',
        'Marathon block', 'distance_full', 42195, '2030-01-07', '2030-03-03', 7, 'active');

select lives_ok(
  $$ insert into training_plans (id, user_id, name, goal_event, goal_distance_m,
                                 start_date, end_date, days_per_week, status)
     values ('aaaaaaaa-0000-0000-0000-0000000c4a02', '99999999-9999-9999-9999-99999c4a1001',
             'Ultra block', 'custom', 91000, '2030-03-04', '2030-06-30', 7, 'active') $$,
  'an active plan starting the day after another ends is accepted'
);

select throws_ok(
  $$ insert into training_plans (user_id, name, goal_event, goal_distance_m,
                                 start_date, end_date, days_per_week, status)
     values ('99999999-9999-9999-9999-99999c4a1001', 'Overlapping', 'distance_10k', 10000,
             '2030-03-03', '2030-04-01', 4, 'active') $$,
  '23P01', null,
  'an active plan sharing even one day with another active plan is refused'
);

select lives_ok(
  $$ insert into training_plans (user_id, name, goal_event, goal_distance_m,
                                 start_date, end_date, days_per_week, status)
     values ('99999999-9999-9999-9999-99999c4a1001', 'Old overlapping', 'distance_10k', 10000,
             '2030-02-01', '2030-04-01', 4, 'completed') $$,
  'a completed plan may overlap an active one'
);

select lives_ok(
  $$ insert into training_plans (user_id, name, goal_event, goal_distance_m,
                                 start_date, end_date, days_per_week, status)
     values ('99999999-9999-9999-9999-99999c4a1002', 'Other runner', 'distance_full', 42195,
             '2030-01-07', '2030-03-03', 4, 'active') $$,
  'another runner''s active plan over the same dates is independent'
);

select is(
  (select count(*)::int from training_plans
   where user_id = '99999999-9999-9999-9999-99999c4a1001' and status = 'active'),
  2,
  'the runner holds two active plans'
);

-- clone_plan_template completes only the plans the clone overlaps.
insert into clubs (id, slug, name, is_public, join_policy, owner_id)
values ('99999999-9999-9999-9999-99999c4a1c01', 'chain-club', 'Chain Club', true, 'open',
        '99999999-9999-9999-9999-99999c4a1001')
on conflict (id) do nothing;
insert into club_members (club_id, user_id, role, status, joined_at)
values ('99999999-9999-9999-9999-99999c4a1c01', '99999999-9999-9999-9999-99999c4a1001',
        'member', 'active', now())
on conflict (club_id, user_id) do nothing;
insert into training_plans (id, user_id, club_id, name, goal_event, goal_distance_m,
                            start_date, end_date, days_per_week, status, is_template)
values ('aaaaaaaa-0000-0000-0000-0000000c4a03', '99999999-9999-9999-9999-99999c4a1001',
        '99999999-9999-9999-9999-99999c4a1c01', 'Four-week template', 'distance_10k', 10000,
        '2030-01-01', '2030-01-28', 4, 'completed', true);

set local request.jwt.claims = '{"sub":"99999999-9999-9999-9999-99999c4a1001","role":"authenticated"}';
set local role = 'authenticated';
select lives_ok(
  $$ select clone_plan_template('aaaaaaaa-0000-0000-0000-0000000c4a03', '2030-07-01') $$,
  'cloning a template into the free dates after both blocks succeeds'
);
reset role;

select is(
  (select count(*)::int from training_plans
   where user_id = '99999999-9999-9999-9999-99999c4a1001' and status = 'active'),
  3,
  'a clone into free dates leaves both earlier blocks active'
);

set local role = 'authenticated';
select lives_ok(
  $$ select clone_plan_template('aaaaaaaa-0000-0000-0000-0000000c4a03', '2030-03-01') $$,
  'cloning over the marathon/ultra boundary succeeds'
);
reset role;

select is(
  (select array_agg(row(name, status)::text order by name) from training_plans
   where user_id = '99999999-9999-9999-9999-99999c4a1001' and status in ('completed', 'abandoned')
     and not is_template),
  array[row('Marathon block', 'abandoned')::text, row('Old overlapping', 'completed')::text,
        row('Ultra block', 'abandoned')::text],
  'a clone abandons exactly the active plans its window overlaps (20270903000001)'
);

-- trim_training_plan ends a plan early.
insert into training_plans (id, user_id, name, goal_event, goal_distance_m,
                            start_date, end_date, days_per_week, status)
values ('aaaaaaaa-0000-0000-0000-0000000c4a04', '99999999-9999-9999-9999-99999c4a1001',
        'Trim me', 'distance_half', 21097, '2031-01-06', '2031-01-26', 4, 'active');
insert into plan_weeks (id, plan_id, week_index, phase, target_volume_m)
values
  ('aaaaaaaa-0000-0000-0000-0000000c4b01', 'aaaaaaaa-0000-0000-0000-0000000c4a04', 0, 'base', 20000),
  ('aaaaaaaa-0000-0000-0000-0000000c4b02', 'aaaaaaaa-0000-0000-0000-0000000c4a04', 1, 'build', 20000),
  ('aaaaaaaa-0000-0000-0000-0000000c4b03', 'aaaaaaaa-0000-0000-0000-0000000c4a04', 2, 'taper', 20000);
insert into plan_workouts (week_id, scheduled_date, kind, target_distance_m)
values
  ('aaaaaaaa-0000-0000-0000-0000000c4b01', '2031-01-08', 'easy', 8000),
  ('aaaaaaaa-0000-0000-0000-0000000c4b02', '2031-01-13', 'easy', 8000),
  ('aaaaaaaa-0000-0000-0000-0000000c4b02', '2031-01-18', 'long', 16000),
  ('aaaaaaaa-0000-0000-0000-0000000c4b03', '2031-01-25', 'race', 21097);

set local role = 'authenticated';
select throws_ok(
  $$ select trim_training_plan('aaaaaaaa-0000-0000-0000-0000000c4a04', '2031-01-05') $$,
  'P0001', null,
  'a plan cannot be trimmed to end before it starts'
);
select lives_ok(
  $$ select trim_training_plan('aaaaaaaa-0000-0000-0000-0000000c4a04', '2031-01-15') $$,
  'the owner trims the plan to end mid-week-two'
);
reset role;

select is(
  (select end_date from training_plans where id = 'aaaaaaaa-0000-0000-0000-0000000c4a04'),
  '2031-01-15'::date,
  'the trimmed plan ends on the new date'
);
select is(
  (select array_agg(wo.scheduled_date order by wo.scheduled_date)
   from plan_workouts wo join plan_weeks w on w.id = wo.week_id
   where w.plan_id = 'aaaaaaaa-0000-0000-0000-0000000c4a04'),
  array['2031-01-08'::date, '2031-01-13'::date],
  'workouts after the new end date are deleted, earlier ones kept'
);

set local request.jwt.claims = '{"sub":"99999999-9999-9999-9999-99999c4a1002","role":"authenticated"}';
set local role = 'authenticated';
select throws_ok(
  $$ select trim_training_plan('aaaaaaaa-0000-0000-0000-0000000c4a04', '2031-01-10') $$,
  'P0001', null,
  'another runner cannot trim the plan'
);
reset role;

select * from finish();
rollback;
