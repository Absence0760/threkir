-- Pins migration 20270815000001 (nutrition programming P1: nutrition_plans +
-- nutrition_plan_assignments). The contract:
--
--   1. A plan is written by its author only, and read by its author or by a
--      client an assignment links to it, active or ended (the P3 branch,
--      through the private.can_read_nutrition_plan definer helper; an ended
--      assignment still governs its days, so the read survives the end,
--      migration 20270819000041). A stranger sees and writes nothing, and an
--      ended client gains no write.
--   2. Self-assignment is a direct insert, and only of a plan the caller
--      authors: a known plan id must not be enough to mint the assignment the
--      client read branch would then honour.
--   3. The CHECKs hold: the goal-phase / progression / status vocabularies, the
--      calorie sanity floor, and end_date >= start_date.
--   4. Erasure: everything cascades from auth.users; a deleted assigner leaves
--      the client's assignment intact but unattributed; deleting a plan never
--      touches food_log.
begin;
select plan(33);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('99999999-0000-0000-0000-0000000e0a01', 'authenticated', 'authenticated', 'author@np.local', '', now(), now()),
  ('99999999-0000-0000-0000-0000000e0a02', 'authenticated', 'authenticated', 'stranger@np.local', '', now(), now()),
  ('99999999-0000-0000-0000-0000000e0a03', 'authenticated', 'authenticated', 'client@np.local', '', now(), now()),
  ('99999999-0000-0000-0000-0000000e0a04', 'authenticated', 'authenticated', 'assigner@np.local', '', now(), now());

insert into nutrition_plans (id, author_id, title, target_calories, target_protein_g)
values
  ('99999999-0000-0000-0000-0000000e0b01', '99999999-0000-0000-0000-0000000e0a01', 'Marathon build', 2600, 150),
  ('99999999-0000-0000-0000-0000000e0b02', '99999999-0000-0000-0000-0000000e0a03', 'Client own plan', 2100, null);

insert into nutrition_plan_assignments (id, plan_id, client_id, assigned_by, start_date, status)
values
  ('99999999-0000-0000-0000-0000000e0c01', '99999999-0000-0000-0000-0000000e0b01',
   '99999999-0000-0000-0000-0000000e0a03', '99999999-0000-0000-0000-0000000e0a01', current_date - 3, 'active'),
  ('99999999-0000-0000-0000-0000000e0c02', '99999999-0000-0000-0000-0000000e0b02',
   '99999999-0000-0000-0000-0000000e0a03', '99999999-0000-0000-0000-0000000e0a04', current_date - 10, 'ended');

insert into food_log (id, user_id, item_name, calories, started_at)
values ('99999999-0000-0000-0000-0000000e0d01', '99999999-0000-0000-0000-0000000e0a01', 'Oats', 300, now());

set local role authenticated;

-- ============================================================
-- Author
-- ============================================================
set local "request.jwt.claims" = '{"sub":"99999999-0000-0000-0000-0000000e0a01","role":"authenticated"}';

select is(
  (select count(*)::int from nutrition_plans where id = '99999999-0000-0000-0000-0000000e0b01'),
  1, 'the author reads their own plan');

select lives_ok(
  $$ insert into nutrition_plans (id, author_id, title, target_calories)
     values ('99999999-0000-0000-0000-0000000e0b03', '99999999-0000-0000-0000-0000000e0a01', 'Cut', 1900) $$,
  'the author inserts their own plan');

select lives_ok(
  $$ insert into nutrition_plan_assignments (id, plan_id, client_id, assigned_by, start_date)
     values ('99999999-0000-0000-0000-0000000e0c03', '99999999-0000-0000-0000-0000000e0b03',
             '99999999-0000-0000-0000-0000000e0a01', '99999999-0000-0000-0000-0000000e0a01', current_date) $$,
  'the author self-assigns their own plan');

select is(
  (select count(*)::int from nutrition_plan_assignments where id = '99999999-0000-0000-0000-0000000e0c03'),
  1, 'and reads the self-assignment back');

select lives_ok(
  $$ update nutrition_plan_assignments set status = 'ended', end_date = current_date
      where id = '99999999-0000-0000-0000-0000000e0c03' $$,
  'the author ends their own self-assignment');

select is(
  (select status from nutrition_plan_assignments where id = '99999999-0000-0000-0000-0000000e0c03'),
  'ended', 'and the end is stored');

-- ============================================================
-- Stranger
-- ============================================================
set local "request.jwt.claims" = '{"sub":"99999999-0000-0000-0000-0000000e0a02","role":"authenticated"}';

select is(
  (select count(*)::int from nutrition_plans where author_id = '99999999-0000-0000-0000-0000000e0a01'),
  0, 'a stranger cannot read another user''s plans');

select is(
  (select count(*)::int from nutrition_plan_assignments where client_id = '99999999-0000-0000-0000-0000000e0a03'),
  0, 'a stranger cannot read another user''s assignments');

select throws_ok(
  $$ insert into nutrition_plans (author_id, title, target_calories)
     values ('99999999-0000-0000-0000-0000000e0a01', 'Forged', 2000) $$,
  '42501', null,
  'a stranger cannot insert a plan authored by someone else');

select throws_ok(
  $$ insert into nutrition_plan_assignments (plan_id, client_id, assigned_by, start_date)
     values ('99999999-0000-0000-0000-0000000e0b01', '99999999-0000-0000-0000-0000000e0a02',
             '99999999-0000-0000-0000-0000000e0a02', current_date) $$,
  '42501', null,
  'a stranger cannot self-assign a plan they do not author, so a known id opens nothing');

select throws_ok(
  $$ insert into nutrition_plan_assignments (plan_id, client_id, assigned_by, start_date)
     values ('99999999-0000-0000-0000-0000000e0b01', '99999999-0000-0000-0000-0000000e0a03',
             '99999999-0000-0000-0000-0000000e0a01', current_date) $$,
  '42501', null,
  'nobody can write an assignment for another client outside the RPC');

select lives_ok(
  $$ update nutrition_plans set title = 'Hijacked' where id = '99999999-0000-0000-0000-0000000e0b01' $$,
  'a stranger''s update runs but is RLS-filtered');

-- ============================================================
-- Client: the active-assignment read branch
-- ============================================================
set local "request.jwt.claims" = '{"sub":"99999999-0000-0000-0000-0000000e0a03","role":"authenticated"}';

select lives_ok(
  $$ update nutrition_plans set title = 'Edited by client' where id = '99999999-0000-0000-0000-0000000e0b01' $$,
  'a client''s edit of an assigned plan runs but is RLS-filtered');

select is(
  (select title from nutrition_plans where id = '99999999-0000-0000-0000-0000000e0b01'),
  'Marathon build',
  'a client reads a plan an active assignment links them to, and neither edit landed');

select is(
  (select count(*)::int from nutrition_plan_assignments
    where client_id = '99999999-0000-0000-0000-0000000e0a03'),
  2, 'the client reads every assignment that names them');

select lives_ok(
  $$ insert into nutrition_plan_assignments (id, plan_id, client_id, assigned_by, start_date)
     values ('99999999-0000-0000-0000-0000000e0c04', '99999999-0000-0000-0000-0000000e0b02',
             '99999999-0000-0000-0000-0000000e0a03', '99999999-0000-0000-0000-0000000e0a03', current_date) $$,
  'the client self-assigns their own plan');

select throws_ok(
  $$ update nutrition_plan_assignments set plan_id = '99999999-0000-0000-0000-0000000e0b01'
      where id = '99999999-0000-0000-0000-0000000e0c04' $$,
  '42501', null,
  'the client cannot repoint an assignment they hold at a plan they do not author');

-- ============================================================
-- CHECKs (as the client, on their own plan)
-- ============================================================
select throws_ok(
  $$ update nutrition_plans set goal_phase = 'bulk' where id = '99999999-0000-0000-0000-0000000e0b02' $$,
  '23514', null, 'goal_phase rejects a value outside the vocabulary');

select throws_ok(
  $$ update nutrition_plans set progression = 'auto' where id = '99999999-0000-0000-0000-0000000e0b02' $$,
  '23514', null, 'progression rejects a value outside the vocabulary');

select throws_ok(
  $$ update nutrition_plans set target_calories = 999 where id = '99999999-0000-0000-0000-0000000e0b02' $$,
  '23514', null, 'target_calories rejects a value below the 1000 sanity floor');

select throws_ok(
  $$ insert into nutrition_plan_assignments (plan_id, client_id, assigned_by, start_date, end_date)
     values ('99999999-0000-0000-0000-0000000e0b02', '99999999-0000-0000-0000-0000000e0a03',
             '99999999-0000-0000-0000-0000000e0a03', current_date, current_date - 1) $$,
  '23514', null, 'an assignment cannot end before it starts');

select throws_ok(
  $$ insert into nutrition_plan_assignments (plan_id, client_id, assigned_by, start_date, status)
     values ('99999999-0000-0000-0000-0000000e0b02', '99999999-0000-0000-0000-0000000e0a03',
             '99999999-0000-0000-0000-0000000e0a03', current_date, 'paused') $$,
  '23514', null, 'status rejects a value outside the vocabulary');

-- ============================================================
-- The helper, and the ended-assignment edge of the read branch
-- ============================================================
reset role;

select ok(
  not has_function_privilege('anon', 'private.can_read_nutrition_plan(uuid, uuid)', 'execute'),
  'anon cannot execute the plan-read helper');

update nutrition_plan_assignments set status = 'ended', end_date = current_date
 where id = '99999999-0000-0000-0000-0000000e0c01';

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"99999999-0000-0000-0000-0000000e0a03","role":"authenticated"}';

select is(
  (select title from nutrition_plans where id = '99999999-0000-0000-0000-0000000e0b01'),
  'Marathon build',
  'a client still reads a third-party plan once its assignment has ended, since it governs those days');

select lives_ok(
  $$ update nutrition_plans set title = 'Edited after the end' where id = '99999999-0000-0000-0000-0000000e0b01' $$,
  'an ended client''s edit of the plan runs but is RLS-filtered');

select lives_ok(
  $$ update nutrition_plan_assignments set status = 'active', end_date = null
      where id = '99999999-0000-0000-0000-0000000e0c01' $$,
  'an ended client''s attempt to reopen a third-party assignment runs but is RLS-filtered');

select throws_ok(
  $$ insert into nutrition_plan_assignments (plan_id, client_id, assigned_by, start_date)
     values ('99999999-0000-0000-0000-0000000e0b01', '99999999-0000-0000-0000-0000000e0a03',
             '99999999-0000-0000-0000-0000000e0a03', current_date + 1) $$,
  '42501', null,
  'an ended client cannot self-assign the third-party plan again, so reading it opens no write');

reset role;

select is(
  (select title || ' / ' || status || ' / ' || coalesce(end_date::text, 'open')
     from nutrition_plans p join nutrition_plan_assignments a on a.plan_id = p.id
    where a.id = '99999999-0000-0000-0000-0000000e0c01'),
  'Marathon build / ended / ' || current_date::text,
  'and neither the plan edit nor the reopen landed');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"99999999-0000-0000-0000-0000000e0a02","role":"authenticated"}';

select is(
  (select count(*)::int from nutrition_plans where id = '99999999-0000-0000-0000-0000000e0b01'),
  0, 'a stranger still cannot read the plan an ended assignment keeps open to its client');

-- ============================================================
-- Erasure
-- ============================================================
reset role;

delete from auth.users where id = '99999999-0000-0000-0000-0000000e0a04';
select is(
  (select count(*)::int from nutrition_plan_assignments
    where id = '99999999-0000-0000-0000-0000000e0c02' and assigned_by is null),
  1, 'a deleted assigner leaves the client''s assignment intact and unattributed');

delete from nutrition_plans where id = '99999999-0000-0000-0000-0000000e0b01';
select is(
  (select count(*)::int from nutrition_plan_assignments where plan_id = '99999999-0000-0000-0000-0000000e0b01'),
  0, 'deleting a plan cascades its assignments');
select is(
  (select count(*)::int from food_log where id = '99999999-0000-0000-0000-0000000e0d01'),
  1, 'and leaves the author''s food_log untouched');

delete from auth.users where id = '99999999-0000-0000-0000-0000000e0a03';
select is(
  (select count(*)::int from nutrition_plans p
     full join nutrition_plan_assignments a on a.plan_id = p.id
    where p.author_id = '99999999-0000-0000-0000-0000000e0a03'
       or a.client_id = '99999999-0000-0000-0000-0000000e0a03'),
  0, 'deleting the auth user cascade-removes their plans and assignments');

select * from finish();
rollback;
