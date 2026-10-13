-- Audience sharing (20270802000001..3): the visibility matrix for the
-- followers level and named-person grants, on runs and on routes.
--
-- Principals, all non-owners but O:
--   O  owner
--   R  named recipient of a live grant (O follows R, so the grant is admitted;
--      R does not follow O, so nothing R sees comes from the followers level)
--   V  named recipient whose grant O revoked (O follows V)
--   F  follower of O (F -> O), holds no grant
--   N  connected to nobody
--   anon (a null viewer)
-- Entities, one of each per table:
--   priv  owner-only        fol  followers_only
--   shr   private + grant   pub  is_public
--
-- The clipped-track rule for runs lives in the clip-public-track Edge Function
-- (Deno tests beside it); here it is pinned for routes through
-- clip_route_for_viewer, and for runs by the absence of any track column in
-- shared_runs plus the owner-only Storage policy.

begin;

select plan(41);

insert into private.feature_flags (name, enabled) values ('audience_sharing', true)
  on conflict (name) do update set enabled = true;

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('a5a50000-0000-0000-0000-00000000000a', 'authenticated', 'authenticated', 'o@share.local', '', now(), now()),
  ('a5a50000-0000-0000-0000-00000000000b', 'authenticated', 'authenticated', 'r@share.local', '', now(), now()),
  ('a5a50000-0000-0000-0000-00000000000c', 'authenticated', 'authenticated', 'v@share.local', '', now(), now()),
  ('a5a50000-0000-0000-0000-00000000000d', 'authenticated', 'authenticated', 'f@share.local', '', now(), now()),
  ('a5a50000-0000-0000-0000-00000000000e', 'authenticated', 'authenticated', 'n@share.local', '', now(), now());

select tests.confirm_consent();

insert into user_follows (follower_id, followee_id) values
  ('a5a50000-0000-0000-0000-00000000000a', 'a5a50000-0000-0000-0000-00000000000b'),
  ('a5a50000-0000-0000-0000-00000000000a', 'a5a50000-0000-0000-0000-00000000000c'),
  ('a5a50000-0000-0000-0000-00000000000d', 'a5a50000-0000-0000-0000-00000000000a');

-- O's privacy zone covers the first waypoint of every route below.
insert into user_settings (user_id, prefs)
values ('a5a50000-0000-0000-0000-00000000000a',
        jsonb_build_object('privacy_zones', jsonb_build_array(
          jsonb_build_object('lat', 47.37, 'lng', 8.54, 'radius_m', 150))))
on conflict (user_id) do update set prefs = excluded.prefs;

insert into runs (id, user_id, started_at, distance_m, duration_s, source, is_public, followers_only, metadata)
values
  ('a5a5aaaa-0000-0000-0000-000000000001', 'a5a50000-0000-0000-0000-00000000000a',
   now() - interval '30 days', 5000, 1500, 'app', false, false, '{"activity_type":"run"}'),
  ('a5a5aaaa-0000-0000-0000-000000000002', 'a5a50000-0000-0000-0000-00000000000a',
   now() - interval '30 days', 5000, 1500, 'app', false, true, '{"activity_type":"run"}'),
  ('a5a5aaaa-0000-0000-0000-000000000003', 'a5a50000-0000-0000-0000-00000000000a',
   now() - interval '30 days', 5000, 1500, 'app', false, false,
   '{"activity_type":"run","strava_id":"123","plan_workout_id":"x","title":"Shared tempo"}'),
  ('a5a5aaaa-0000-0000-0000-000000000004', 'a5a50000-0000-0000-0000-00000000000a',
   now() - interval '30 days', 5000, 1500, 'app', true, false, '{"activity_type":"run"}');

insert into routes (id, user_id, name, waypoints, distance_m, is_public, followers_only)
select v.id::uuid, 'a5a50000-0000-0000-0000-00000000000a', v.name,
       '[{"lat":47.37,"lng":8.54},{"lat":47.38,"lng":8.55},{"lat":47.39,"lng":8.56}]'::jsonb,
       5000, v.pub, v.fol
  from (values
    ('a5a5bbbb-0000-0000-0000-000000000001', 'priv', false, false),
    ('a5a5bbbb-0000-0000-0000-000000000002', 'fol',  false, true),
    ('a5a5bbbb-0000-0000-0000-000000000003', 'shr',  false, false),
    ('a5a5bbbb-0000-0000-0000-000000000004', 'pub',  true,  false)
  ) as v(id, name, pub, fol);

-- ── Grant-table RLS, written as the owner ──
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"a5a50000-0000-0000-0000-00000000000a","role":"authenticated"}';

-- (1)
select lives_ok(
  $$insert into run_shares (run_id, owner_id, recipient_id) values
      ('a5a5aaaa-0000-0000-0000-000000000003', 'a5a50000-0000-0000-0000-00000000000a', 'a5a50000-0000-0000-0000-00000000000b'),
      ('a5a5aaaa-0000-0000-0000-000000000003', 'a5a50000-0000-0000-0000-00000000000a', 'a5a50000-0000-0000-0000-00000000000c')$$,
  'the owner shares a run with two people they are connected to');

-- (2)
select lives_ok(
  $$insert into route_shares (route_id, owner_id, recipient_id) values
      ('a5a5bbbb-0000-0000-0000-000000000003', 'a5a50000-0000-0000-0000-00000000000a', 'a5a50000-0000-0000-0000-00000000000b'),
      ('a5a5bbbb-0000-0000-0000-000000000003', 'a5a50000-0000-0000-0000-00000000000a', 'a5a50000-0000-0000-0000-00000000000c')$$,
  'the owner shares a route with two people they are connected to');

-- (3)
select throws_ok(
  $$insert into run_shares (run_id, owner_id, recipient_id) values
      ('a5a5aaaa-0000-0000-0000-000000000003', 'a5a50000-0000-0000-0000-00000000000a', 'a5a50000-0000-0000-0000-00000000000e')$$,
  '42501', null,
  'a grant to someone with no follow edge either way is refused');

-- (4)
select throws_ok(
  $$insert into run_shares (run_id, owner_id, recipient_id) values
      ('a5a5aaaa-0000-0000-0000-000000000003', 'a5a50000-0000-0000-0000-00000000000a', 'a5a50000-0000-0000-0000-00000000000a')$$,
  '42501', null,
  'a grant to oneself is refused by the rail');

-- Revoke V: access must end on the next read.
delete from run_shares where run_id = 'a5a5aaaa-0000-0000-0000-000000000003'
  and recipient_id = 'a5a50000-0000-0000-0000-00000000000c';
delete from route_shares where route_id = 'a5a5bbbb-0000-0000-0000-000000000003'
  and recipient_id = 'a5a50000-0000-0000-0000-00000000000c';

-- (5)
select is((select count(*)::int from run_shares where run_id = 'a5a5aaaa-0000-0000-0000-000000000003'),
  1, 'the owner reads their remaining grant and the revoked one is gone');

-- (6) a grant on someone else's run, written as F about O's run
set local "request.jwt.claims" = '{"sub":"a5a50000-0000-0000-0000-00000000000d","role":"authenticated"}';
select throws_ok(
  $$insert into run_shares (run_id, owner_id, recipient_id) values
      ('a5a5aaaa-0000-0000-0000-000000000001', 'a5a50000-0000-0000-0000-00000000000d', 'a5a50000-0000-0000-0000-00000000000a')$$,
  '42501', null,
  'a grant on a run the caller does not own is refused');

-- (7)
select is((select count(*)::int from run_shares), 0,
  'a follower who is not the recipient cannot see the owner''s grants');

-- (8)
set local "request.jwt.claims" = '{"sub":"a5a50000-0000-0000-0000-00000000000b","role":"authenticated"}';
select is((select count(*)::int from run_shares where recipient_id = 'a5a50000-0000-0000-0000-00000000000b'),
  1, 'the recipient reads their own grant');

-- (9) the recipient cannot revoke the owner's grant
delete from run_shares where run_id = 'a5a5aaaa-0000-0000-0000-000000000003';
reset role;
select is((select count(*)::int from run_shares where run_id = 'a5a5aaaa-0000-0000-0000-000000000003'),
  1, 'a recipient delete leaves the grant in place');

-- ── The run matrix, through private.is_run_visible_to ──
create temporary table share_viewers (who text, uid uuid);
insert into share_viewers values
  ('1 owner',     'a5a50000-0000-0000-0000-00000000000a'),
  ('2 recipient', 'a5a50000-0000-0000-0000-00000000000b'),
  ('3 revoked',   'a5a50000-0000-0000-0000-00000000000c'),
  ('4 follower',  'a5a50000-0000-0000-0000-00000000000d'),
  ('5 stranger',  'a5a50000-0000-0000-0000-00000000000e'),
  ('6 anon',      null);

create temporary table share_runs (level text, id uuid);
insert into share_runs values
  ('a priv', 'a5a5aaaa-0000-0000-0000-000000000001'),
  ('b fol',  'a5a5aaaa-0000-0000-0000-000000000002'),
  ('c shr',  'a5a5aaaa-0000-0000-0000-000000000003'),
  ('d pub',  'a5a5aaaa-0000-0000-0000-000000000004');

create temporary table share_routes (level text, id uuid);
insert into share_routes values
  ('a priv', 'a5a5bbbb-0000-0000-0000-000000000001'),
  ('b fol',  'a5a5bbbb-0000-0000-0000-000000000002'),
  ('c shr',  'a5a5bbbb-0000-0000-0000-000000000003'),
  ('d pub',  'a5a5bbbb-0000-0000-0000-000000000004');

create temporary table share_expected (who text, level text, visible boolean);
insert into share_expected values
  ('1 owner', 'a priv', true),  ('1 owner', 'b fol', true),  ('1 owner', 'c shr', true),  ('1 owner', 'd pub', true),
  ('2 recipient', 'a priv', false), ('2 recipient', 'b fol', false), ('2 recipient', 'c shr', true),  ('2 recipient', 'd pub', true),
  ('3 revoked', 'a priv', false), ('3 revoked', 'b fol', false), ('3 revoked', 'c shr', false), ('3 revoked', 'd pub', true),
  ('4 follower', 'a priv', false), ('4 follower', 'b fol', true),  ('4 follower', 'c shr', false), ('4 follower', 'd pub', true),
  ('5 stranger', 'a priv', false), ('5 stranger', 'b fol', false), ('5 stranger', 'c shr', false), ('5 stranger', 'd pub', true),
  ('6 anon', 'a priv', false), ('6 anon', 'b fol', false), ('6 anon', 'c shr', false), ('6 anon', 'd pub', true);

-- (10)
select results_eq(
  $$select v.who, e.level, private.is_run_visible_to(e.id, v.uid)
      from share_viewers v cross join share_runs e order by 1, 2$$,
  $$select who, level, visible from share_expected order by 1, 2$$,
  'run visibility: owner / recipient / revoked / follower / stranger / anon x private / followers / shared / public');

-- (11) photos follow the same audience (the coach tier stays out, § 98)
select results_eq(
  $$select v.who, e.level, private.is_run_photo_visible_to(e.id, v.uid)
      from share_viewers v cross join share_runs e order by 1, 2$$,
  $$select who, level, visible from share_expected order by 1, 2$$,
  'run photo visibility follows the same matrix');

-- (12)
select results_eq(
  $$select v.who, e.level, private.is_route_visible_to(e.id, v.uid)
      from share_viewers v cross join share_routes e order by 1, 2$$,
  $$select who, level, visible from share_expected order by 1, 2$$,
  'route visibility: owner / recipient / revoked / follower / stranger / anon x private / followers / shared / public');

-- ── The redacted non-owner row read: shared_runs / shared_routes ──
-- (13)
select is(
  (select array_agg(column_name::text order by ordinal_position)
     from information_schema.columns where table_schema = 'public' and table_name = 'shared_runs'),
  (select array_agg(column_name::text order by ordinal_position)
     from information_schema.columns where table_schema = 'public' and table_name = 'public_runs'),
  'shared_runs projects exactly the public_runs columns, so a recipient reads nothing a stranger could not');

-- (14)
select is(
  (select array_agg(column_name::text order by ordinal_position)
     from information_schema.columns where table_schema = 'public' and table_name = 'shared_routes'),
  (select array_agg(column_name::text order by ordinal_position)
     from information_schema.columns where table_schema = 'public' and table_name = 'public_routes'),
  'shared_routes projects exactly the public_routes columns');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"a5a50000-0000-0000-0000-00000000000b","role":"authenticated"}';

-- (15)
select results_eq(
  $$select id from shared_runs where user_id = 'a5a50000-0000-0000-0000-00000000000a'$$,
  $$values ('a5a5aaaa-0000-0000-0000-000000000003'::uuid)$$,
  'the recipient reads exactly the run shared with them through shared_runs');

-- (16)
select is(
  (select (metadata ? 'strava_id') or (metadata ? 'plan_workout_id')
     from shared_runs where id = 'a5a5aaaa-0000-0000-0000-000000000003'),
  false,
  'shared_runs strips the owner-only metadata keys public_runs strips');

-- (17)
select is(
  (select metadata ->> 'title' from shared_runs where id = 'a5a5aaaa-0000-0000-0000-000000000003'),
  'Shared tempo',
  'shared_runs keeps the public-safe metadata');

-- (18)
select results_eq(
  $$select id from shared_routes where user_id = 'a5a50000-0000-0000-0000-00000000000a'$$,
  $$values ('a5a5bbbb-0000-0000-0000-000000000003'::uuid)$$,
  'the recipient reads exactly the route shared with them through shared_routes');

-- (19) the clipped-track rule: the recipient gets the polyline minus the zone
select is(
  jsonb_array_length(clip_route_for_viewer('a5a5bbbb-0000-0000-0000-000000000003')),
  2,
  'a named recipient gets the route clipped to the owner''s privacy zone');

-- (20) the raw bytes stay owner-only: shared_runs carries no track path
select is(
  (select count(*)::int from information_schema.columns
    where table_schema = 'public' and table_name = 'shared_runs'
      and column_name in ('track_url', 'hr_series_url', 'external_id', 'notes')),
  0,
  'shared_runs carries no track path, HR series path, external id or notes');

-- (21)
select is(
  (select count(*)::int from shared_runs where id = 'a5a5aaaa-0000-0000-0000-000000000004'),
  0,
  'a public run is not in shared_runs; its readers keep public_runs');

set local "request.jwt.claims" = '{"sub":"a5a50000-0000-0000-0000-00000000000c","role":"authenticated"}';

-- (22)
select is(
  (select count(*)::int from shared_runs where id = 'a5a5aaaa-0000-0000-0000-000000000003'),
  0,
  'a revoked recipient cannot see the run in shared_runs');

-- (23)
select throws_ok(
  $$select clip_route_for_viewer('a5a5bbbb-0000-0000-0000-000000000003')$$,
  '42501', null,
  'a revoked recipient is refused the route polyline');

set local "request.jwt.claims" = '{"sub":"a5a50000-0000-0000-0000-00000000000d","role":"authenticated"}';

-- (24)
select results_eq(
  $$select id from shared_runs where user_id = 'a5a50000-0000-0000-0000-00000000000a'$$,
  $$values ('a5a5aaaa-0000-0000-0000-000000000002'::uuid)$$,
  'a follower reads exactly the followers-only run through shared_runs');

-- (25)
select is(
  jsonb_array_length(clip_route_for_viewer('a5a5bbbb-0000-0000-0000-000000000002')),
  2,
  'a follower gets the followers-only route clipped to the owner''s privacy zone');

set local "request.jwt.claims" = '{"sub":"a5a50000-0000-0000-0000-00000000000e","role":"authenticated"}';

-- (26)
select is(
  (select count(*)::int from shared_runs where user_id = 'a5a50000-0000-0000-0000-00000000000a'),
  0,
  'a stranger cannot see any of the owner''s runs in shared_runs');

-- (27)
select is(
  (select count(*)::int from shared_routes where user_id = 'a5a50000-0000-0000-0000-00000000000a'),
  0,
  'a stranger cannot see any of the owner''s routes in shared_routes');

-- (28)
select throws_ok(
  $$select clip_route_for_viewer('a5a5bbbb-0000-0000-0000-000000000002')$$,
  '42501', null,
  'a stranger is refused a followers-only route polyline');

set local "request.jwt.claims" = '{"sub":"a5a50000-0000-0000-0000-00000000000a","role":"authenticated"}';

-- (29)
select is(
  jsonb_array_length(clip_route_for_viewer('a5a5bbbb-0000-0000-0000-000000000003')),
  3,
  'the owner still gets the unclipped route');

-- (30)
select is(
  (select count(*)::int from shared_runs where user_id = 'a5a50000-0000-0000-0000-00000000000a'),
  0,
  'the owner''s own runs are not in shared_runs; the owner reads runs');

set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';

-- (31)
select throws_ok(
  $$select clip_route_for_viewer('a5a5bbbb-0000-0000-0000-000000000003')$$,
  '42501', null,
  'anon is refused a shared route polyline');

-- (32)
select throws_ok(
  $$select count(*) from shared_runs$$,
  '42501', null,
  'anon holds no privilege on shared_runs');

reset role;

-- ── Never broadcast: feeds and notifications key on is_public ──
-- (33)
select is(
  (select count(*)::int from public_runs
    where id in ('a5a5aaaa-0000-0000-0000-000000000002', 'a5a5aaaa-0000-0000-0000-000000000003')),
  0,
  'public_runs (feeds, profiles, the share page) carries neither the followers-only nor the shared run');

insert into runs (id, user_id, started_at, distance_m, duration_s, source, is_public, followers_only, metadata)
values
  ('a5a5aaaa-0000-0000-0000-000000000005', 'a5a50000-0000-0000-0000-00000000000a',
   now() - interval '1 hour', 5000, 1500, 'app', false, true, '{"activity_type":"run"}'),
  ('a5a5aaaa-0000-0000-0000-000000000006', 'a5a50000-0000-0000-0000-00000000000a',
   now() - interval '1 hour', 5000, 1500, 'app', true, false, '{"activity_type":"run"}');

-- (34) positive control: the same follower IS notified of a fresh public run
select is(
  (select count(*)::int from notifications
    where user_id = 'a5a50000-0000-0000-0000-00000000000d'
      and kind = 'run_completed' and run_id = 'a5a5aaaa-0000-0000-0000-000000000006'),
  1,
  'a fresh public run notifies the follower');

-- (35)
select is(
  (select count(*)::int from notifications
    where user_id = 'a5a50000-0000-0000-0000-00000000000d'
      and kind = 'run_completed' and run_id = 'a5a5aaaa-0000-0000-0000-000000000005'),
  0,
  'a fresh followers-only run sends the follower no run_completed notification');

-- ── Level coherence ──
update runs set is_public = true where id = 'a5a5aaaa-0000-0000-0000-000000000005';

-- (36)
select is(
  (select followers_only from runs where id = 'a5a5aaaa-0000-0000-0000-000000000005'),
  false,
  'flipping a followers-only run public clears followers_only (is_public wins)');

-- ── A block silences the followers level ──
insert into user_blocks (blocker_id, blocked_id)
values ('a5a50000-0000-0000-0000-00000000000a', 'a5a50000-0000-0000-0000-00000000000d');

-- (37)
select is(
  private.is_run_visible_to('a5a5aaaa-0000-0000-0000-000000000002', 'a5a50000-0000-0000-0000-00000000000d'),
  false,
  'a follower the owner blocked loses the followers-only run');

-- ── A shadow-hidden route leaves its audience ──
update routes set shadow_hidden = true where id = 'a5a5bbbb-0000-0000-0000-000000000003';

-- (38)
select is(
  private.is_route_visible_to('a5a5bbbb-0000-0000-0000-000000000003', 'a5a50000-0000-0000-0000-00000000000b'),
  false,
  'a shadow-hidden route is withheld from its named recipient');

-- ── The prod gate: with the flag off nothing widens ──
-- The block and the hide are lifted first, so every cell below is one the
-- matrix (10) / (12) showed admitted with the flag on.
delete from user_blocks where blocker_id = 'a5a50000-0000-0000-0000-00000000000a';
update routes set shadow_hidden = false where id = 'a5a5bbbb-0000-0000-0000-000000000003';
update private.feature_flags set enabled = false where name = 'audience_sharing';

-- (39)
select results_eq(
  $$select private.is_run_visible_to('a5a5aaaa-0000-0000-0000-000000000003', 'a5a50000-0000-0000-0000-00000000000b'),
           private.is_route_visible_to('a5a5bbbb-0000-0000-0000-000000000003', 'a5a50000-0000-0000-0000-00000000000b'),
           private.is_run_visible_to('a5a5aaaa-0000-0000-0000-000000000002', 'a5a50000-0000-0000-0000-00000000000d'),
           private.is_route_visible_to('a5a5bbbb-0000-0000-0000-000000000002', 'a5a50000-0000-0000-0000-00000000000d')$$,
  $$values (false, false, false, false)$$,
  'with audience sharing off a live grant and the followers level read as private');

insert into runs (id, user_id, started_at, distance_m, duration_s, source, is_public, followers_only, metadata)
values ('a5a5aaaa-0000-0000-0000-000000000007', 'a5a50000-0000-0000-0000-00000000000a',
        now() - interval '30 days', 5000, 1500, 'app', false, true, '{"activity_type":"run"}');

-- (40)
select is(
  (select followers_only from runs where id = 'a5a5aaaa-0000-0000-0000-000000000007'),
  false,
  'with audience sharing off a followers-only write is stored private, so nothing widens when the flag flips');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"a5a50000-0000-0000-0000-00000000000a","role":"authenticated"}';

-- (41)
select throws_ok(
  $$insert into run_shares (run_id, owner_id, recipient_id) values
      ('a5a5aaaa-0000-0000-0000-000000000001', 'a5a50000-0000-0000-0000-00000000000a', 'a5a50000-0000-0000-0000-00000000000b')$$,
  '42501', null,
  'with audience sharing off a new grant is refused');

select * from finish();
rollback;
