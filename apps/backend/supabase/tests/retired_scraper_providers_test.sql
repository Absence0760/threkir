-- The scraped integrations are retired (migrations 20271216170001 + …02,
-- decisions § 2467):
--   * integrations refuses provider `parkrun` and `ultrasignup`, and still
--     takes the providers that remain;
--   * race_listings refuses provider `parkrun`, and still takes `ultrasignup`
--     (the licensed listings leg stays);
--   * both narrowed constraints are validated, and the UltraSignup identity
--     check is gone with the provider it constrained.

begin;
select plan(9);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('aaaa8801-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'retired@int.local', '', now(), now());

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"aaaa8801-0000-0000-0000-000000000001","role":"authenticated"}';

select throws_ok(
  $$ insert into integrations (user_id, provider) values ('aaaa8801-0000-0000-0000-000000000001', 'parkrun') $$,
  '23514', null, 'a parkrun integration row is refused');

select throws_ok(
  $$ insert into integrations (user_id, provider, external_id, external_first_name, external_last_name)
     values ('aaaa8801-0000-0000-0000-000000000001', 'ultrasignup', '138805', 'Ann', 'Trail') $$,
  '23514', null, 'an UltraSignup identity row is refused');

select lives_ok(
  $$ insert into integrations (user_id, provider, external_id) values ('aaaa8801-0000-0000-0000-000000000001', 'strava', 'athlete-1') $$,
  'a Strava row is still accepted');

reset role;
set local role service_role;

select throws_ok(
  $$ insert into race_listings (provider, provider_race_id, name, race_date, distance_m, is_verified)
     values ('parkrun', '1', 'Some Park', current_date + 3, 5000, true) $$,
  '23514', null, 'a parkrun race listing is refused');

select lives_ok(
  $$ insert into race_listings (provider, provider_race_id, name, race_date, distance_m, is_verified)
     values ('ultrasignup', '500101', 'Example Peaks 100', current_date + 30, 160934, true) $$,
  'an UltraSignup race listing is still accepted');

select lives_ok(
  $$ insert into race_listings (provider, provider_race_id, name, race_date, distance_m, is_verified)
     values ('runsignup', 'rs-1', 'Example 5K', current_date + 10, 5000, true) $$,
  'a RunSignUp race listing is still accepted');

reset role;

select is(
  (select convalidated from pg_constraint where conname = 'integrations_provider_check'),
  true, 'integrations_provider_check is validated');

select is(
  (select convalidated from pg_constraint where conname = 'race_listings_provider_check'),
  true, 'race_listings_provider_check is validated');

select is(
  (select count(*)::int from pg_constraint where conname = 'integrations_ultrasignup_identity_chk'),
  0, 'the UltraSignup identity check is gone');

select * from finish();
rollback;
