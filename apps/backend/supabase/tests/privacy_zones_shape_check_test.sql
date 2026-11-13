-- pgtap: a stored privacy-zone list must be a list of points (migration
-- 20271226031374, issue #1374 round 4). privacy_in_any_zone reads a
-- non-array as "no zones", so the shape is refused on the way in.

begin;

select plan(6);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('00000000-0000-0000-0000-00000000f301', 'authenticated', 'authenticated',
        'shape@zone.local', '', now(), now());

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000f301","role":"authenticated"}';

select lives_ok(
  $$ insert into user_settings (user_id, prefs)
     values ('00000000-0000-0000-0000-00000000f301',
             '{"privacy_zones":[{"lat":47.37,"lng":8.54,"radius_m":200}]}'::jsonb) $$,
  'a list of points is accepted'
);

select throws_ok(
  $$ update user_settings set prefs = jsonb_set(prefs, '{privacy_zones}', '{"lat":47.37,"lng":8.54}')
      where user_id = '00000000-0000-0000-0000-00000000f301' $$,
  '22023',
  null,
  'a single object instead of a list is refused'
);

select throws_ok(
  $$ update user_settings set prefs = jsonb_set(prefs, '{privacy_zones}', '[{"lat":"47.37","lng":8.54}]')
      where user_id = '00000000-0000-0000-0000-00000000f301' $$,
  '22023',
  null,
  'a zone with a non-numeric latitude is refused'
);

select throws_ok(
  $$ update user_settings set prefs = jsonb_set(prefs, '{privacy_zones}', '[{"lat":47.37,"lng":8.54,"radius_m":"big"}]')
      where user_id = '00000000-0000-0000-0000-00000000f301' $$,
  '22023',
  null,
  'a zone with a non-numeric radius is refused'
);

select lives_ok(
  $$ update user_settings set prefs = prefs - 'privacy_zones'
      where user_id = '00000000-0000-0000-0000-00000000f301' $$,
  'removing the zones is accepted'
);

reset role;
select is(
  (select prefs ? 'privacy_zones' from user_settings
    where user_id = '00000000-0000-0000-0000-00000000f301'),
  false,
  'the refused writes left nothing behind and the removal landed'
);

select * from finish();
rollback;
