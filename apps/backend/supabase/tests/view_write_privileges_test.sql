-- Pins migration 20270324_001 (view write lockdown). Two layers:
--
--   1. A catch-all over information_schema: NO view in the public schema may
--      grant anon/authenticated anything beyond SELECT. Supabase's default
--      privileges hand out full table privileges on CREATE, and a simple
--      view is auto-updatable with writes authorised as the VIEW OWNER
--      (postgres, bypassing RLS) — so a future view created without the
--      revoke-then-grant reset fails HERE instead of shipping writable.
--   2. A functional probe on the shape that was exploitable: an anon insert
--      through an auto-updatable view is denied by the privilege. The probe
--      used to target public_race_listings, the view the exploit went
--      through, but 20270924000002 joined it to public_routes, and a view
--      that is not auto-updatable refuses an insert in the rewriter (55000)
--      before any privilege is consulted, so it no longer measured the
--      revoke. The probe now targets public_routes, still a single-table
--      view, and public_race_listings keeps a direct privilege assertion.

begin;

select plan(4);

select is(
  (select count(*)::int
     from information_schema.role_table_grants g
     join information_schema.views v
       on v.table_schema = g.table_schema and v.table_name = g.table_name
     where g.table_schema = 'public'
       and g.grantee in ('anon', 'authenticated')
       and g.privilege_type <> 'SELECT'),
  0,
  'no public-schema view grants anon/authenticated anything beyond SELECT — '
  'writes through an auto-updatable view run as the view owner and bypass RLS'
);

set local role anon;
set local "request.jwt.claims" = '{}';

select ok(
  not has_table_privilege('anon', 'public.public_race_listings', 'INSERT'),
  'anon holds no INSERT privilege on public_race_listings'
);

select throws_ok(
  $$ insert into public_routes (id, name)
     values (gen_random_uuid(), 'Forged Via View') $$,
  '42501',
  null,
  'anon cannot INSERT through the auto-updatable public_routes'
);

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}';

select throws_ok(
  $$ insert into public_gym_workouts (id, user_id, started_at, is_public)
     values (gen_random_uuid(), '00000000-0000-0000-0000-000000000001', now(), true) $$,
  '42501',
  null,
  'authenticated cannot INSERT through public_gym_workouts'
);

select * from finish();
rollback;
