-- Pins the UltraSignup identity on `integrations` (migrations 20270726000003 +
-- 20270729000002, decisions § 1841 + § 1853):
--   * a whole identity (canonical numeric id up to 12 digits, both names, each
--     at most 60 characters) is stored and read back by its owner;
--   * a non-numeric, 13-digit, zero, zero-padded or absent id is refused, and
--     so are a half name pair, a blank name and a 61-character name;
--   * another provider keeps its free-form external_id and needs no name, but
--     the pair rule still holds for it;
--   * the names are owner-only under RLS, like the rest of the row;
--   * disconnecting deletes the owner's row and nothing else, and a stranger's
--     delete removes nothing.

begin;
select plan(19);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('aaaa7731-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'us-owner@int.local', '', now(), now()),
  ('aaaa7731-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'us-other@int.local', '', now(), now());

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"aaaa7731-0000-0000-0000-000000000001","role":"authenticated"}';

insert into integrations (user_id, provider, external_id, external_first_name, external_last_name)
values ('aaaa7731-0000-0000-0000-000000000001', 'ultrasignup', '138805', 'Ann', 'Trail');
insert into integrations (user_id, provider, external_id)
values ('aaaa7731-0000-0000-0000-000000000001', 'strava', 'strava-athlete-77');

select results_eq(
  $$ select external_id, external_first_name, external_last_name from integrations
     where user_id = 'aaaa7731-0000-0000-0000-000000000001' and provider = 'ultrasignup' $$,
  $$ values ('138805'::text, 'Ann'::text, 'Trail'::text) $$,
  'the owner stores a whole UltraSignup identity and reads it back');

-- ── the id ──
select throws_ok(
  $$ update integrations set external_id = 'ann-trail'
     where user_id = 'aaaa7731-0000-0000-0000-000000000001' and provider = 'ultrasignup' $$,
  '23514', null, 'a non-numeric person id is refused');

select throws_ok(
  $$ update integrations set external_id = '1234567890123'
     where user_id = 'aaaa7731-0000-0000-0000-000000000001' and provider = 'ultrasignup' $$,
  '23514', null, 'a 13-digit person id is refused');

update integrations set external_id = '123456789012'
where user_id = 'aaaa7731-0000-0000-0000-000000000001' and provider = 'ultrasignup';
select is(
  (select external_id from integrations
   where user_id = 'aaaa7731-0000-0000-0000-000000000001' and provider = 'ultrasignup'),
  '123456789012', 'a 12-digit person id is stored');

select throws_ok(
  $$ update integrations set external_id = '0'
     where user_id = 'aaaa7731-0000-0000-0000-000000000001' and provider = 'ultrasignup' $$,
  '23514', null, 'the feed''s zero, which means no person, is refused');

select throws_ok(
  $$ update integrations set external_id = '0138805'
     where user_id = 'aaaa7731-0000-0000-0000-000000000001' and provider = 'ultrasignup' $$,
  '23514', null, 'a zero-padded id is refused, so one person has one spelling');

select throws_ok(
  $$ update integrations set external_id = null
     where user_id = 'aaaa7731-0000-0000-0000-000000000001' and provider = 'ultrasignup' $$,
  '23514', null, 'an UltraSignup row with no person id at all is refused');

-- ── the names ──
select throws_ok(
  $$ update integrations set external_last_name = null
     where user_id = 'aaaa7731-0000-0000-0000-000000000001' and provider = 'ultrasignup' $$,
  '23514', null, 'a first name without a last name is refused');

select throws_ok(
  $$ update integrations set external_first_name = null, external_last_name = null
     where user_id = 'aaaa7731-0000-0000-0000-000000000001' and provider = 'ultrasignup' $$,
  '23514', null, 'an UltraSignup id without the name it was found under is refused');

select throws_ok(
  $$ update integrations set external_first_name = '   '
     where user_id = 'aaaa7731-0000-0000-0000-000000000001' and provider = 'ultrasignup' $$,
  '23514', null, 'a blank name cannot be fetched with and is refused');

select throws_ok(
  $$ update integrations set external_first_name = repeat('a', 61)
     where user_id = 'aaaa7731-0000-0000-0000-000000000001' and provider = 'ultrasignup' $$,
  '23514', null, 'a 61-character name is refused');

update integrations set external_first_name = repeat('a', 60)
where user_id = 'aaaa7731-0000-0000-0000-000000000001' and provider = 'ultrasignup';
select is(
  (select char_length(external_first_name) from integrations
   where user_id = 'aaaa7731-0000-0000-0000-000000000001' and provider = 'ultrasignup'),
  60, 'a 60-character name, the function''s own cap, is stored');

-- ── other providers ──
select is(
  (select external_id from integrations
   where user_id = 'aaaa7731-0000-0000-0000-000000000001' and provider = 'strava'),
  'strava-athlete-77', 'another provider keeps a free-form id with no name');

select throws_ok(
  $$ update integrations set external_first_name = 'Ann'
     where user_id = 'aaaa7731-0000-0000-0000-000000000001' and provider = 'strava' $$,
  '23514', null, 'the name pair rule holds for every provider');

-- ── RLS on the names ──
set local "request.jwt.claims" = '{"sub":"aaaa7731-0000-0000-0000-000000000002","role":"authenticated"}';
select is_empty(
  $$ select external_first_name, external_last_name from integrations
     where user_id = 'aaaa7731-0000-0000-0000-000000000001' and provider = 'ultrasignup' $$,
  'another user cannot read the name an UltraSignup identity was found under');

delete from integrations
where user_id = 'aaaa7731-0000-0000-0000-000000000001' and provider = 'ultrasignup';

-- ── disconnect ──
set local "request.jwt.claims" = '{"sub":"aaaa7731-0000-0000-0000-000000000001","role":"authenticated"}';
select is(
  (select count(*)::int from integrations
   where user_id = 'aaaa7731-0000-0000-0000-000000000001' and provider = 'ultrasignup'),
  1, 'a stranger''s delete leaves the owner''s identity in place');

delete from integrations
where user_id = 'aaaa7731-0000-0000-0000-000000000001' and provider = 'ultrasignup';

select is(
  (select count(*)::int from integrations
   where user_id = 'aaaa7731-0000-0000-0000-000000000001' and provider = 'ultrasignup'),
  0, 'unlinking deletes the owner''s UltraSignup row');

select is(
  (select count(*)::int from integrations
   where user_id = 'aaaa7731-0000-0000-0000-000000000001' and provider = 'strava'),
  1, 'unlinking UltraSignup leaves the owner''s other providers alone');

insert into integrations (user_id, provider, external_id, external_first_name, external_last_name)
values ('aaaa7731-0000-0000-0000-000000000001', 'ultrasignup', '138805', 'Ann', 'Trail');
select is(
  (select external_id from integrations
   where user_id = 'aaaa7731-0000-0000-0000-000000000001' and provider = 'ultrasignup'),
  '138805', 'a relink after an unlink stores the identity again');

select * from finish();
rollback;
