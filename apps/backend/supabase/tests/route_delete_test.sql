-- Pins what deleting a route does to everything that references it (issue
-- #1286, migration 20271106000001, decisions § 2292), with the delete run as
-- the owner's own session so every ON DELETE action and every trigger it
-- reaches runs under the claims a real client sends.
--
--   1-3.   route_delete_impact: refused to a stranger, refused for a missing
--          route, and the owner reads every count, "others" excluding their
--          own rows.
--   4-5.   A stranger who can see the route deletes nothing.
--   6.     The owner's delete removes the route.
--   7-14.  The route's own content cascades: photos, markers, conditions,
--          reviews, shares, bookmarks, segments and segment efforts.
--   15-20. Records that pointed at it keep living with the link nulled: the
--          runs that followed it, an event using it, an event course using it,
--          and a race listing using it as its course, which stays verified.
--   21-22. A photo's bytes stay readable to their uploader after the cascade
--          has taken the route_photos row, so the client sweep can remove
--          them; another user still cannot read them.
--   23-24. A club admin may delete a club route uploaded by someone else, and
--          reads its impact.
--   25.    anon cannot call route_delete_impact.

begin;
select plan(25);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('d1286000-0000-0000-0000-0000000000a1', 'authenticated', 'authenticated', 'rd-owner@rd.local', '', now(), now()),
  ('d1286000-0000-0000-0000-0000000000a2', 'authenticated', 'authenticated', 'rd-other@rd.local', '', now(), now()),
  ('d1286000-0000-0000-0000-0000000000a3', 'authenticated', 'authenticated', 'rd-admin@rd.local', '', now(), now());

insert into clubs (id, owner_id, name, slug, is_public)
values ('d1286000-0000-0000-0000-0000000000c1', 'd1286000-0000-0000-0000-0000000000a3',
        'Route Delete Club', 'route-delete-club', true);

insert into routes (id, user_id, name, waypoints, distance_m, is_public, club_id)
values
  ('d1286000-0000-0000-0000-0000000000b1', 'd1286000-0000-0000-0000-0000000000a1', 'Old import',
   '[{"lat":51.5,"lng":-0.1},{"lat":51.51,"lng":-0.11}]'::jsonb, 5000, true, null),
  ('d1286000-0000-0000-0000-0000000000b2', 'd1286000-0000-0000-0000-0000000000a1', 'Club loop',
   '[{"lat":51.5,"lng":-0.1},{"lat":51.51,"lng":-0.11}]'::jsonb, 5000, false,
   'd1286000-0000-0000-0000-0000000000c1');

insert into runs (id, user_id, route_id, started_at, distance_m, duration_s, source, metadata)
values
  ('d1286000-0000-0000-0000-0000000000d1', 'd1286000-0000-0000-0000-0000000000a1',
   'd1286000-0000-0000-0000-0000000000b1', now() - interval '2 days', 5000, 1500, 'app', '{"activity_type":"run"}'),
  ('d1286000-0000-0000-0000-0000000000d2', 'd1286000-0000-0000-0000-0000000000a2',
   'd1286000-0000-0000-0000-0000000000b1', now() - interval '1 day', 5000, 1600, 'app', '{"activity_type":"run"}');

insert into saved_routes (user_id, route_id)
values ('d1286000-0000-0000-0000-0000000000a1', 'd1286000-0000-0000-0000-0000000000b1'),
       ('d1286000-0000-0000-0000-0000000000a2', 'd1286000-0000-0000-0000-0000000000b1');

insert into route_reviews (route_id, user_id, rating)
values ('d1286000-0000-0000-0000-0000000000b1', 'd1286000-0000-0000-0000-0000000000a1', 5),
       ('d1286000-0000-0000-0000-0000000000b1', 'd1286000-0000-0000-0000-0000000000a2', 4);

insert into route_conditions (route_id, user_id, condition, severity)
values ('d1286000-0000-0000-0000-0000000000b1', 'd1286000-0000-0000-0000-0000000000a2', 'muddy', 'caution');

insert into route_markers (id, route_id, user_id, kind, label, lat, lng)
values ('d1286000-0000-0000-0000-0000000000e1', 'd1286000-0000-0000-0000-0000000000b1',
        'd1286000-0000-0000-0000-0000000000a1', 'aid_station', 'Water', 51.505, -0.105);

insert into route_shares (route_id, owner_id, recipient_id)
values ('d1286000-0000-0000-0000-0000000000b1', 'd1286000-0000-0000-0000-0000000000a1',
        'd1286000-0000-0000-0000-0000000000a2');

insert into segments (id, route_id, name, start_distance_m, end_distance_m, author_id)
values
  ('d1286000-0000-0000-0000-0000000000f1', 'd1286000-0000-0000-0000-0000000000b1', 'Owner climb', 0, 1000,
   'd1286000-0000-0000-0000-0000000000a1'),
  ('d1286000-0000-0000-0000-0000000000f2', 'd1286000-0000-0000-0000-0000000000b1', 'Other sprint', 1000, 2000,
   'd1286000-0000-0000-0000-0000000000a2');

insert into segment_efforts (segment_id, run_id, user_id, time_seconds, started_at)
values ('d1286000-0000-0000-0000-0000000000f1', 'd1286000-0000-0000-0000-0000000000d2',
        'd1286000-0000-0000-0000-0000000000a2', 300, now() - interval '1 day');

insert into storage.objects (bucket_id, name, owner)
values ('route-photos', 'd1286000-0000-0000-0000-0000000000a1/rd-photo.jpg',
        'd1286000-0000-0000-0000-0000000000a1');

insert into route_photos (route_id, owner_id, storage_path)
values ('d1286000-0000-0000-0000-0000000000b1', 'd1286000-0000-0000-0000-0000000000a1',
        'd1286000-0000-0000-0000-0000000000a1/rd-photo.jpg');

insert into events (id, club_id, title, starts_at, author_id, is_public, route_id)
values
  ('d1286000-0000-0000-0000-0000000000e7', 'd1286000-0000-0000-0000-0000000000c1', 'Tuesday run',
   now() + interval '7 days', 'd1286000-0000-0000-0000-0000000000a3', true,
   'd1286000-0000-0000-0000-0000000000b1'),
  ('d1286000-0000-0000-0000-0000000000e8', 'd1286000-0000-0000-0000-0000000000c1', 'Two-course race',
   now() + interval '14 days', 'd1286000-0000-0000-0000-0000000000a3', true, null);

insert into event_courses (id, event_id, name, distance_m, sort_order, route_id)
values ('d1286000-0000-0000-0000-0000000000ec', 'd1286000-0000-0000-0000-0000000000e8', '5K', 5000, 0,
        'd1286000-0000-0000-0000-0000000000b1');

set local role service_role;
insert into race_listings (id, provider, provider_race_id, name, race_date, distance_m, is_verified, route_id)
values ('d1286000-0000-0000-0000-00000000aaa1', 'runsignup', 'rd-1286', 'Old Import 5K', '2036-06-01', 5000, true,
        'd1286000-0000-0000-0000-0000000000b1');
reset role;

-- ── 1-3: route_delete_impact ───────────────────────────────────────────────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"d1286000-0000-0000-0000-0000000000a2","role":"authenticated"}';

select throws_ok(
  $$ select * from route_delete_impact('d1286000-0000-0000-0000-0000000000b1') $$,
  '42501', 'not allowed to delete this route',
  'a stranger cannot read a route''s delete impact');

set local "request.jwt.claims" = '{"sub":"d1286000-0000-0000-0000-0000000000a1","role":"authenticated"}';

select throws_ok(
  $$ select * from route_delete_impact('d1286000-0000-0000-0000-0000000000ff') $$,
  '42501', 'not allowed to delete this route',
  'a missing route answers the same refusal');

select results_eq(
  $$ select saved_by_others, reviews_by_others, conditions_by_others, segments_by_others,
            segment_efforts_by_others, shares, race_listings, events, linked_runs, photos, markers
     from route_delete_impact('d1286000-0000-0000-0000-0000000000b1') $$,
  $$ values (1, 1, 1, 1, 1, 1, 1, 2, 2, 1, 1) $$,
  'the owner reads every count, "others" leaving out their own bookmark, review and segment');

-- ── 4-5: a stranger's delete ───────────────────────────────────────────────
set local "request.jwt.claims" = '{"sub":"d1286000-0000-0000-0000-0000000000a2","role":"authenticated"}';

select isnt_empty(
  $$ select 1 from public_routes where id = 'd1286000-0000-0000-0000-0000000000b1' $$,
  'the stranger can read the public route they are about to try deleting');

delete from routes where id = 'd1286000-0000-0000-0000-0000000000b1';
reset role;

-- refusal: routes RLS admits the delete to the uploader and club admins only
select is(
  (select count(*)::int from routes where id = 'd1286000-0000-0000-0000-0000000000b1'),
  1,
  'a stranger''s delete removes nothing');

-- ── 6: the owner's delete ──────────────────────────────────────────────────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"d1286000-0000-0000-0000-0000000000a1","role":"authenticated"}';

delete from routes where id = 'd1286000-0000-0000-0000-0000000000b1';
select is(
  (select count(*)::int from routes where id = 'd1286000-0000-0000-0000-0000000000b1'),
  0,
  'the owner''s delete removes the route');

-- ── 21: the uploader can still reach their bytes ────────────────────────────
select is(
  (select count(*)::int from storage.objects
     where bucket_id = 'route-photos' and name = 'd1286000-0000-0000-0000-0000000000a1/rd-photo.jpg'),
  1,
  'the uploader still reads their photo object once its route_photos row is gone');

set local "request.jwt.claims" = '{"sub":"d1286000-0000-0000-0000-0000000000a2","role":"authenticated"}';
select is(
  (select count(*)::int from storage.objects
     where bucket_id = 'route-photos' and name = 'd1286000-0000-0000-0000-0000000000a1/rd-photo.jpg'),
  0,
  'another user cannot read the uploader''s orphaned photo object');
reset role;

-- ── 7-14: the cascade ──────────────────────────────────────────────────────
select is((select count(*)::int from route_photos where route_id = 'd1286000-0000-0000-0000-0000000000b1'), 0,
  'the route''s photos cascade');
select is((select count(*)::int from route_markers where id = 'd1286000-0000-0000-0000-0000000000e1'), 0,
  'the route''s markers cascade');
select is((select count(*)::int from route_conditions where route_id = 'd1286000-0000-0000-0000-0000000000b1'), 0,
  'condition reports on the route cascade');
select is((select count(*)::int from route_reviews where route_id = 'd1286000-0000-0000-0000-0000000000b1'), 0,
  'reviews of the route cascade');
select is((select count(*)::int from route_shares where route_id = 'd1286000-0000-0000-0000-0000000000b1'), 0,
  'shares of the route cascade');
select is((select count(*)::int from saved_routes where route_id = 'd1286000-0000-0000-0000-0000000000b1'), 0,
  'bookmarks of the route cascade');
select is((select count(*)::int from segments where route_id = 'd1286000-0000-0000-0000-0000000000b1'), 0,
  'segments on the route cascade');
select is((select count(*)::int from segment_efforts where segment_id = 'd1286000-0000-0000-0000-0000000000f1'), 0,
  'efforts on those segments cascade');

-- ── 15-20: the links that are nulled ───────────────────────────────────────
select is((select count(*)::int from runs where id in ('d1286000-0000-0000-0000-0000000000d1',
                                                       'd1286000-0000-0000-0000-0000000000d2')), 2,
  'the runs that followed the route survive');
select is((select count(*)::int from runs where id in ('d1286000-0000-0000-0000-0000000000d1',
                                                       'd1286000-0000-0000-0000-0000000000d2')
                                            and route_id is null), 2,
  'and lose the link');
select is((select route_id from events where id = 'd1286000-0000-0000-0000-0000000000e7'), null::uuid,
  'an event using the route keeps running with no route');
select is((select route_id from event_courses where id = 'd1286000-0000-0000-0000-0000000000ec'), null::uuid,
  'an event course using the route survives with no route');
select is((select route_id from race_listings where id = 'd1286000-0000-0000-0000-00000000aaa1'), null::uuid,
  'a race listing using the route loses its course');
select is((select is_verified from race_listings where id = 'd1286000-0000-0000-0000-00000000aaa1'), true,
  'and stays verified');

-- ── 23-24: a club admin and a club route ───────────────────────────────────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"d1286000-0000-0000-0000-0000000000a3","role":"authenticated"}';

select results_eq(
  $$ select linked_runs, photos from route_delete_impact('d1286000-0000-0000-0000-0000000000b2') $$,
  $$ values (0, 0) $$,
  'a club admin reads the impact of a club route someone else uploaded');

delete from routes where id = 'd1286000-0000-0000-0000-0000000000b2';
reset role;
select is(
  (select count(*)::int from routes where id = 'd1286000-0000-0000-0000-0000000000b2'),
  0,
  'a club admin deletes that club route');

-- ── 25: anon ───────────────────────────────────────────────────────────────
select ok(
  not has_function_privilege('anon', 'public.route_delete_impact(uuid)', 'execute'),
  'anon cannot execute route_delete_impact');

select * from finish();
rollback;
