-- Height, gender and the body_metrics weight series need health-data consent
-- (migration 20271231002547_health_values_need_consent.sql; decisions § 2547).
--
-- Pins:
--   * a runner without health_data_consent_at cannot store a height or a
--     gender on user_profiles, on insert or update, by their own write or any
--     other (42501);
--   * the same runner can clear both, and save every other profile column;
--   * one write that sets the stamp and a value together passes;
--   * a profile write that leaves an existing value as it was is not refused,
--     which is what lets a withdrawal null the stamp before the transition
--     trigger clears the values;
--   * body_metrics refuses an insert or update for a runner without consent,
--     and never refuses a delete;
--   * private.erase_values_held_without_consent() clears height, gender, the
--     weight series and plan heart-rate targets of every runner without
--     consent, including one with no profile row, and leaves a consenting
--     runner's values alone.

begin;

select plan(23);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeee2547', 'authenticated', 'authenticated', 'hv-none@test.local', '', now(), now()),
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeee2548', 'authenticated', 'authenticated', 'hv-yes@test.local', '', now(), now()),
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeee2549', 'authenticated', 'authenticated', 'hv-noprofile@test.local', '', now(), now());

insert into user_profiles (id, display_name, preferred_unit, age_confirmed_at, health_data_consent_at)
values ('eeeeeeee-eeee-eeee-eeee-eeeeeeee2547', 'HV None', 'km', now(), null),
       ('eeeeeeee-eeee-eeee-eeee-eeeeeeee2548', 'HV Yes', 'km', now(), '2026-01-01T00:00:00Z');

-- 1-3. Any writer, without consent: height and gender are refused on insert.
select throws_ok(
  $$ insert into user_profiles (id, height_cm)
     values ('eeeeeeee-eeee-eeee-eeee-eeeeeeee2549', 170) $$,
  '42501', 'user_profiles: height_cm needs health-data consent',
  'a height on a new profile without consent is refused'
);
select throws_ok(
  $$ insert into user_profiles (id, gender)
     values ('eeeeeeee-eeee-eeee-eeee-eeeeeeee2549', 'female') $$,
  '42501', 'user_profiles: gender needs health-data consent',
  'a gender on a new profile without consent is refused'
);
select lives_ok(
  $$ insert into user_profiles (id, display_name)
     values ('eeeeeeee-eeee-eeee-eeee-eeeeeeee2549', 'HV No Values') $$,
  'a new profile without either value is not refused'
);
delete from user_profiles where id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeee2549';

-- 4-8. The owner's own update, without consent.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"eeeeeeee-eeee-eeee-eeee-eeeeeeee2547","role":"authenticated"}';
select throws_ok(
  $$ update user_profiles set height_cm = 180
      where id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeee2547' $$,
  '42501', 'user_profiles: height_cm needs health-data consent',
  'the owner cannot store a height without consent'
);
select throws_ok(
  $$ update user_profiles set gender = 'male'
      where id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeee2547' $$,
  '42501', 'user_profiles: gender needs health-data consent',
  'the owner cannot store a gender without consent'
);
select lives_ok(
  $$ update user_profiles set height_cm = null, gender = null, date_of_birth = '1990-01-01'
      where id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeee2547' $$,
  'clearing both values, and writing the age record, is never refused'
);
select lives_ok(
  $$ update user_profiles set display_name = 'HV None Renamed'
      where id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeee2547' $$,
  'a runner without consent can still save the other profile columns'
);

-- body_metrics, without consent: refused.
select throws_ok(
  $$ insert into body_metrics (user_id, weight_kg)
     values ('eeeeeeee-eeee-eeee-eeee-eeeeeeee2547', 70) $$,
  '42501', 'body_metrics: weight needs health-data consent',
  'the owner cannot record a weight without consent'
);
reset role;

-- 9-11. With consent: stored and changed.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"eeeeeeee-eeee-eeee-eeee-eeeeeeee2548","role":"authenticated"}';
select lives_ok(
  $$ update user_profiles set height_cm = 175, gender = 'female'
      where id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeee2548' $$,
  'a runner with consent can store a height and a gender'
);
select lives_ok(
  $$ insert into body_metrics (id, user_id, weight_kg)
     values ('eeeeeeee-0000-0000-0000-00000000b547', 'eeeeeeee-eeee-eeee-eeee-eeeeeeee2548', 64) $$,
  'a runner with consent can record a weight'
);
select lives_ok(
  $$ update body_metrics set weight_kg = 63.5
      where id = 'eeeeeeee-0000-0000-0000-00000000b547' $$,
  'a runner with consent can correct a weight'
);
reset role;

-- 12-15. With the stamp nulled while the values stand (the triggers are held
-- off here so the state can be built), a write that leaves them as they were
-- is not refused; a changed value, and any body_metrics write, are.
alter table user_profiles disable trigger user_profiles_health_consent_transition;
update user_profiles set health_data_consent_at = null
 where id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeee2548';
alter table user_profiles enable trigger user_profiles_health_consent_transition;
select lives_ok(
  $$ update user_profiles set height_cm = height_cm, gender = gender, display_name = 'HV Kept'
      where id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeee2548' $$,
  'a write that leaves a stored height and gender as they were is not refused'
);
select throws_ok(
  $$ update user_profiles set height_cm = 176
      where id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeee2548' $$,
  '42501', 'user_profiles: height_cm needs health-data consent',
  'changing a stored height without consent is refused'
);
select throws_ok(
  $$ update body_metrics set weight_kg = 62
      where id = 'eeeeeeee-0000-0000-0000-00000000b547' $$,
  '42501', 'body_metrics: weight needs health-data consent',
  'correcting a weight without consent is refused'
);
select lives_ok(
  $$ delete from body_metrics where id = 'eeeeeeee-0000-0000-0000-00000000b547' $$,
  'deleting a weight is never refused'
);

-- 16. One write that sets the stamp and a value together passes (the service
-- role: lock_consent_columns refuses the stamp from a client).
set local "request.jwt.claims" = '{"role":"service_role"}';
select lives_ok(
  $$ update user_profiles set health_data_consent_at = now(), height_cm = 177
      where id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeee2548' $$,
  'setting the stamp and a height in one write passes'
);

-- 17. The withdrawal RPC nulls the stamp while the values stand, then clears
-- them; the new trigger must not refuse its first step.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"eeeeeeee-eeee-eeee-eeee-eeeeeeee2548","role":"authenticated"}';
select lives_ok(
  $$ select withdraw_health_data_consent() $$,
  'withdraw_health_data_consent() is not refused by the value gate'
);
reset role;

-- 18-23. The clean-up. Values held without consent are built with the gates
-- held off, as the pre-gate rows were written; the consenting runner's are
-- written through the gates.
update user_profiles set health_data_consent_at = now(), height_cm = 181, gender = 'male'
 where id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeee2548';
insert into body_metrics (user_id, weight_kg) values ('eeeeeeee-eeee-eeee-eeee-eeeeeeee2548', 80);

alter table user_profiles disable trigger user_profiles_check_health_values;
alter table body_metrics disable trigger body_metrics_check_health_consent;
alter table body_metrics disable trigger body_metrics_require_consent;
update user_profiles set height_cm = 160, gender = 'female'
 where id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeee2547';
insert into body_metrics (user_id, weight_kg)
values ('eeeeeeee-eeee-eeee-eeee-eeeeeeee2547', 55),
       ('eeeeeeee-eeee-eeee-eeee-eeeeeeee2549', 90);
alter table user_profiles enable trigger user_profiles_check_health_values;
alter table body_metrics enable trigger body_metrics_check_health_consent;
alter table body_metrics enable trigger body_metrics_require_consent;

insert into training_plans (id, user_id, name, goal_event, goal_distance_m, start_date, end_date, days_per_week, status)
values ('eeeeeeee-0000-0000-0000-0000000a2547', 'eeeeeeee-eeee-eeee-eeee-eeeeeeee2547', 'HV None plan', 'distance_10k', 10000,
        current_date, current_date + 48, 4, 'active'),
       ('eeeeeeee-0000-0000-0000-0000000a2548', 'eeeeeeee-eeee-eeee-eeee-eeeeeeee2548', 'HV Yes plan', 'distance_10k', 10000,
        current_date, current_date + 48, 4, 'active');
insert into plan_weeks (id, plan_id, week_index, phase, target_volume_m)
values ('eeeeeeee-0000-0000-0000-0000000b2547', 'eeeeeeee-0000-0000-0000-0000000a2547', 0, 'base', 20000),
       ('eeeeeeee-0000-0000-0000-0000000b2548', 'eeeeeeee-0000-0000-0000-0000000a2548', 0, 'base', 20000);
alter table plan_workouts disable trigger user;
insert into plan_workouts (id, week_id, scheduled_date, kind, target_distance_m, target_hr_min_bpm, target_hr_max_bpm)
values ('eeeeeeee-0000-0000-0000-0000000c2547', 'eeeeeeee-0000-0000-0000-0000000b2547', current_date + 1, 'easy', 6000, 120, 140),
       ('eeeeeeee-0000-0000-0000-0000000c2548', 'eeeeeeee-0000-0000-0000-0000000b2548', current_date + 1, 'easy', 6000, 125, 145);
alter table plan_workouts enable trigger user;

select lives_ok(
  $$ select private.erase_values_held_without_consent() $$,
  'the clean-up runs'
);
select is(
  (select row(height_cm, gender)::text from user_profiles
    where id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeee2547'),
  row(null::numeric, null::text)::text,
  'the clean-up nulled the height and gender held without consent'
);
select is(
  (select count(*)::int from body_metrics
    where user_id in ('eeeeeeee-eeee-eeee-eeee-eeeeeeee2547', 'eeeeeeee-eeee-eeee-eeee-eeeeeeee2549')),
  0,
  'the clean-up deleted the weights held without consent, with or without a profile row'
);
select is(
  (select row(target_hr_min_bpm, target_hr_max_bpm)::text from plan_workouts
    where id = 'eeeeeeee-0000-0000-0000-0000000c2547'),
  row(null::smallint, null::smallint)::text,
  'the clean-up nulled the heart-rate targets on the plan of a runner without consent'
);
select is(
  (select row(up.height_cm, up.gender, (select count(*) from body_metrics where user_id = up.id))::text
     from user_profiles up where up.id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeee2548'),
  row(181::numeric(5,1), 'male'::text, 1::bigint)::text,
  'a consenting runner keeps height, gender and weight'
);
select is(
  (select row(target_hr_min_bpm, target_hr_max_bpm)::text from plan_workouts
    where id = 'eeeeeeee-0000-0000-0000-0000000c2548'),
  row(125::smallint, 145::smallint)::text,
  'a consenting runner keeps the heart-rate targets on their plan'
);

select * from finish();
rollback;
