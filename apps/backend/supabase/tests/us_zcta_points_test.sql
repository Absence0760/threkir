-- Pins migration 20270805000001 — the ZIP centroids race-listings-sync places
-- a provider race with (decisions § 1900).
--
-- The table is reference data read only by the service role: a client has no
-- reason to read 33,791 centroids, and none to write one, so neither app role
-- holds a grant and RLS stays on with no policy as the second rail.

begin;
select plan(6);

select is(
  (select count(*)::int from public.us_zcta_points),
  33791,
  'every 2024 Gazetteer ZCTA is loaded'
);

select results_eq(
  $$ select lat, lng from public.us_zcta_points where zcta = '48060' $$,
  $$ values (42.9836::double precision, -82.4583::double precision) $$,
  'a ZIP reads as its Census internal point (the fixture race in Port Huron, MI)'
);

select is(
  (select count(*)::int from public.us_zcta_points where zcta = '00000'),
  0,
  'a ZIP with no ZCTA has no row, so its race is written without a point'
);

select ok(
  not has_table_privilege('anon', 'public.us_zcta_points', 'SELECT')
    and not has_table_privilege('authenticated', 'public.us_zcta_points', 'SELECT')
    and not has_table_privilege('authenticated', 'public.us_zcta_points', 'INSERT'),
  'no app role can read or write the centroids'
);

select ok(
  has_table_privilege('service_role', 'public.us_zcta_points', 'SELECT'),
  'the sync, as the service role, can read them'
);

select results_eq(
  $$ select c.relrowsecurity, (select count(*)::int from pg_policy p where p.polrelid = c.oid)
       from pg_class c where c.oid = 'public.us_zcta_points'::regclass $$,
  $$ values (true, 0) $$,
  'RLS is on with no policy: there is no client read path to serve'
);

select * from finish();
rollback;
