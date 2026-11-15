-- A direct NULL of health_data_consent_at clears the same consent-gated set
-- withdraw_health_data_consent() clears (migration
-- 20271230001390_consent_null_clears_gated_values.sql; decisions § 2542).
--
-- Pins:
--   * the owner nulling the stamp directly (allowed by lock_consent_columns as
--     an Art 7(3) withdrawal) clears height and gender, the body_metrics
--     series, the heart-rate targets on their plans and every consent-gated
--     settings key, and keeps the age record and the keys that are not
--     health data;
--   * another consented runner's values are untouched;
--   * an update that does not null the stamp clears nothing;
--   * withdraw_health_data_consent() clears the same set;
--   * the set of settings keys is the one the registry names.

begin;

select plan(16);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('cccccccc-0000-0000-0000-00000000139a', 'authenticated', 'authenticated', 'cn-direct@test.local', '', now(), now()),
  ('cccccccc-0000-0000-0000-00000000139b', 'authenticated', 'authenticated', 'cn-rpc@test.local', '', now(), now());

insert into user_profiles (id, display_name, preferred_unit, health_data_consent_at,
                           height_cm, gender, date_of_birth)
values ('cccccccc-0000-0000-0000-00000000139a', 'CN Direct', 'km', '2026-01-01T00:00:00Z',
        170, 'female', '1985-05-05'),
       ('cccccccc-0000-0000-0000-00000000139b', 'CN Rpc', 'km', '2026-01-01T00:00:00Z',
        182, 'male', '1979-09-09');

insert into body_metrics (user_id, weight_kg)
values ('cccccccc-0000-0000-0000-00000000139a', 60.0),
       ('cccccccc-0000-0000-0000-00000000139b', 80.0);

insert into private.feature_flags (name, enabled) values ('hr_prescription', true)
  on conflict (name) do update set enabled = true;

insert into user_settings (user_id, prefs)
select u, jsonb_build_object(
         'hr_medication_affected', true, 'date_of_birth', '1985-05-05',
         'body_weight_kg', 60.0, 'cycle_tracking_mode', 'cycle',
         'cycle_length_days', 28, 'cycle_last_period_start', '2026-10-01',
         'pregnancy_due_date', '2027-03-01', 'weight_unit', 'kg')
from unnest(array['cccccccc-0000-0000-0000-00000000139a',
                  'cccccccc-0000-0000-0000-00000000139b']::uuid[]) u;

insert into training_plans (id, user_id, name, goal_event, goal_distance_m, start_date, end_date, days_per_week, status)
values ('cccccccc-1000-0000-0000-00000000139a', 'cccccccc-0000-0000-0000-00000000139a', 'A', 'distance_10k', 10000,
        current_date, current_date + 48, 4, 'active'),
       ('cccccccc-1000-0000-0000-00000000139b', 'cccccccc-0000-0000-0000-00000000139b', 'B', 'distance_10k', 10000,
        current_date, current_date + 48, 4, 'active');
insert into plan_weeks (id, plan_id, week_index, phase, target_volume_m)
values ('cccccccc-2000-0000-0000-00000000139a', 'cccccccc-1000-0000-0000-00000000139a', 0, 'base', 20000),
       ('cccccccc-2000-0000-0000-00000000139b', 'cccccccc-1000-0000-0000-00000000139b', 0, 'base', 20000);
insert into plan_workouts (id, week_id, scheduled_date, kind, target_distance_m,
                           target_hr_min_bpm, target_hr_max_bpm)
values ('cccccccc-3000-0000-0000-00000000139a', 'cccccccc-2000-0000-0000-00000000139a', current_date + 1, 'easy', 6000, 120, 140),
       ('cccccccc-3000-0000-0000-00000000139b', 'cccccccc-2000-0000-0000-00000000139b', current_date + 1, 'easy', 6000, 120, 140);

-- 1. The settings keys the trigger and the RPC strip.
select is(
  private.health_consent_pref_keys(),
  array['hr_medication_affected', 'date_of_birth', 'body_weight_kg',
        'cycle_tracking_mode', 'cycle_length_days',
        'cycle_last_period_start', 'pregnancy_due_date']::text[],
  'the consent-gated settings keys are the ones docs/backend/settings.md names'
);

-- 2. An update that leaves the stamp alone clears nothing.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"cccccccc-0000-0000-0000-00000000139a","role":"authenticated"}';
update user_profiles set display_name = 'CN Direct renamed'
 where id = 'cccccccc-0000-0000-0000-00000000139a';
update user_settings set prefs = prefs || '{"locale": "en"}'::jsonb
 where user_id = 'cccccccc-0000-0000-0000-00000000139a';
reset role;
select is(
  (select count(*)::int from user_profiles
    where id = 'cccccccc-0000-0000-0000-00000000139a'
      and height_cm = 170 and gender = 'female'),
  1,
  'an unrelated profile update keeps height and gender'
);
select is(
  (select prefs ?& private.health_consent_pref_keys() from user_settings
    where user_id = 'cccccccc-0000-0000-0000-00000000139a'),
  true,
  'an unrelated settings write keeps every consent-gated key'
);

-- 3. The owner nulls the stamp directly.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"cccccccc-0000-0000-0000-00000000139a","role":"authenticated"}';
select lives_ok(
  $$ update user_profiles set health_data_consent_at = null
      where id = 'cccccccc-0000-0000-0000-00000000139a' $$,
  'the owner can null the consent stamp directly'
);
reset role;

select is(
  (select count(*)::int from user_profiles
    where id = 'cccccccc-0000-0000-0000-00000000139a'
      and height_cm is null and gender is null),
  1,
  'a direct null cleared height and gender'
);
select is(
  (select date_of_birth from user_profiles
    where id = 'cccccccc-0000-0000-0000-00000000139a'),
  '1985-05-05'::date,
  'a direct null kept the age record'
);
select is(
  (select count(*)::int from body_metrics
    where user_id = 'cccccccc-0000-0000-0000-00000000139a'),
  0,
  'a direct null erased the body_metrics series'
);
select is(
  (select row(target_hr_min_bpm, target_hr_max_bpm)::text from plan_workouts
    where id = 'cccccccc-3000-0000-0000-00000000139a'),
  row(null::int, null::int)::text,
  'a direct null cleared the heart-rate targets on the runner''s plan'
);
select is(
  (select prefs from user_settings
    where user_id = 'cccccccc-0000-0000-0000-00000000139a'),
  '{"weight_unit": "kg", "locale": "en"}'::jsonb,
  'a direct null stripped every consent-gated settings key and kept the rest'
);

-- 4. The other runner is untouched.
select is(
  (select count(*)::int from user_profiles
    where id = 'cccccccc-0000-0000-0000-00000000139b'
      and height_cm = 182 and gender = 'male'),
  1,
  'another runner keeps height and gender'
);
select is(
  (select count(*)::int from body_metrics
    where user_id = 'cccccccc-0000-0000-0000-00000000139b'),
  1,
  'another runner keeps their weight series'
);
select is(
  (select prefs ?& private.health_consent_pref_keys() from user_settings
    where user_id = 'cccccccc-0000-0000-0000-00000000139b'),
  true,
  'another runner keeps their consent-gated settings keys'
);

-- 5. The RPC clears the same set.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"cccccccc-0000-0000-0000-00000000139b","role":"authenticated"}';
select lives_ok(
  $$ select withdraw_health_data_consent() $$,
  'withdraw_health_data_consent() succeeds'
);
reset role;
select is(
  (select count(*)::int from user_profiles
    where id = 'cccccccc-0000-0000-0000-00000000139b'
      and health_data_consent_at is null and height_cm is null and gender is null),
  1,
  'the RPC nulled the stamp, height and gender'
);
select is(
  (select (select count(*)::int from body_metrics where user_id = 'cccccccc-0000-0000-0000-00000000139b')
        + (select count(*)::int from plan_workouts
            where id = 'cccccccc-3000-0000-0000-00000000139b'
              and (target_hr_min_bpm is not null or target_hr_max_bpm is not null))),
  0,
  'the RPC erased the weight series and the heart-rate targets'
);
select is(
  (select prefs from user_settings
    where user_id = 'cccccccc-0000-0000-0000-00000000139b'),
  '{"weight_unit": "kg"}'::jsonb,
  'the RPC stripped every consent-gated settings key and kept the rest'
);

select * from finish();
rollback;
