-- Coach run map (20270822000011, decisions § 1968): coached_runs admits a
-- caller to an athlete's runs only through an active coaching link with the
-- coach_run_map gate open, and clip_track_for_user trims the athlete's zones
-- from what clip-public-track then serves.
--
-- Principals:
--   A  athlete, with a privacy zone and one private run
--   C  coach with an active link to A
--   E  coach whose link to A has ended
--   N  signed-in stranger
--
-- The refusals (N, E) are measured by the pgtap guard's coached_runs
-- neutraliser; the active coach's read beside them is the positive control.

begin;

select plan(7);

insert into private.feature_flags (name, enabled) values ('coach_run_map', true)
  on conflict (name) do update set enabled = true;

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('c0a50000-0000-0000-0000-00000000000a', 'authenticated', 'authenticated', 'a@coachmap.local', '', now(), now()),
  ('c0a50000-0000-0000-0000-00000000000c', 'authenticated', 'authenticated', 'c@coachmap.local', '', now(), now()),
  ('c0a50000-0000-0000-0000-00000000000e', 'authenticated', 'authenticated', 'e@coachmap.local', '', now(), now()),
  ('c0a50000-0000-0000-0000-00000000000f', 'authenticated', 'authenticated', 'n@coachmap.local', '', now(), now());

select tests.confirm_consent();

insert into coach_athletes (coach_id, athlete_id, invite_token, status, accepted_at, ended_at)
values
  ('c0a50000-0000-0000-0000-00000000000c', 'c0a50000-0000-0000-0000-00000000000a',
   'coachmap-active-token', 'active', now(), null),
  ('c0a50000-0000-0000-0000-00000000000e', 'c0a50000-0000-0000-0000-00000000000a',
   'coachmap-ended-token', 'ended', now() - interval '20 days', now() - interval '10 days');

insert into user_settings (user_id, prefs)
values ('c0a50000-0000-0000-0000-00000000000a',
        jsonb_build_object('privacy_zones', jsonb_build_array(
          jsonb_build_object('lat', 47.37, 'lng', 8.54, 'radius_m', 150))))
on conflict (user_id) do update set prefs = excluded.prefs;

insert into runs (id, user_id, started_at, distance_m, duration_s, source, is_public, metadata)
values
  ('c0a5aaaa-0000-0000-0000-000000000001', 'c0a50000-0000-0000-0000-00000000000a',
   now() - interval '2 days', 8000, 2400, 'app', false, '{"activity_type":"run"}'),
  ('c0a5aaaa-0000-0000-0000-000000000002', 'c0a50000-0000-0000-0000-00000000000c',
   now() - interval '2 days', 6000, 1800, 'app', false, '{"activity_type":"run"}');

set local role authenticated;

-- (1)
set local "request.jwt.claims" = '{"sub":"c0a50000-0000-0000-0000-00000000000f","role":"authenticated"}';
select is(
  (select count(*)::int from coached_runs),
  0,
  'a signed-in stranger cannot see any athlete''s run through the coach view');

-- (2)
set local "request.jwt.claims" = '{"sub":"c0a50000-0000-0000-0000-00000000000c","role":"authenticated"}';
select is(
  (select count(*)::int from coached_runs
    where id in ('c0a5aaaa-0000-0000-0000-000000000001', 'c0a5aaaa-0000-0000-0000-000000000002')),
  1,
  'the active coach reads the athlete''s private run and not their own through the view');

-- (3)
set local "request.jwt.claims" = '{"sub":"c0a50000-0000-0000-0000-00000000000e","role":"authenticated"}';
select is(
  (select count(*)::int from coached_runs)
    + (select count(*)::int from runs where id = 'c0a5aaaa-0000-0000-0000-000000000001'),
  0,
  'a coach whose link ended cannot see the athlete''s run, through the view or the table');

-- (4)
set local "request.jwt.claims" = '{"sub":"c0a50000-0000-0000-0000-00000000000a","role":"authenticated"}';
select is(
  (select count(*)::int from coached_runs)
    + (select count(*)::int from runs where id = 'c0a5aaaa-0000-0000-0000-000000000001'),
  1,
  'the athlete reads their own run from the table and nothing from the coach view');

-- (5) closed gate
reset role;
update private.feature_flags set enabled = false where name = 'coach_run_map';
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c0a50000-0000-0000-0000-00000000000c","role":"authenticated"}';
select is(
  (select count(*)::int from coached_runs)
    + (select count(*)::int from runs where id = 'c0a5aaaa-0000-0000-0000-000000000001'),
  1,
  'with the gate closed the coach keeps the run row (§ 98) and the view is empty, so no map is served');

select is(
  (select public.coach_run_map_enabled()),
  false,
  'clients read the closed gate and draw no map');

reset role;

-- (7) What clip-public-track then serves a coach: the athlete's zone trimmed.
select is(
  jsonb_array_length(clip_track_for_user(
    'c0a50000-0000-0000-0000-00000000000a',
    '[{"lat":47.37,"lng":8.54},{"lat":47.38,"lng":8.55},{"lat":47.39,"lng":8.56}]'::jsonb)),
  2,
  'the coach is served the track clipped against the athlete''s zones, not the raw points');

select * from finish();
rollback;
