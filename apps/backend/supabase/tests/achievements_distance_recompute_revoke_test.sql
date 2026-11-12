-- Pins migration 20270719000002_achievements_revoke_on_distance_recompute.sql:
-- the distance_recompute worker's write (distance_m and
-- metadata.distance_recomputed_at changing together) takes back the distance
-- tiers the corrected figure no longer earns, an ordinary distance edit does
-- not, a still-met lifetime tier and every non-distance family survive, the
-- award trigger that follows re-grants a lower tier still met, the revoked
-- badge's notification goes with it, and neither new function is callable by
-- a client role.
--
-- User A: a 5.2 km run (distance_single bronze) plus a 100 km ride, which
-- counts toward lifetime (distance_lifetime bronze, 105.2 km) but not toward
-- the single-run family. A hand-inserted streak row stands in for "a family
-- the revoker must not touch" — it is not earned by A's runs at all, so a
-- revoker that ignored the family filter would delete it.
-- User B: a 21.5 km run earns distance_single silver only (the awarder
-- inserts the top tier), so a recompute to 20 km must leave B holding bronze.

begin;
select plan(17);

-- ── shape ────────────────────────────────────────────────────────────────

select is(
  (select p.prosecdef from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'revoke_unmet_distance_achievements'),
  true,
  'revoke_unmet_distance_achievements is SECURITY DEFINER');

select ok(
  (select 'search_path=public' = any(p.proconfig) from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'revoke_unmet_distance_achievements'),
  'revoke_unmet_distance_achievements pins search_path');

select ok(
  not has_function_privilege('anon', 'public.revoke_unmet_distance_achievements(uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.revoke_unmet_distance_achievements(uuid)', 'EXECUTE'),
  'neither anon nor authenticated may execute revoke_unmet_distance_achievements');

select ok(
  not has_function_privilege('anon', 'public.achievement_tiers_met(uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.achievement_tiers_met(uuid)', 'EXECUTE'),
  'neither anon nor authenticated may execute achievement_tiers_met');

-- ── fixtures ─────────────────────────────────────────────────────────────

insert into auth.users (id, email, encrypted_password, email_confirmed_at,
                        instance_id, aud, role)
values
  ('ad000000-0000-0000-0000-0000000000a1', 'ach-recompute-a@test.local', '', now(),
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('ad000000-0000-0000-0000-0000000000b2', 'ach-recompute-b@test.local', '', now(),
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated');

insert into runs (id, user_id, started_at, distance_m, duration_s, source,
                  activity_type, metadata)
values
  ('ad000001-0000-0000-0000-000000000001', 'ad000000-0000-0000-0000-0000000000a1',
   '2026-09-01 09:00:00+00', 5200, 1800, 'app', 'run', '{"activity_type":"run"}'),
  ('ad000001-0000-0000-0000-000000000002', 'ad000000-0000-0000-0000-0000000000a1',
   '2026-09-03 09:00:00+00', 100000, 14400, 'app', 'cycle', '{"activity_type":"cycle"}'),
  ('ad000001-0000-0000-0000-000000000003', 'ad000000-0000-0000-0000-0000000000b2',
   '2026-09-01 09:00:00+00', 21500, 7200, 'app', 'run', '{"activity_type":"run"}');

insert into achievements (user_id, badge_key, tier, source_kind, value_num)
values ('ad000000-0000-0000-0000-0000000000a1', 'streak', 'bronze', 'streak', 7);

select ok(
  exists (select 1 from achievements
           where user_id = 'ad000000-0000-0000-0000-0000000000a1'
             and badge_key = 'distance_single' and tier = 'bronze'),
  'a 5.2 km run earns the distance_single bronze (5k) badge');

select ok(
  exists (select 1 from achievements
           where user_id = 'ad000000-0000-0000-0000-0000000000a1'
             and badge_key = 'distance_lifetime' and tier = 'bronze'),
  'a 5.2 km run plus a 100 km ride earns the distance_lifetime bronze badge');

-- ── an ordinary distance edit never revokes ──────────────────────────────

update runs set distance_m = 4900
 where id = 'ad000001-0000-0000-0000-000000000001';

select ok(
  exists (select 1 from achievements
           where user_id = 'ad000000-0000-0000-0000-0000000000a1'
             and badge_key = 'distance_single' and tier = 'bronze'),
  'an ordinary distance edit to 4.9 km (no distance_recomputed_at) keeps the 5k badge');

update runs set distance_m = 5200
 where id = 'ad000001-0000-0000-0000-000000000001';

-- A metadata-only stamp with no distance change is not the recompute write.
update runs set metadata = metadata || '{"distance_recomputed_at":"2026-10-01T00:00:00Z"}'::jsonb
 where id = 'ad000001-0000-0000-0000-000000000001';

select ok(
  exists (select 1 from achievements
           where user_id = 'ad000000-0000-0000-0000-0000000000a1'
             and badge_key = 'distance_single' and tier = 'bronze'),
  'stamping distance_recomputed_at without a distance change revokes nothing');

-- ── the recompute write revokes what the corrected distance no longer earns ─

select set_config('test.a_5k_notification',
  coalesce((select n.id::text from notifications n
     join achievements a on a.id = n.achievement_id
    where a.user_id = 'ad000000-0000-0000-0000-0000000000a1'
      and a.badge_key = 'distance_single' and a.tier = 'bronze'), ''),
  true);

update runs
   set distance_m = 4900,
       metadata = metadata || jsonb_build_object(
         'distance_recorded_m', 5200,
         'distance_estimator', 'kalman_v1',
         'distance_recomputed_at', '2026-10-08T12:00:00Z')
 where id = 'ad000001-0000-0000-0000-000000000001';

select ok(current_setting('test.a_5k_notification') <> '',
  'the 5k award had its achievement notification before the recompute');

select ok(
  not exists (select 1 from achievements
               where user_id = 'ad000000-0000-0000-0000-0000000000a1'
                 and badge_key = 'distance_single'),
  'the recompute write lowering 5.2 km to 4.9 km revokes the 5k badge');

select ok(
  not exists (select 1 from notifications
               where id::text = current_setting('test.a_5k_notification')),
  'the revoked badge''s notification is removed, not left dangling');

select ok(
  exists (select 1 from achievements
           where user_id = 'ad000000-0000-0000-0000-0000000000a1'
             and badge_key = 'distance_lifetime' and tier = 'bronze'),
  'a lifetime tier still met (104.9 km) is kept');

select ok(
  exists (select 1 from achievements
           where user_id = 'ad000000-0000-0000-0000-0000000000a1'
             and badge_key = 'streak' and tier = 'bronze'),
  'a non-distance family is untouched by the revoke');

-- ── a lower tier still met is re-granted by the award that follows ──────

select ok(
  exists (select 1 from achievements
           where user_id = 'ad000000-0000-0000-0000-0000000000b2'
             and badge_key = 'distance_single' and tier = 'silver')
  and not exists (select 1 from achievements
                   where user_id = 'ad000000-0000-0000-0000-0000000000b2'
                     and badge_key = 'distance_single' and tier = 'bronze'),
  'a 21.5 km run is awarded the top tier (silver) only');

update runs
   set distance_m = 20000,
       metadata = metadata || '{"distance_recomputed_at":"2026-10-08T12:00:00Z"}'::jsonb
 where id = 'ad000001-0000-0000-0000-000000000003';

select ok(
  not exists (select 1 from achievements
               where user_id = 'ad000000-0000-0000-0000-0000000000b2'
                 and badge_key = 'distance_single' and tier = 'silver'),
  'a recompute to 20 km revokes the half-marathon silver');

select ok(
  exists (select 1 from achievements
           where user_id = 'ad000000-0000-0000-0000-0000000000b2'
             and badge_key = 'distance_single' and tier = 'bronze'),
  'the award trigger after the revoke grants the bronze the corrected run still earns');

-- ── a direct call at trigger depth 0 from a client role is refused ───────

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"ad000000-0000-0000-0000-0000000000a1","role":"authenticated"}', true);
select throws_ok(
  $$select revoke_unmet_distance_achievements('ad000000-0000-0000-0000-0000000000b2')$$,
  '42501',
  null,
  'a signed-in caller cannot invoke the revoker against anyone');
reset role;

select * from finish();
rollback;
