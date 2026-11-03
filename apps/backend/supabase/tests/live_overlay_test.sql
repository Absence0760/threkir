-- Streamer overlay (migration 20271104000001, decisions § 2265).
--
-- Pins: the token never reaches a client role; the gate closes making,
-- configuring and reading it, and strips bpm from every ping; the feed returns
-- only pings older than the creator's delay, coordinates only with the map on
-- (never for a coarse last-seen row), bpm only with heart rate on AND
-- health-data consent; a rotated, revoked or wrong token and a concluded run
-- read nothing; heart rate cannot be turned on without consent; token creation
-- is rate-limited; and the hub's consent question is service-role only. A
-- client-written ping's `at` is stamped to its arrival, so a late upload lands
-- after the overlay's cursor instead of behind it, while the service role
-- keeps the `at` it writes.

begin;

select plan(37);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('0e000000-0000-0000-0000-00000000000a', 'authenticated', 'authenticated', 'streamer@overlay.local', '', now(), now()),
  ('0e000000-0000-0000-0000-00000000000b', 'authenticated', 'authenticated', 'other@overlay.local', '', now(), now());

insert into user_profiles (id, display_name)
values
  ('0e000000-0000-0000-0000-00000000000a', 'Streamer Sky'),
  ('0e000000-0000-0000-0000-00000000000b', 'Other Ola')
on conflict (id) do update set display_name = excluded.display_name;

delete from private.feature_flags where name = 'live_overlay';

-- A private live stub: the overlay must work without a public run.
insert into runs (id, user_id, started_at, duration_s, distance_m, source, activity_type, is_public, metadata)
values
  ('0e001000-0000-0000-0000-000000000001', '0e000000-0000-0000-0000-00000000000a',
   now() - interval '10 minutes', 0, 0, 'app', 'run', false, '{"in_progress": true}'),
  ('0e001000-0000-0000-0000-000000000002', '0e000000-0000-0000-0000-00000000000b',
   now() - interval '10 minutes', 0, 0, 'app', 'run', true, '{"in_progress": true}');

-- ── Gate closed ──

-- (1)
select is(public.live_overlay_enabled(), false, 'the gate reads closed while no flag row exists');

update user_profiles set health_data_consent_at = now()
 where id = '0e000000-0000-0000-0000-00000000000a';
insert into live_run_pings (run_id, user_id, at, lat, lng, distance_m, elapsed_s, bpm)
values ('0e001000-0000-0000-0000-000000000001', '0e000000-0000-0000-0000-00000000000a',
        now() - interval '9 minutes', 51.50, -0.10, 100, 60, 140);
-- (2)
select is(
  (select bpm from live_run_pings where run_id = '0e001000-0000-0000-0000-000000000001'),
  null, 'gate closed: a ping keeps no bpm, even with health-data consent');
delete from live_run_pings where run_id = '0e001000-0000-0000-0000-000000000001';

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"0e000000-0000-0000-0000-00000000000a","role":"authenticated"}';
-- (3)
select throws_ok(
  $$ select create_live_overlay_token() $$,
  'P0001', 'live_overlay_disabled', 'gate closed: no token can be made');
-- (4)
select throws_ok(
  $$ select update_live_overlay_settings(30, true, false) $$,
  'P0001', 'live_overlay_disabled', 'gate closed: nothing can be configured');

reset role;
insert into private.feature_flags (name, enabled) values ('live_overlay', true)
  on conflict (name) do update set enabled = true;

-- ── The token never reaches a client role ──
set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';
-- (5)
select throws_ok(
  $$ select token from private.live_overlay_tokens $$,
  '42501', null, 'anon cannot read the overlay token table');
-- (6)
select throws_ok(
  $$ select * from get_live_overlay() $$,
  '42501', null, 'anon cannot call get_live_overlay');
-- (7)
select throws_ok(
  $$ select create_live_overlay_token() $$,
  '42501', null, 'anon cannot make a token');
-- (8)
select throws_ok(
  $$ select live_heart_rate_shared('0e000000-0000-0000-0000-00000000000a') $$,
  '42501', null, 'anon cannot ask whether a user shares heart rate');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"0e000000-0000-0000-0000-00000000000a","role":"authenticated"}';
-- (9)
select throws_ok(
  $$ select token from private.live_overlay_tokens $$,
  '42501', null, 'even the owner cannot read the token table directly');
-- (10)
select throws_ok(
  $$ select live_heart_rate_shared('0e000000-0000-0000-0000-00000000000a') $$,
  '42501', null, 'an authenticated caller cannot ask the hub''s consent question');

-- ── Making and configuring ──
-- (11)
select is((select count(*)::int from get_live_overlay()), 0, 'no overlay before one is made');
-- (12)
select isnt(create_live_overlay_token(), null, 'the owner makes a token');

reset role;
create temporary table tok as
  select t.token from private.live_overlay_tokens t
   where t.user_id = '0e000000-0000-0000-0000-00000000000a';
grant select on tok to anon, authenticated;
set local role authenticated;

-- (13)
select results_eq(
  $$ select token, delay_s, show_map, show_heart_rate, heart_rate_consent from get_live_overlay() $$,
  $$ select (select token from tok), 60, false, false, true $$,
  'the overlay starts with a 60 s delay, no map and no heart rate, and reports consent');
-- (14)
select throws_ok(
  $$ select update_live_overlay_settings(901, false, false) $$,
  '22023', null, 'a delay over 900 s is refused');

-- Consent is withdrawn for the opt-in check, then restored below.
reset role;
update user_profiles set health_data_consent_at = null
 where id = '0e000000-0000-0000-0000-00000000000a';
set local role authenticated;
-- (15)
select throws_ok(
  $$ select update_live_overlay_settings(60, false, true) $$,
  '42501', 'health_data_consent_required',
  'heart rate cannot be turned on without health-data consent');

set local "request.jwt.claims" = '{"sub":"0e000000-0000-0000-0000-00000000000b","role":"authenticated"}';
-- (16)
select throws_ok(
  $$ select update_live_overlay_settings(60, true, false) $$,
  'P0002', null, 'a user with no overlay has nothing to configure');

-- ── The pings: one per age, around a 60 s delay ──
reset role;
set local app.consent_write = 'on';
update user_profiles set health_data_consent_at = now()
 where id = '0e000000-0000-0000-0000-00000000000a';
set local app.consent_write = 'off';
insert into live_run_pings (run_id, user_id, at, lat, lng, distance_m, elapsed_s, bpm, coarse)
values
  ('0e001000-0000-0000-0000-000000000001', '0e000000-0000-0000-0000-00000000000a',
   now() - interval '120 seconds', 51.50, -0.10, 1000, 300, 150, false),
  ('0e001000-0000-0000-0000-000000000001', '0e000000-0000-0000-0000-00000000000a',
   now() - interval '90 seconds', 51.51, -0.11, 1100, 330, 152, false),
  ('0e001000-0000-0000-0000-000000000001', '0e000000-0000-0000-0000-00000000000a',
   now() - interval '30 seconds', 51.52, -0.12, 1200, 360, 155, false),
  ('0e001000-0000-0000-0000-000000000001', '0e000000-0000-0000-0000-00000000000a',
   now() - interval '5 seconds', 51.53, -0.13, 1300, 390, 158, false),
  ('0e001000-0000-0000-0000-000000000002', '0e000000-0000-0000-0000-00000000000b',
   now() - interval '120 seconds', 48.85, 2.35, 500, 200, 130, false);

-- (17)
select is(
  (select bpm from live_run_pings where run_id = '0e001000-0000-0000-0000-000000000002'),
  null, 'a ping from a user without health-data consent keeps no bpm');
-- (18)
select is(
  (select count(*)::int from live_run_pings
    where run_id = '0e001000-0000-0000-0000-000000000001' and bpm is not null),
  4, 'a consenting user''s pings keep their bpm while the gate is open');

set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';
-- (19)
select results_eq(
  $$ select distance_m from live_overlay_feed((select token from tok)) $$,
  $$ values (1000::double precision), (1100::double precision) $$,
  'the feed returns only pings older than the delay, oldest first');
-- (20)
select is(
  (select count(*)::int from live_overlay_feed((select token from tok)) where lat is not null or lng is not null),
  0, 'with the map off no coordinates come back');
-- (21)
select is(
  (select count(*)::int from live_overlay_feed((select token from tok)) where bpm is not null),
  0, 'with heart rate off no bpm comes back');
-- (22)
select results_eq(
  $$ select distance_m from live_overlay_feed((select token from tok), now() - interval '100 seconds') $$,
  $$ values (1100::double precision) $$,
  'with a cursor, only what became visible after it');
-- (23)
select is(
  (select count(*)::int from live_overlay_feed('not-a-token')), 0, 'a wrong token reads nothing');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"0e000000-0000-0000-0000-00000000000a","role":"authenticated"}';
select update_live_overlay_settings(0, true, true);

reset role;
insert into live_run_pings (run_id, user_id, at, lat, lng, distance_m, elapsed_s, coarse)
values ('0e001000-0000-0000-0000-000000000001', '0e000000-0000-0000-0000-00000000000a',
        now() - interval '1 second', 51.54, -0.14, 1350, 400, true);

set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';
-- (24)
select is(
  (select count(*)::int from live_overlay_feed((select token from tok))),
  5, 'a zero delay returns every ping');
-- (25)
select is(
  (select count(*)::int from live_overlay_feed((select token from tok)) where lat is not null),
  4, 'with the map on, coordinates come back for every precise ping');
-- (26)
select is(
  (select lat from live_overlay_feed((select token from tok)) where distance_m = 1350),
  null, 'a coarse last-seen row never carries coordinates');
-- (27)
select is(
  (select bpm from live_overlay_feed((select token from tok)) where distance_m = 1300),
  158, 'heart rate on and consent on record: bpm comes back');

reset role;
update user_profiles set health_data_consent_at = null
 where id = '0e000000-0000-0000-0000-00000000000a';
set local role anon;
-- (28)
select is(
  (select count(*)::int from live_overlay_feed((select token from tok)) where bpm is not null),
  0, 'withdrawing consent stops bpm at once, whatever the setting says');

-- ── A late upload cannot fall behind the cursor ──
-- The owner's phone writes a ping it claims is an hour old, after the overlay
-- has already read up to the coarse row a second ago.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"0e000000-0000-0000-0000-00000000000a","role":"authenticated"}';
insert into live_run_pings (run_id, user_id, at, lat, lng, distance_m, elapsed_s)
values ('0e001000-0000-0000-0000-000000000001', '0e000000-0000-0000-0000-00000000000a',
        now() - interval '1 hour', 51.55, -0.15, 1400, 430);
-- (29)
select is(
  (select at from live_run_pings
    where run_id = '0e001000-0000-0000-0000-000000000001' and distance_m = 1400),
  now(), 'a client-written ping''s at is stamped to the time it arrived');
set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';
-- (30)
select results_eq(
  $$ select distance_m from live_overlay_feed((select token from tok), now() - interval '1 second') $$,
  $$ values (1400::double precision) $$,
  'a late upload comes back after the cursor the overlay already holds');

set local role service_role;
insert into live_run_pings (run_id, user_id, at, lat, lng, distance_m, elapsed_s)
values ('0e001000-0000-0000-0000-000000000002', '0e000000-0000-0000-0000-00000000000b',
        now() - interval '2 hours', 48.86, 2.36, 600, 230);
reset role;
-- (31)
select is(
  (select at from live_run_pings
    where run_id = '0e001000-0000-0000-0000-000000000002' and distance_m = 600),
  now() - interval '2 hours', 'the service role keeps the at it writes');

-- ── Rotation, revocation, the end of the run ──
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"0e000000-0000-0000-0000-00000000000a","role":"authenticated"}';
-- (32)
select isnt(create_live_overlay_token(), (select token from tok), 'making it again replaces the token');
-- (33)
select is(
  (select count(*)::int from live_overlay_feed((select token from tok))), 0,
  'the replaced token reads nothing');
-- (34)
select is(
  (select delay_s from get_live_overlay()), 0, 'replacing the token keeps the settings');

reset role;
update runs set concluded_at = now() where id = '0e001000-0000-0000-0000-000000000001';
set local role authenticated;
-- (35)
select is(
  (select count(*)::int from live_overlay_feed((select token from get_live_overlay()))), 0,
  'a concluded run reads nothing');

select revoke_live_overlay_token();
-- (36)
select is((select count(*)::int from get_live_overlay()), 0, 'revoking deletes the overlay');

-- ── Rate limit: 10 makes an hour ──
do $$
begin
  for i in 1..8 loop
    perform create_live_overlay_token();
  end loop;
end $$;
-- (37)
select throws_ok(
  $$ select create_live_overlay_token() $$,
  'P0001', null, 'the 11th token made in an hour is refused');

select * from finish();
rollback;
