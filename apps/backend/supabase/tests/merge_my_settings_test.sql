-- Atomic owner merges into the prefs bags: merge_my_settings +
-- merge_my_device_settings (migration 20271021000002_atomic_prefs_merge.sql,
-- issue #1212).
--
-- Pins:
--   * a merge sets the named keys and leaves every other key as the row holds
--     it NOW — not as the caller last read it, which is the lost update a
--     client-side read-merge-write produced.
--   * a JSON-null value removes the key (the clients' applyPrefsChanges rule).
--   * a missing row is created (the insert arm; platform is NOT NULL on the
--     device table).
--   * the write is auth.uid()-scoped.
--   * a non-object delta is refused rather than written.
--   * anon has no execute grant.

begin;

select plan(12);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('dddddddd-dddd-dddd-dddd-dddddddddd01', 'authenticated', 'authenticated', 'owner@mms.local', '', now(), now()),
  ('dddddddd-dddd-dddd-dddd-dddddddddd02', 'authenticated', 'authenticated', 'other@mms.local', '', now(), now());

insert into user_settings (user_id, prefs) values
  ('dddddddd-dddd-dddd-dddd-dddddddddd01',
   jsonb_build_object('body_weight_kg', 60, 'privacy_zones', jsonb_build_array(jsonb_build_object('lat', 1, 'lng', 2, 'radius_m', 200)))),
  ('dddddddd-dddd-dddd-dddd-dddddddddd02',
   jsonb_build_object('body_weight_kg', 90));

insert into user_device_settings (user_id, device_id, platform, prefs) values
  ('dddddddd-dddd-dddd-dddd-dddddddddd01', 'device-mms', 'web',
   jsonb_build_object('theme', 'dark', 'keep_screen_on', true));

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"dddddddd-dddd-dddd-dddd-dddddddddd01","role":"authenticated"}';

-- 1-2. Two writers' deltas, applied one after the other, both survive: the
--      second merge applies to the bag the first left, not to a stale copy.
select merge_my_settings(jsonb_build_object('body_weight_kg', 81.5));
select merge_my_settings(jsonb_build_object('locale', 'en'));
select is(
  (select (prefs->>'body_weight_kg') || '/' || (prefs->>'locale')
     from user_settings where user_id = 'dddddddd-dddd-dddd-dddd-dddddddddd01'),
  '81.5/en', 'a later merge of another key keeps the earlier merge''s value');
select is(
  (select jsonb_array_length(prefs->'privacy_zones')
     from user_settings where user_id = 'dddddddd-dddd-dddd-dddd-dddddddddd01'),
  1, 'keys the delta does not name are left as the row holds them');

-- 3-4. A JSON null removes the key; the returned bag is the merged row.
select is(
  merge_my_settings(jsonb_build_object('locale', null, 'time_zone', 'UTC')) ? 'locale',
  false, 'the returned bag reflects the removal');
select is(
  (select (prefs ? 'locale')::text || '/' || (prefs->>'time_zone')
     from user_settings where user_id = 'dddddddd-dddd-dddd-dddd-dddddddddd01'),
  'false/UTC', 'a JSON-null value removes the key; the other key is set');

-- 5. Nested values are stored whole, not null-stripped.
select merge_my_settings(jsonb_build_object('hr_zones', jsonb_build_object('z1', null, 'z2', 140)));
select is(
  (select (prefs->'hr_zones') ? 'z1'
     from user_settings where user_id = 'dddddddd-dddd-dddd-dddd-dddddddddd01'),
  true, 'only top-level nulls remove; a nested null is part of the value');

-- 6. Another user's bag is untouched (read as superuser — RLS hides it).
reset role;
select is(
  (select prefs from user_settings where user_id = 'dddddddd-dddd-dddd-dddd-dddddddddd02'),
  jsonb_build_object('body_weight_kg', 90), 'the merge is auth.uid()-scoped');

-- 7. A user with no row gets one.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"dddddddd-dddd-dddd-dddd-dddddddddd02","role":"authenticated"}';
delete from user_settings where user_id = 'dddddddd-dddd-dddd-dddd-dddddddddd02';
select merge_my_settings(jsonb_build_object('weight_unit', 'kg', 'gone', null));
select is(
  (select prefs from user_settings where user_id = 'dddddddd-dddd-dddd-dddd-dddddddddd02'),
  jsonb_build_object('weight_unit', 'kg'), 'a missing row is created from the delta, nulls dropped');

-- 8. A non-object delta is refused.
select throws_ok(
  $$ select merge_my_settings('[1,2]'::jsonb) $$,
  '22023', null, 'a non-object delta is refused');

-- 9-10. Device bag: same merge, other per-device prefs survive.
set local "request.jwt.claims" = '{"sub":"dddddddd-dddd-dddd-dddd-dddddddddd01","role":"authenticated"}';
select merge_my_device_settings('device-mms', jsonb_build_object('theme', 'light', 'keep_screen_on', null), 'web');
select is(
  (select prefs from user_device_settings
    where user_id = 'dddddddd-dddd-dddd-dddd-dddddddddd01' and device_id = 'device-mms'),
  jsonb_build_object('theme', 'light'), 'device merge sets and removes per the delta');
select merge_my_device_settings('device-mms', jsonb_build_object('map_style', 'outdoors'), 'web');
select is(
  (select prefs->>'theme' from user_device_settings
    where user_id = 'dddddddd-dddd-dddd-dddd-dddddddddd01' and device_id = 'device-mms'),
  'light', 'device merge keeps keys the delta does not name');

-- 11. An unprovisioned device row is created with the caller's platform.
select merge_my_device_settings('device-fresh', jsonb_build_object('theme', 'dark'), 'android', 'Pixel');
select is(
  (select platform || '/' || label || '/' || (prefs->>'theme') from user_device_settings
    where user_id = 'dddddddd-dddd-dddd-dddd-dddddddddd01' and device_id = 'device-fresh'),
  'android/Pixel/dark', 'an unprovisioned device row is created with platform + label');

-- 12. anon has no execute grant.
set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';
select throws_ok(
  $$ select merge_my_settings('{}'::jsonb) $$,
  '42501', null, 'anon cannot execute merge_my_settings');

select * from finish();

rollback;
