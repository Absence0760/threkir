-- The settings-bag weight needs health-data consent (migration
-- 20271229001390_body_weight_needs_health_consent.sql; decisions § 2541).
--
-- Pins:
--   * a runner without health_data_consent_at cannot store body_weight_kg,
--     through merge_my_settings or a direct insert/update (42501);
--   * the same runner can still write every other key, remove the weight, and
--     store a JSON null;
--   * a runner with consent can store and change it;
--   * a settings write that leaves an existing weight as it was is not
--     refused, so an unrelated save never trips over a stored value;
--   * nulling the consent stamp closes the gate again;
--   * withdraw_health_data_consent() strips the weight.

begin;

select plan(12);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeee1390', 'authenticated', 'authenticated', 'bw-none@test.local', '', now(), now()),
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeee1391', 'authenticated', 'authenticated', 'bw-yes@test.local', '', now(), now()),
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeee1392', 'authenticated', 'authenticated', 'bw-noprofile@test.local', '', now(), now());

insert into user_profiles (id, display_name, preferred_unit, health_data_consent_at)
values ('eeeeeeee-eeee-eeee-eeee-eeeeeeee1390', 'BW None', 'km', null),
       ('eeeeeeee-eeee-eeee-eeee-eeeeeeee1391', 'BW Yes', 'km', '2026-01-01T00:00:00Z');

-- 1. A direct insert without consent is refused (any writer, not only the
--    owner's own merge).
select throws_ok(
  $$ insert into user_settings (user_id, prefs)
     values ('eeeeeeee-eeee-eeee-eeee-eeeeeeee1392', '{"body_weight_kg": 70}'::jsonb) $$,
  '42501', 'user_settings: body_weight_kg needs health-data consent',
  'a weight for a runner with no profile (so no consent) is refused on insert'
);

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"eeeeeeee-eeee-eeee-eeee-eeeeeeee1390","role":"authenticated"}';

-- 2-3. The owner's own merge, without consent: the weight is refused, every
--      other key is not.
select throws_ok(
  $$ select merge_my_settings('{"body_weight_kg": 70}'::jsonb) $$,
  '42501', 'user_settings: body_weight_kg needs health-data consent',
  'merge_my_settings refuses a weight without health-data consent'
);
select lives_ok(
  $$ select merge_my_settings('{"weight_unit": "kg", "privacy_default": "private"}'::jsonb) $$,
  'a runner without consent can still save the keys that are not health data'
);

-- 4. Removing the key, and a JSON null, are never refused.
select lives_ok(
  $$ select merge_my_settings('{"body_weight_kg": null}'::jsonb) $$,
  'removing the weight is never refused'
);
reset role;
select lives_ok(
  $$ update user_settings set prefs = prefs || '{"body_weight_kg": null}'::jsonb
      where user_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeee1390' $$,
  'a JSON-null weight is not a weight and is not refused'
);

-- 5. With consent the weight is stored and can change.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"eeeeeeee-eeee-eeee-eeee-eeeeeeee1391","role":"authenticated"}';
select lives_ok(
  $$ select merge_my_settings('{"body_weight_kg": 70}'::jsonb) $$,
  'a runner with consent can store a weight'
);
select lives_ok(
  $$ select merge_my_settings('{"body_weight_kg": 71.5}'::jsonb) $$,
  'a runner with consent can change the weight'
);
reset role;
select is(
  (select (prefs ->> 'body_weight_kg')::numeric from user_settings
    where user_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeee1391'),
  71.5::numeric,
  'the consented weight is stored'
);

-- 6. A direct null of the stamp (a withdrawal the lock trigger allows) closes
--    the gate for a new value, while a write that leaves the stored weight
--    untouched still lands.
update user_profiles set health_data_consent_at = null
 where id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeee1391';
select lives_ok(
  $$ update user_settings set prefs = prefs || '{"locale": "en"}'::jsonb
      where user_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeee1391' $$,
  'an unrelated settings write never trips over a weight already stored'
);
select throws_ok(
  $$ update user_settings set prefs = prefs || '{"body_weight_kg": 90}'::jsonb
      where user_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeee1391' $$,
  '42501', 'user_settings: body_weight_kg needs health-data consent',
  'changing the weight after consent is gone is refused'
);

-- 7. withdraw_health_data_consent() strips the weight, whether or not consent
--    was on record when it was called.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"eeeeeeee-eeee-eeee-eeee-eeeeeeee1391","role":"authenticated"}';
select lives_ok(
  $$ select withdraw_health_data_consent() $$,
  'withdraw_health_data_consent() succeeds'
);
reset role;
select is(
  (select prefs ? 'body_weight_kg' from user_settings
    where user_id = 'eeeeeeee-eeee-eeee-eeee-eeeeeeee1391'),
  false,
  'withdrawal stripped the weight from the settings bag'
);

select * from finish();
rollback;
