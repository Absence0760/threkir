-- Weak-GPS live pings (20271112000030, decisions § 2357).
--
-- Pins: the flag defaults false, the owner can write it, a public spectator
-- reads it back, the privacy-zone last-seen carve-out's delete of earlier
-- coarse rows leaves weak rows alone, and a safety contact's poll RPC carries
-- it.

begin;

select plan(6);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('3eac0000-0000-0000-0000-00000000000a', 'authenticated', 'authenticated', 'o@weakgps.local', '', now(), now()),
  ('3eac0000-0000-0000-0000-00000000000c', 'authenticated', 'authenticated', 'c@weakgps.local', '', now(), now());

select tests.confirm_consent();

insert into user_settings (user_id, prefs)
values ('3eac0000-0000-0000-0000-00000000000a',
        jsonb_build_object('privacy_zones', jsonb_build_array(
          jsonb_build_object('lat', 47.37, 'lng', 8.54, 'radius_m', 150))))
on conflict (user_id) do update set prefs = excluded.prefs;

insert into runs (id, user_id, started_at, duration_s, distance_m, source, activity_type, is_public, metadata)
values ('3eac1000-0000-0000-0000-000000000001', '3eac0000-0000-0000-0000-00000000000a',
        now() - interval '10 minutes', 0, 0, 'app', 'run', true, '{"in_progress": true}');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"3eac0000-0000-0000-0000-00000000000a","role":"authenticated"}';

insert into live_run_pings (run_id, user_id, lat, lng)
values ('3eac1000-0000-0000-0000-000000000001', '3eac0000-0000-0000-0000-00000000000a', 47.40, 8.60);
insert into live_run_pings (run_id, user_id, lat, lng, weak_gps)
values ('3eac1000-0000-0000-0000-000000000001', '3eac0000-0000-0000-0000-00000000000a', 47.41, 8.61, true);

-- (1)
select is(
  (select weak_gps from live_run_pings
    where run_id = '3eac1000-0000-0000-0000-000000000001' and lat = 47.40),
  false,
  'a ping that does not say otherwise is not weak');

-- (2)
select is(
  (select weak_gps from live_run_pings
    where run_id = '3eac1000-0000-0000-0000-000000000001' and lat = 47.41),
  true,
  'the owner can publish a weak-GPS ping');

-- An in-zone ping: the carve-out deletes earlier COARSE rows, never weak ones.
insert into live_run_pings (run_id, user_id, lat, lng, weak_gps)
values ('3eac1000-0000-0000-0000-000000000001', '3eac0000-0000-0000-0000-00000000000a', 47.370001, 8.540001, true);

-- (3)
select is(
  (select count(*)::int from live_run_pings
    where run_id = '3eac1000-0000-0000-0000-000000000001' and weak_gps and not coarse),
  1,
  'an in-zone ping does not sweep the run''s earlier weak-GPS pings');

set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';

-- (4)
select is(
  (select count(*)::int from live_run_pings
    where run_id = '3eac1000-0000-0000-0000-000000000001' and weak_gps),
  2,
  'a public spectator reads the weak flag');

reset role;

insert into private.feature_flags (name, enabled) values ('safety_audience', true)
  on conflict (name) do update set enabled = true;
insert into safety_contacts (id, owner_id, contact_email)
values ('3eacc000-0000-0000-0000-00000000000c', '3eac0000-0000-0000-0000-00000000000a', 'c@weakgps.local');
update safety_contacts set confirmed_at = now(), contact_user_id = '3eac0000-0000-0000-0000-00000000000c'
 where id = '3eacc000-0000-0000-0000-00000000000c';
update runs set is_public = false, safety_audience = true
 where id = '3eac1000-0000-0000-0000-000000000001';
insert into private.run_safety_links (run_id, contact_id, token)
values ('3eac1000-0000-0000-0000-000000000001', '3eacc000-0000-0000-0000-00000000000c',
        '3eac7000-0000-0000-0000-000000000001');

set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';

-- (5)
select is(
  (select count(*)::int from public.safety_live_pings(
     '3eac1000-0000-0000-0000-000000000001', '3eac7000-0000-0000-0000-000000000001')
    where weak_gps),
  2,
  'a safety contact''s backlog carries the weak flag');

-- (6)
select is(
  (select count(*)::int from public.safety_live_pings(
     '3eac1000-0000-0000-0000-000000000001', '3eac7000-0000-0000-0000-000000000001',
     now() - interval '1 hour')
    where weak_gps),
  2,
  'a safety contact''s cursor poll carries the weak flag');

select * from finish();
rollback;
