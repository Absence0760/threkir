-- Pins migration 20270830000002 (decisions § 2009): a race workout carries a
-- name and an A/B/C priority, only race workouts may, and the clone RPCs
-- carry both fields into the copy.

begin;
select plan(7);

insert into auth.users (id, email, encrypted_password, email_confirmed_at, instance_id, aud, role)
values ('99999999-9999-9999-9999-99999c4a2001', 'race-fields@example.com', '', now(),
        '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated')
on conflict (id) do nothing;
insert into user_profiles (id, display_name, preferred_unit, subscription_tier)
values ('99999999-9999-9999-9999-99999c4a2001', 'Race Fields', 'km', 'free')
on conflict (id) do nothing;
insert into clubs (id, slug, name, is_public, join_policy, owner_id)
values ('99999999-9999-9999-9999-99999c4a2c01', 'race-fields-club', 'Race Fields Club', true,
        'open', '99999999-9999-9999-9999-99999c4a2001')
on conflict (id) do nothing;
insert into club_members (club_id, user_id, role, status, joined_at)
values ('99999999-9999-9999-9999-99999c4a2c01', '99999999-9999-9999-9999-99999c4a2001',
        'member', 'active', now())
on conflict (club_id, user_id) do nothing;

insert into training_plans (id, user_id, club_id, name, goal_event, goal_distance_m,
                            start_date, end_date, days_per_week, status, is_template)
values ('aaaaaaaa-0000-0000-0000-0000000c4c01', '99999999-9999-9999-9999-99999c4a2001',
        '99999999-9999-9999-9999-99999c4a2c01', 'Ultra season', 'custom', 91000,
        '2030-01-07', '2030-01-20', 7, 'completed', true);
insert into plan_weeks (id, plan_id, week_index, phase, target_volume_m)
values ('aaaaaaaa-0000-0000-0000-0000000c4d01', 'aaaaaaaa-0000-0000-0000-0000000c4c01', 0, 'base', 60000);

select lives_ok(
  $$ insert into plan_workouts (week_id, scheduled_date, kind, target_distance_m,
                                target_duration_seconds, race_name, race_priority)
     values ('aaaaaaaa-0000-0000-0000-0000000c4d01', '2030-01-12', 'race', 56000,
             23400, 'Two Oceans Ultra', 'B') $$,
  'a race workout takes a name and a priority'
);

select throws_ok(
  $$ insert into plan_workouts (week_id, scheduled_date, kind, race_priority)
     values ('aaaaaaaa-0000-0000-0000-0000000c4d01', '2030-01-13', 'race', 'D') $$,
  '23514', null,
  'a priority outside A/B/C is refused'
);

select throws_ok(
  $$ insert into plan_workouts (week_id, scheduled_date, kind, target_distance_m, race_name)
     values ('aaaaaaaa-0000-0000-0000-0000000c4d01', '2030-01-14', 'long', 32000, 'Not a race') $$,
  '23514', null,
  'only a race workout may carry race fields'
);

select throws_ok(
  $$ insert into plan_workouts (week_id, scheduled_date, kind, race_name)
     values ('aaaaaaaa-0000-0000-0000-0000000c4d01', '2030-01-15', 'race', '   ') $$,
  '23514', null,
  'a blank race name is refused'
);

select lives_ok(
  $$ insert into plan_workouts (week_id, scheduled_date, kind, target_distance_m)
     values ('aaaaaaaa-0000-0000-0000-0000000c4d01', '2030-01-16', 'race', 10000) $$,
  'a race workout without a name or priority is still accepted'
);

set local request.jwt.claims = '{"sub":"99999999-9999-9999-9999-99999c4a2001","role":"authenticated"}';
set local role = 'authenticated';
select lives_ok(
  $$ select clone_plan_template('aaaaaaaa-0000-0000-0000-0000000c4c01', '2030-03-04') $$,
  'the template clones'
);
reset role;

select is(
  (select row(wo.race_name, wo.race_priority, wo.target_duration_seconds)::text
   from plan_workouts wo
   join plan_weeks w on w.id = wo.week_id
   join training_plans p on p.id = w.plan_id
   where p.user_id = '99999999-9999-9999-9999-99999c4a2001'
     and not p.is_template and wo.scheduled_date = '2030-03-09'),
  row('Two Oceans Ultra'::text, 'B'::text, 23400)::text,
  'the clone carries the race name, priority and goal time'
);

select * from finish();
rollback;
