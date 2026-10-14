-- Pins migrations 20270803000001 + 20270803000002: a class event attaches a
-- gym routine (decisions § 1869).
--
--   1. an organiser attaches a template of the event's own club, and a public
--      template;
--   2. the trigger refuses (42501) a host's personal routine and another
--      club's template, and refuses moving an event that carries a club
--      template into a club whose members could not read it;
--   3. a plain member cannot change the attachment;
--   4. events_one_class_content refuses a class carrying both a session plan
--      and a gym routine (23514), and it is validated;
--   5. an attendee who is a club member reads the attached routine and its
--      planned sets; a stranger does not;
--   6. deleting the template detaches it (on delete set null).

begin;
select plan(16);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('99999999-0000-0000-0000-00000000b001', 'authenticated', 'authenticated', 'host@egr.local', '', now(), now()),
  ('99999999-0000-0000-0000-00000000b002', 'authenticated', 'authenticated', 'attendee@egr.local', '', now(), now()),
  ('99999999-0000-0000-0000-00000000b003', 'authenticated', 'authenticated', 'stranger@egr.local', '', now(), now());

-- Club X is the host's (enroll_club_owner enrolls the owner); the attendee is a
-- plain member. Club Y is the stranger's.
insert into clubs (id, owner_id, name, slug)
values
  ('cccccccc-0000-0000-0000-00000000b0c1', '99999999-0000-0000-0000-00000000b001', 'Strength Club', 'egr-strength-club'),
  ('cccccccc-0000-0000-0000-00000000b0c2', '99999999-0000-0000-0000-00000000b003', 'Other Club', 'egr-other-club');

insert into club_members (club_id, user_id, role, status)
values ('cccccccc-0000-0000-0000-00000000b0c1', '99999999-0000-0000-0000-00000000b002', 'member', 'active');

-- A club-X template, a public template, the host's personal routine, and a
-- club-Y template.
insert into gym_routines (id, author_id, club_id, is_public_template, title, exercise_count)
values
  ('61918001-0000-0000-0000-00000000b0a1', '99999999-0000-0000-0000-00000000b001', 'cccccccc-0000-0000-0000-00000000b0c1', false, 'Club Lower', 1),
  ('61918001-0000-0000-0000-00000000b0a2', '99999999-0000-0000-0000-00000000b003', null, true, 'Public Upper', 0),
  ('61918001-0000-0000-0000-00000000b0a3', '99999999-0000-0000-0000-00000000b001', null, false, 'My Private', 0),
  ('61918001-0000-0000-0000-00000000b0a4', '99999999-0000-0000-0000-00000000b003', 'cccccccc-0000-0000-0000-00000000b0c2', false, 'Other Club Routine', 0);

insert into gym_routine_exercises (id, routine_id, exercise_name, exercise_key, position)
values ('e8e80001-0000-0000-0000-00000000b0e1', '61918001-0000-0000-0000-00000000b0a1', 'Back Squat', 'back squat', 0);

insert into gym_routine_sets (routine_exercise_id, set_index, target_reps_min, target_weight_kg)
values ('e8e80001-0000-0000-0000-00000000b0e1', 0, 5, 60);

insert into session_plans (id, author_id, club_id, title, is_public)
values ('11111111-0000-0000-0000-00000000b0f1', '99999999-0000-0000-0000-00000000b001', 'cccccccc-0000-0000-0000-00000000b0c1', 'Club Flow', false);

insert into events (id, club_id, author_id, title, category, starts_at)
values
  ('eeeeeeee-0000-0000-0000-00000000b0e1', 'cccccccc-0000-0000-0000-00000000b0c1', '99999999-0000-0000-0000-00000000b001', 'Strength class', 'class', now() + interval '7 days'),
  ('eeeeeeee-0000-0000-0000-00000000b0e2', 'cccccccc-0000-0000-0000-00000000b0c1', '99999999-0000-0000-0000-00000000b001', 'HIIT class', 'class', now() + interval '8 days');

-- Under the stranger's own club too, so the move-event case below has a club
-- the host organises on both sides.
insert into club_members (club_id, user_id, role, status)
values ('cccccccc-0000-0000-0000-00000000b0c2', '99999999-0000-0000-0000-00000000b001', 'admin', 'active');

set local role authenticated;

-- ============================================================
-- 1. organiser attaches a club template and a public template
-- ============================================================
set local "request.jwt.claims" = '{"sub":"99999999-0000-0000-0000-00000000b001","role":"authenticated"}';
select lives_ok(
  $$ update events set gym_routine_id = '61918001-0000-0000-0000-00000000b0a1'
     where id = 'eeeeeeee-0000-0000-0000-00000000b0e1' $$,
  'an organiser attaches a template of the event''s own club');
select lives_ok(
  $$ update events set gym_routine_id = '61918001-0000-0000-0000-00000000b0a2'
     where id = 'eeeeeeee-0000-0000-0000-00000000b0e2' $$,
  'an organiser attaches a public template');
select is(
  (select gym_routine_id from events where id = 'eeeeeeee-0000-0000-0000-00000000b0e1'),
  '61918001-0000-0000-0000-00000000b0a1'::uuid,
  'the attached routine reads back through the events column grant');

-- ============================================================
-- 2. the trigger refuses a routine an attendee could not read
-- ============================================================
select throws_ok(
  $$ update events set gym_routine_id = '61918001-0000-0000-0000-00000000b0a3'
     where id = 'eeeeeeee-0000-0000-0000-00000000b0e2' $$,
  '42501',
  'a class can attach only a template of its own club or a public template',
  'the host''s personal routine is refused');
select throws_ok(
  $$ update events set gym_routine_id = '61918001-0000-0000-0000-00000000b0a4'
     where id = 'eeeeeeee-0000-0000-0000-00000000b0e2' $$,
  '42501',
  'a class can attach only a template of its own club or a public template',
  'another club''s template is refused');
select throws_ok(
  $$ update events set club_id = 'cccccccc-0000-0000-0000-00000000b0c2'
     where id = 'eeeeeeee-0000-0000-0000-00000000b0e1' $$,
  '42501',
  null,
  'moving a class that carries a club template into another club is refused');
select throws_ok(
  $$ insert into events (club_id, author_id, title, category, starts_at, gym_routine_id)
     values ('cccccccc-0000-0000-0000-00000000b0c1', '99999999-0000-0000-0000-00000000b001',
             'Insert with private', 'class', now() + interval '9 days',
             '61918001-0000-0000-0000-00000000b0a3') $$,
  '42501',
  'a class can attach only a template of its own club or a public template',
  'an insert carrying a personal routine is refused too');

-- ============================================================
-- 3. a plain member cannot change the attachment
-- ============================================================
-- The events UPDATE policy filters the member's write to zero rows; the
-- trigger is the second layer behind it.
set local "request.jwt.claims" = '{"sub":"99999999-0000-0000-0000-00000000b002","role":"authenticated"}';
select lives_ok(
  $$ update events set gym_routine_id = null
     where id = 'eeeeeeee-0000-0000-0000-00000000b0e1' $$,
  'a plain member''s detach runs but is RLS-filtered');
select is(
  (select gym_routine_id from events where id = 'eeeeeeee-0000-0000-0000-00000000b0e1'),
  '61918001-0000-0000-0000-00000000b0a1'::uuid,
  'the routine is still attached after the plain member''s write');

-- ============================================================
-- 4. at most one of session_plan_id / gym_routine_id
-- ============================================================
set local "request.jwt.claims" = '{"sub":"99999999-0000-0000-0000-00000000b001","role":"authenticated"}';
select throws_ok(
  $$ update events set session_plan_id = '11111111-0000-0000-0000-00000000b0f1'
     where id = 'eeeeeeee-0000-0000-0000-00000000b0e1' $$,
  '23514',
  null,
  'a class carrying a gym routine cannot also carry a session plan');
select is(
  (select convalidated from pg_constraint
    where conname = 'events_one_class_content' and conrelid = 'public.events'::regclass),
  true,
  'events_one_class_content is validated');

-- ============================================================
-- 5. the attendee reads the attached routine; a stranger does not
-- ============================================================
set local "request.jwt.claims" = '{"sub":"99999999-0000-0000-0000-00000000b002","role":"authenticated"}';
select is(
  (select title from gym_routines where id = '61918001-0000-0000-0000-00000000b0a1'),
  'Club Lower',
  'a club-member attendee reads the attached club template');
select is(
  (select count(*)::int from gym_routine_sets s
     join gym_routine_exercises e on e.id = s.routine_exercise_id
    where e.routine_id = '61918001-0000-0000-0000-00000000b0a1'),
  1,
  'the attendee reads the template''s planned sets, which the seed pre-fills from');
select is(
  (select title from public_gym_routines where id = '61918001-0000-0000-0000-00000000b0a2'),
  'Public Upper',
  'the attendee reads an attached public template through the library view');

set local "request.jwt.claims" = '{"sub":"99999999-0000-0000-0000-00000000b003","role":"authenticated"}';
select is(
  (select count(*)::int from gym_routines where id = '61918001-0000-0000-0000-00000000b0a1'),
  0,
  'a stranger to the club does not read its template');

-- ============================================================
-- 6. deleting the template detaches it
-- ============================================================
reset role;
delete from gym_routines where id = '61918001-0000-0000-0000-00000000b0a1';
select is(
  (select gym_routine_id from events where id = 'eeeeeeee-0000-0000-0000-00000000b0e1'),
  null,
  'deleting the template leaves the class standing with no routine');

select * from finish();
rollback;
