-- Pins migration 20270924000001: training_plans.race_listing_id links a plan
-- to the race it was built for. create_training_plan writes it through the
-- public listing view (an unknown or malformed id writes null and still
-- creates the plan), the owner may set it on their own plan, a template never
-- holds it, restart_training_plan does not carry it, and deleting the listing
-- nulls the link without touching the plan.

begin;
select plan(9);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('b5b5b5b5-0000-0000-0000-0000000f0001', 'authenticated', 'authenticated', 'trl-owner@trl.local', '', now(), now())
on conflict (id) do nothing;
insert into user_profiles (id, display_name)
values ('b5b5b5b5-0000-0000-0000-0000000f0001', 'TRL Owner')
on conflict (id) do nothing;

set local role service_role;
insert into race_listings (id, provider, provider_race_id, name, race_date, distance_m, is_verified)
values
  ('b6b6b6b6-0000-0000-0000-0000000f0001', 'runsignup', 'trl-1', 'Richmond Marathon', '2036-11-14', 42195, true),
  ('b6b6b6b6-0000-0000-0000-0000000f0002', 'runsignup', 'trl-2', 'Two Oceans', '2037-04-04', 56000, true);
reset role;

create temp table trl_ids (label text primary key, id uuid);
grant select, insert on trl_ids to authenticated;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"b5b5b5b5-0000-0000-0000-0000000f0001","role":"authenticated"}';

insert into trl_ids values ('linked', create_training_plan(
  '{"name":"Richmond build","goal_event":"distance_full","goal_distance_m":42195,"start_date":"2036-11-09","end_date":"2036-11-15","days_per_week":4,"race_listing_id":"b6b6b6b6-0000-0000-0000-0000000f0001"}',
  '[{"week_index":0,"phase":"race","target_volume_m":42195,"workouts":[{"scheduled_date":"2036-11-14","kind":"easy","target_distance_m":8000}]}]'));

insert into trl_ids values ('unknown', create_training_plan(
  '{"name":"Gone race","goal_event":"distance_10k","goal_distance_m":10000,"start_date":"2036-12-07","end_date":"2036-12-13","days_per_week":4,"race_listing_id":"b6b6b6b6-0000-0000-0000-0000000f00ff"}',
  '[{"week_index":0,"phase":"base","target_volume_m":5000,"workouts":[{"scheduled_date":"2036-12-09","kind":"easy","target_distance_m":5000}]}]'));

insert into trl_ids values ('malformed', create_training_plan(
  '{"name":"Not an id","goal_event":"distance_10k","goal_distance_m":10000,"start_date":"2037-01-04","end_date":"2037-01-10","days_per_week":4,"race_listing_id":"richmond"}',
  '[{"week_index":0,"phase":"base","target_volume_m":5000,"workouts":[{"scheduled_date":"2037-01-06","kind":"easy","target_distance_m":5000}]}]'));

-- The owner points their own plan at another race.
update training_plans
   set race_listing_id = 'b6b6b6b6-0000-0000-0000-0000000f0002'
 where id = (select id from trl_ids where label = 'unknown');
reset role;

-- 1. The create links the listing it was handed.
select is(
  (select race_listing_id from training_plans where id = (select id from trl_ids where label = 'linked')),
  'b6b6b6b6-0000-0000-0000-0000000f0001'::uuid,
  'create_training_plan stores the race listing the plan was built for'
);

-- 2. A malformed id creates the plan, unlinked.
select is(
  (select race_listing_id from training_plans where id = (select id from trl_ids where label = 'malformed')),
  null::uuid,
  'a race_listing_id that is not a uuid creates the plan with no link'
);

-- 3. An id naming no listing created the plan unlinked, and the owner then
-- linked it by hand.
select is(
  (select race_listing_id from training_plans where id = (select id from trl_ids where label = 'unknown')),
  'b6b6b6b6-0000-0000-0000-0000000f0002'::uuid,
  'the owner sets race_listing_id on their own plan'
);

-- 4. A plan published as a template holds no race link.
insert into training_plans (id, user_id, name, goal_event, goal_distance_m, start_date, end_date,
  days_per_week, status, is_template, is_public_template, race_listing_id)
values ('b7b7b7b7-0000-0000-0000-0000000f0001', 'b5b5b5b5-0000-0000-0000-0000000f0001', 'Library copy',
  'distance_full', 42195, '2036-11-09', '2036-11-15', 4, 'completed', true, true,
  'b6b6b6b6-0000-0000-0000-0000000f0001');
select is(
  (select race_listing_id from training_plans where id = 'b7b7b7b7-0000-0000-0000-0000000f0001'),
  null::uuid,
  'a template insert drops the race link'
);

-- 5. Flipping a linked plan to a template drops it too.
insert into training_plans (id, user_id, name, goal_event, goal_distance_m, start_date, end_date,
  days_per_week, status, race_listing_id)
values ('b7b7b7b7-0000-0000-0000-0000000f0002', 'b5b5b5b5-0000-0000-0000-0000000f0001', 'Flip me',
  'distance_full', 42195, '2035-11-04', '2035-11-10', 4, 'completed',
  'b6b6b6b6-0000-0000-0000-0000000f0001');
update training_plans set is_template = true where id = 'b7b7b7b7-0000-0000-0000-0000000f0002';
select is(
  (select race_listing_id from training_plans where id = 'b7b7b7b7-0000-0000-0000-0000000f0002'),
  null::uuid,
  'turning a linked plan into a template drops the race link'
);

-- 6. A restart copy starts unlinked: its race is always behind it.
insert into training_plans (id, user_id, name, goal_event, goal_distance_m, start_date, end_date,
  days_per_week, status, race_listing_id)
values ('b7b7b7b7-0000-0000-0000-0000000f0003', 'b5b5b5b5-0000-0000-0000-0000000f0001', 'Last year',
  'distance_full', 42195, current_date - 60, current_date - 40, 4, 'completed',
  'b6b6b6b6-0000-0000-0000-0000000f0001');
insert into plan_weeks (id, plan_id, week_index, phase, target_volume_m)
values ('b8b8b8b8-0000-0000-0000-0000000f0003', 'b7b7b7b7-0000-0000-0000-0000000f0003', 0, 'base', 10000);
insert into plan_workouts (week_id, scheduled_date, kind, target_distance_m)
values ('b8b8b8b8-0000-0000-0000-0000000f0003', current_date - 58, 'easy', 5000);

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"b5b5b5b5-0000-0000-0000-0000000f0001","role":"authenticated"}';
insert into trl_ids values ('restart', restart_training_plan(
  'b7b7b7b7-0000-0000-0000-0000000f0003', current_date + 400));
reset role;

select isnt(
  (select id from trl_ids where label = 'restart'),
  null::uuid,
  'the restart made a copy'
);
select is(
  (select race_listing_id from training_plans where id = (select id from trl_ids where label = 'restart')),
  null::uuid,
  'restart_training_plan does not carry the race link'
);

-- 7. Deleting the listing nulls the link and keeps the plan.
set local role service_role;
delete from race_listings where id = 'b6b6b6b6-0000-0000-0000-0000000f0001';
reset role;
select is(
  (select race_listing_id from training_plans where id = (select id from trl_ids where label = 'linked')),
  null::uuid,
  'deleting the listing sets the plan''s race link to null'
);
select is(
  (select count(*)::int from training_plans where id = (select id from trl_ids where label = 'linked')),
  1,
  'deleting the listing keeps the plan'
);

select * from finish();
rollback;
