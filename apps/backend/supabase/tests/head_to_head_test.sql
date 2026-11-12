-- Head-to-head comparisons (migration 20271104000003, decisions § 2267).
--
-- Pins each rule a row needs, and that every refusal is the same empty result:
-- mutual follows only; no block either way; the friend's profile public and
-- not shadow-hidden; both runs public (not followers_only, not a DNF); the
-- target visible to the caller; the best attempt per side; no age, gender or
-- personal_records read; authenticated only.

begin;

select plan(29);

-- bb01 me, bb02 friend (mutual), bb03 one-way (I follow them), bb04 private
-- profile, bb05 blocked, bb06 shadow-hidden, bb07 only non-public runs, bb08
-- owns a private route.
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
select ('00000000-0000-0000-0000-00000000bb0' || n)::uuid, 'authenticated', 'authenticated',
       'h2h' || n || '@ci.local', '', now(), now()
  from generate_series(1, 8) n;

insert into user_profiles (id, display_name, handle)
select ('00000000-0000-0000-0000-00000000bb0' || n)::uuid, 'Runner ' || n,
       case n when 2 then 'pal' else null end
  from generate_series(1, 8) n
on conflict (id) do update set display_name = excluded.display_name, handle = excluded.handle;

update user_profiles set profile_private = true where id = '00000000-0000-0000-0000-00000000bb04';
update user_profiles set shadow_hidden = true where id = '00000000-0000-0000-0000-00000000bb06';
-- An age record with consent on the friend: still never derived or returned.
update user_profiles set date_of_birth = (now() - interval '41 years')::date,
                         gender = 'female', health_data_consent_at = now()
 where id = '00000000-0000-0000-0000-00000000bb02';

select tests.confirm_consent();

insert into user_blocks (blocker_id, blocked_id)
values ('00000000-0000-0000-0000-00000000bb01', '00000000-0000-0000-0000-00000000bb05');

-- Mutual edges between me and 02, 04, 05, 06, 07; one-way me -> 03. The block
-- above may already have cleared its edge; it is written back here so the
-- block filter is what refuses 05, not a missing follow.
insert into user_follows (follower_id, followee_id)
select '00000000-0000-0000-0000-00000000bb01'::uuid, ('00000000-0000-0000-0000-00000000bb0' || n)::uuid
  from unnest(array[2, 3, 4, 5, 6, 7]) n
union all
select ('00000000-0000-0000-0000-00000000bb0' || n)::uuid, '00000000-0000-0000-0000-00000000bb01'::uuid
  from unnest(array[2, 4, 5, 6, 7]) n
on conflict do nothing;

insert into routes (id, user_id, name, waypoints, distance_m, is_public)
values
  ('66666666-6666-6666-6666-6666666bb001', '00000000-0000-0000-0000-00000000bb01', 'Shared Loop',
   '[{"lat":47.37,"lng":8.54},{"lat":47.38,"lng":8.55}]', 5000, true),
  ('66666666-6666-6666-6666-6666666bb002', '00000000-0000-0000-0000-00000000bb08', 'Owner Only',
   '[{"lat":47.37,"lng":8.54},{"lat":47.38,"lng":8.55}]', 5000, false);

insert into segments (id, route_id, name, start_distance_m, end_distance_m, author_id)
values ('77777777-7777-7777-7777-7777777bb001', '66666666-6666-6666-6666-6666666bb001',
        'Shared Sprint', 500, 1500, '00000000-0000-0000-0000-00000000bb01');

insert into global_segments (id, name, waypoints, distance_m, is_active)
values
  ('a9a9a9a9-0000-0000-0000-0000000bb001', 'Catalogue Hill',
   '[{"lat":40.0,"lng":-73.0},{"lat":40.002,"lng":-73.0}]', 400, true),
  ('a9a9a9a9-0000-0000-0000-0000000bb002', 'Retired Hill',
   '[{"lat":40.0,"lng":-73.0},{"lat":40.002,"lng":-73.0}]', 400, false);

-- run id suffix: owner digit + attempt letter.
insert into runs (id, user_id, route_id, started_at, distance_m, duration_s, source,
                  activity_type, metadata, is_public, followers_only, is_dnf)
values
  ('88888888-8888-8888-8888-8888888bb01a', '00000000-0000-0000-0000-00000000bb01', '66666666-6666-6666-6666-6666666bb001',
   now() - interval '9 days', 5000, 1900, 'app', 'run', '{"activity_type":"run"}', true, false, false),
  ('88888888-8888-8888-8888-8888888bb01b', '00000000-0000-0000-0000-00000000bb01', '66666666-6666-6666-6666-6666666bb001',
   now() - interval '8 days', 5000, 1500, 'app', 'run', '{"activity_type":"run"}', false, false, false),
  ('88888888-8888-8888-8888-8888888bb02a', '00000000-0000-0000-0000-00000000bb02', '66666666-6666-6666-6666-6666666bb001',
   now() - interval '7 days', 5000, 2000, 'app', 'run', '{"activity_type":"run"}', true, false, false),
  ('88888888-8888-8888-8888-8888888bb02b', '00000000-0000-0000-0000-00000000bb02', '66666666-6666-6666-6666-6666666bb001',
   now() - interval '6 days', 5000, 1950, 'app', 'run', '{"activity_type":"run"}', true, false, false),
  ('88888888-8888-8888-8888-8888888bb02c', '00000000-0000-0000-0000-00000000bb02', '66666666-6666-6666-6666-6666666bb001',
   now() - interval '5 days', 2000, 1000, 'app', 'run', '{"activity_type":"run"}', true, false, true),
  ('88888888-8888-8888-8888-8888888bb02d', '00000000-0000-0000-0000-00000000bb02', '66666666-6666-6666-6666-6666666bb001',
   now() - interval '4 days', 5000, 900, 'app', 'cycle', '{"activity_type":"cycle"}', true, false, false),
  ('88888888-8888-8888-8888-8888888bb02e', '00000000-0000-0000-0000-00000000bb02', '66666666-6666-6666-6666-6666666bb001',
   now() - interval '3 days', 5000, 1100, 'app', 'run', '{"activity_type":"run"}', false, false, false),
  ('88888888-8888-8888-8888-8888888bb03a', '00000000-0000-0000-0000-00000000bb03', '66666666-6666-6666-6666-6666666bb001',
   now() - interval '7 days', 5000, 1000, 'app', 'run', '{"activity_type":"run"}', true, false, false),
  ('88888888-8888-8888-8888-8888888bb04a', '00000000-0000-0000-0000-00000000bb04', '66666666-6666-6666-6666-6666666bb001',
   now() - interval '7 days', 5000, 1000, 'app', 'run', '{"activity_type":"run"}', true, false, false),
  ('88888888-8888-8888-8888-8888888bb05a', '00000000-0000-0000-0000-00000000bb05', '66666666-6666-6666-6666-6666666bb001',
   now() - interval '7 days', 5000, 1000, 'app', 'run', '{"activity_type":"run"}', true, false, false),
  ('88888888-8888-8888-8888-8888888bb06a', '00000000-0000-0000-0000-00000000bb06', '66666666-6666-6666-6666-6666666bb001',
   now() - interval '7 days', 5000, 1000, 'app', 'run', '{"activity_type":"run"}', true, false, false),
  ('88888888-8888-8888-8888-8888888bb07a', '00000000-0000-0000-0000-00000000bb07', '66666666-6666-6666-6666-6666666bb001',
   now() - interval '7 days', 5000, 1000, 'app', 'run', '{"activity_type":"run"}', false, true, false),
  ('88888888-8888-8888-8888-8888888bb07b', '00000000-0000-0000-0000-00000000bb07', '66666666-6666-6666-6666-6666666bb001',
   now() - interval '6 days', 5000, 1001, 'app', 'run', '{"activity_type":"run"}', false, false, false),
  ('88888888-8888-8888-8888-8888888bb01c', '00000000-0000-0000-0000-00000000bb01', '66666666-6666-6666-6666-6666666bb002',
   now() - interval '2 days', 5000, 1900, 'app', 'run', '{"activity_type":"run"}', true, false, false),
  ('88888888-8888-8888-8888-8888888bb02f', '00000000-0000-0000-0000-00000000bb02', '66666666-6666-6666-6666-6666666bb002',
   now() - interval '2 days', 5000, 1950, 'app', 'run', '{"activity_type":"run"}', true, false, false);

insert into segment_efforts (segment_id, run_id, user_id, time_seconds, started_at)
values
  ('77777777-7777-7777-7777-7777777bb001', '88888888-8888-8888-8888-8888888bb01a', '00000000-0000-0000-0000-00000000bb01', 100, now() - interval '9 days'),
  ('77777777-7777-7777-7777-7777777bb001', '88888888-8888-8888-8888-8888888bb02b', '00000000-0000-0000-0000-00000000bb02', 120, now() - interval '6 days'),
  ('77777777-7777-7777-7777-7777777bb001', '88888888-8888-8888-8888-8888888bb02e', '00000000-0000-0000-0000-00000000bb02', 90, now() - interval '3 days');

insert into global_segment_efforts (global_segment_id, run_id, user_id, time_seconds, started_at)
values
  ('a9a9a9a9-0000-0000-0000-0000000bb001', '88888888-8888-8888-8888-8888888bb01a', '00000000-0000-0000-0000-00000000bb01', 200, now() - interval '9 days'),
  ('a9a9a9a9-0000-0000-0000-0000000bb001', '88888888-8888-8888-8888-8888888bb02b', '00000000-0000-0000-0000-00000000bb02', 180, now() - interval '6 days'),
  ('a9a9a9a9-0000-0000-0000-0000000bb002', '88888888-8888-8888-8888-8888888bb01a', '00000000-0000-0000-0000-00000000bb01', 200, now() - interval '9 days'),
  ('a9a9a9a9-0000-0000-0000-0000000bb002', '88888888-8888-8888-8888-8888888bb02b', '00000000-0000-0000-0000-00000000bb02', 180, now() - interval '6 days');

-- ── The shape of the function ──
select ok(
  (select prosecdef from pg_proc where oid = 'public.head_to_head(text, uuid, uuid, text)'::regprocedure),
  'head_to_head is SECURITY DEFINER');
select ok(
  pg_get_function_result('public.head_to_head(text, uuid, uuid, text)'::regprocedure)
    !~ '\m(age|gender|date_of_birth|personal_records)\M',
  'no age, gender or personal_records column is returned');
select ok(
  (select prosrc from pg_proc where oid = 'public.head_to_head(text, uuid, uuid, text)'::regprocedure)
    !~ '(personal_records|date_of_birth|health_data_consent_at|gender|waypoints|track_url)',
  'the body reads no personal_records, age record, gender or line');

set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';
select throws_ok(
  $$ select * from head_to_head('route', '66666666-6666-6666-6666-6666666bb001') $$,
  '42501', null, 'anon cannot call head_to_head');

set local role authenticated;
set local "request.jwt.claims" = '{"role":"authenticated"}';
select throws_ok(
  $$ select * from head_to_head('route', '66666666-6666-6666-6666-6666666bb001') $$,
  '42501', null, 'a caller with no user id is refused');

set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000bb01","role":"authenticated"}';
select throws_ok(
  $$ select * from head_to_head('run', '66666666-6666-6666-6666-6666666bb001') $$,
  '22023', null, 'an unknown kind is refused');

-- ── Route ──
select is(
  (select count(*)::int from head_to_head('route', '66666666-6666-6666-6666-6666666bb001')),
  1, 'the picker lists only the one friend every rule admits');
select is(
  (select friend_id from head_to_head('route', '66666666-6666-6666-6666-6666666bb001')),
  '00000000-0000-0000-0000-00000000bb02'::uuid, 'and it is the mutual follow');
select is(
  (select row(my_seconds, my_run_id)::text from head_to_head('route', '66666666-6666-6666-6666-6666666bb001')),
  row(1900, '88888888-8888-8888-8888-8888888bb01a'::uuid)::text,
  'my side is my best PUBLIC attempt, not my faster private one');
select is(
  (select row(friend_seconds, friend_run_id)::text from head_to_head('route', '66666666-6666-6666-6666-6666666bb001')),
  row(1950, '88888888-8888-8888-8888-8888888bb02b'::uuid)::text,
  'the friend''s side skips the DNF, the cycle and the private run');
select is(
  (select row(friend_handle, friend_display_name, target_name)::text
     from head_to_head('route', '66666666-6666-6666-6666-6666666bb001')),
  row('pal', 'Runner 2', 'Shared Loop')::text, 'names come back for the card');
select is(
  (select count(*)::int from head_to_head('route', '66666666-6666-6666-6666-6666666bb001',
                                          '00000000-0000-0000-0000-00000000bb02')),
  1, 'naming the friend returns their row');
select is(
  (select count(*)::int from head_to_head('route', '66666666-6666-6666-6666-6666666bb001', null, 'cycle')),
  0, 'another activity type compares nothing (I have no public cycle there)');

-- Every refusal below is the same empty result as "no data".
-- refusal: the mutual-follow rule is access control, and 03 has a public run here
select is(
  (select count(*)::int from head_to_head('route', '66666666-6666-6666-6666-6666666bb001',
                                          '00000000-0000-0000-0000-00000000bb03')),
  0, 'a one-way follow is refused');
-- refusal: a private profile is access control, and 04 has a public run here
select is(
  (select count(*)::int from head_to_head('route', '66666666-6666-6666-6666-6666666bb001',
                                          '00000000-0000-0000-0000-00000000bb04')),
  0, 'a private profile cannot be compared against');
-- refusal: the block is access control, and 05 has both edges and a public run here
select is(
  (select count(*)::int from head_to_head('route', '66666666-6666-6666-6666-6666666bb001',
                                          '00000000-0000-0000-0000-00000000bb05')),
  0, 'a blocked friend is refused even with both follow edges');
select is(
  (select count(*)::int from head_to_head('route', '66666666-6666-6666-6666-6666666bb001',
                                          '00000000-0000-0000-0000-00000000bb06')),
  0, 'a shadow-hidden profile is refused');
-- refusal: run visibility is access control, and 07 has two runs here
select is(
  (select count(*)::int from head_to_head('route', '66666666-6666-6666-6666-6666666bb001',
                                          '00000000-0000-0000-0000-00000000bb07')),
  0, 'a friend with only followers-only and private runs is refused');
select is(
  (select count(*)::int from head_to_head('route', '66666666-6666-6666-6666-6666666bb001',
                                          '00000000-0000-0000-0000-00000000bb01')),
  0, 'the caller cannot be their own friend');
select is(
  (select count(*)::int from head_to_head('route', '66666666-6666-6666-6666-6666666bb002')),
  0, 'a route the caller cannot see compares nothing, though both have public runs on it');
select is(
  (select count(*)::int from head_to_head('route', '66666666-6666-6666-6666-6666666bb999')),
  0, 'an unknown route is the same empty result');

-- The other direction of a one-way follow, seen from the followed side.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000bb03","role":"authenticated"}';
-- refusal: the mutual-follow rule, from the side that only follows
select is(
  (select count(*)::int from head_to_head('route', '66666666-6666-6666-6666-6666666bb001',
                                          '00000000-0000-0000-0000-00000000bb01')),
  0, 'being followed without following back is refused too');

-- ── Segments ──
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000bb01","role":"authenticated"}';
select is(
  (select row(my_seconds, friend_seconds, target_name)::text
     from head_to_head('segment', '77777777-7777-7777-7777-7777777bb001')),
  row(100, 120, 'Shared Sprint')::text,
  'a route segment compares efforts on public runs only (the 90 is on a private run)');
select is(
  (select row(my_seconds, friend_seconds, target_name)::text
     from head_to_head('global_segment', 'a9a9a9a9-0000-0000-0000-0000000bb001')),
  row(200, 180, 'Catalogue Hill')::text, 'a catalogue segment compares too');
select is(
  (select count(*)::int from head_to_head('global_segment', 'a9a9a9a9-0000-0000-0000-0000000bb002')),
  0, 'a retired catalogue segment compares nothing');

-- ── Symmetry, and my own run must be public ──
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000bb02","role":"authenticated"}';
select is(
  (select row(my_seconds, friend_seconds)::text
     from head_to_head('route', '66666666-6666-6666-6666-6666666bb001', '00000000-0000-0000-0000-00000000bb01')),
  row(1950, 1900)::text, 'the friend sees the same comparison from their side');

reset role;
update runs set is_public = false where id = '88888888-8888-8888-8888-8888888bb01a';
set local role authenticated;
-- refusal: 01 still has two runs here, both private now
select is(
  (select count(*)::int from head_to_head('route', '66666666-6666-6666-6666-6666666bb001', '00000000-0000-0000-0000-00000000bb01')),
  0, 'once the other side''s only public attempt goes private, nothing is compared');

set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000bb01","role":"authenticated"}';
-- refusal: the caller's own private runs are held back from the card too
select is(
  (select count(*)::int from head_to_head('route', '66666666-6666-6666-6666-6666666bb001')),
  0, 'and the caller without a public attempt gets the same empty result');

reset role;
select ok(
  not has_function_privilege('anon', 'public.head_to_head(text, uuid, uuid, text)', 'execute'),
  'anon holds no execute grant');

select * from finish();
rollback;
