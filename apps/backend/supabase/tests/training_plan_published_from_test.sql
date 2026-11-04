-- Pins migration 20271105120001: a public-library copy links the plan it was
-- published from. The owner writes the link on their own template, a cloner's
-- plan never carries it, and deleting the source plan nulls the link without
-- deleting the library copy.

begin;
select plan(4);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('c1c1c1c1-0000-0000-0000-0000000f0001', 'authenticated', 'authenticated', 'tpf-owner@tpf.local', '', now(), now()),
  ('c1c1c1c1-0000-0000-0000-0000000f0002', 'authenticated', 'authenticated', 'tpf-cloner@tpf.local', '', now(), now())
on conflict (id) do nothing;
insert into user_profiles (id, display_name)
values
  ('c1c1c1c1-0000-0000-0000-0000000f0001', 'TPF Owner'),
  ('c1c1c1c1-0000-0000-0000-0000000f0002', 'TPF Cloner')
on conflict (id) do nothing;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c1c1c1c1-0000-0000-0000-0000000f0001","role":"authenticated"}';

insert into training_plans (id, user_id, name, goal_event, goal_distance_m, start_date, end_date,
  days_per_week, status, is_template, is_public_template)
values ('c2c2c2c2-0000-0000-0000-0000000f0001', 'c1c1c1c1-0000-0000-0000-0000000f0001', 'Renamed since',
  'distance_10k', 10000, '2036-03-01', '2036-03-07', 4, 'completed', false, false);

insert into training_plans (id, user_id, name, goal_event, goal_distance_m, start_date, end_date,
  days_per_week, status, is_template, is_public_template, published_from_plan_id)
values ('c2c2c2c2-0000-0000-0000-0000000f0002', 'c1c1c1c1-0000-0000-0000-0000000f0001', 'Published name',
  'distance_10k', 10000, '2036-03-01', '2036-03-07', 4, 'completed', true, true,
  'c2c2c2c2-0000-0000-0000-0000000f0001');
insert into plan_weeks (id, plan_id, week_index, phase, target_volume_m)
values ('c3c3c3c3-0000-0000-0000-0000000f0001', 'c2c2c2c2-0000-0000-0000-0000000f0002', 0, 'base', 5000);
reset role;

-- 1. The owner's template keeps the link it was written with.
select is(
  (select published_from_plan_id from training_plans where id = 'c2c2c2c2-0000-0000-0000-0000000f0002'),
  'c2c2c2c2-0000-0000-0000-0000000f0001'::uuid,
  'a public template stores the plan it was published from'
);

-- 2. A cloner's copy starts unlinked: it is not the publisher's copy.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c1c1c1c1-0000-0000-0000-0000000f0002","role":"authenticated"}';
create temp table tpf_clone as
  select clone_public_plan('c2c2c2c2-0000-0000-0000-0000000f0002', '2036-05-03', 'replace') as id;
reset role;
select is(
  (select published_from_plan_id from training_plans where id = (select id from tpf_clone)),
  null::uuid,
  'clone_public_plan does not carry the publisher''s source link'
);

-- 3 + 4. Deleting the source plan nulls the link and keeps the library copy.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c1c1c1c1-0000-0000-0000-0000000f0001","role":"authenticated"}';
delete from training_plans where id = 'c2c2c2c2-0000-0000-0000-0000000f0001';
reset role;
select is(
  (select count(*)::int from training_plans where id = 'c2c2c2c2-0000-0000-0000-0000000f0002'),
  1,
  'deleting the source plan keeps its library copy'
);
select is(
  (select published_from_plan_id from training_plans where id = 'c2c2c2c2-0000-0000-0000-0000000f0002'),
  null::uuid,
  'deleting the source plan nulls the copy''s link'
);

select * from finish();
rollback;
