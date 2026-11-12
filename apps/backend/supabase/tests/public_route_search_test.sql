-- Public route search reads the `public_routes` view by keyset cursor
-- (decisions § 1934) and matches its text through an escaped `~*` regex
-- (§ 1935); the offset-paged search_public_routes RPC it replaced is dropped
-- (20270817000001). This pins what the clients now depend on: the function is
-- gone, anon can still read the view, the view still hides shadow-hidden and
-- private routes, the partial sort indexes 20270326_001 built still serve the
-- order's prefix, and an escaped pattern matches its text literally.
--
-- The fixture tag scopes every read to these rows only.

begin;

select plan(10);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000326aa', 'authenticated', 'authenticated',
   'owner@sort.local', '', now(), now());

insert into routes
  (id, user_id, name, waypoints, distance_m, is_public, tags,
   run_count, created_at, is_featured, featured_at, shadow_hidden)
values
  ('03260326-0326-0326-0326-0326032603a1', '00000000-0000-0000-0000-0000000326aa',
   'Loop 5*5', '[]'::jsonb, 5000, true, array['sorttest0326'],
   10, '2026-01-01T00:00:00Z', false, null, false),
  ('03260326-0326-0326-0326-0326032603a2', '00000000-0000-0000-0000-0000000326aa',
   'Loop 5555', '[]'::jsonb, 5000, true, array['sorttest0326'],
   10, '2026-01-01T00:00:00Z', false, null, false),
  ('03260326-0326-0326-0326-0326032603a3', '00000000-0000-0000-0000-0000000326aa',
   'Loop a_b (100%)', '[]'::jsonb, 5000, true, array['sorttest0326'],
   5, '2026-03-01T00:00:00Z', false, null, false),
  ('03260326-0326-0326-0326-0326032603a4', '00000000-0000-0000-0000-0000000326aa',
   'Loop axb 1000', '[]'::jsonb, 5000, true, array['sorttest0326'],
   0, '2026-04-01T00:00:00Z', false, null, false),
  ('03260326-0326-0326-0326-0326032603a6', '00000000-0000-0000-0000-0000000326aa',
   'Loop shadow', '[]'::jsonb, 5000, true, array['sorttest0326'],
   99, '2026-06-01T00:00:00Z', false, null, true),
  ('03260326-0326-0326-0326-0326032603a7', '00000000-0000-0000-0000-0000000326aa',
   'Loop private', '[]'::jsonb, 5000, false, array['sorttest0326'],
   98, '2026-06-02T00:00:00Z', false, null, false);

select ok(
  not exists (select 1 from pg_proc p
              join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public' and p.proname = 'search_public_routes'),
  'search_public_routes is dropped');

select ok(
  has_table_privilege('anon', 'public.public_routes', 'select'),
  'anon can read public_routes, which logged-out route search now queries');

select ok(
  not exists (select 1 from public_routes
              where id in ('03260326-0326-0326-0326-0326032603a6',
                           '03260326-0326-0326-0326-0326032603a7')),
  'shadow-hidden and private routes stay out of the view');

-- `5\*5` is what literalSubstringPattern sends for "5*5". The same two rows
-- share created_at, so the order below needs its `id desc` tie-break.
select results_eq(
  $q$ select id from public_routes
      where tags && array['sorttest0326'] and name ~* '5\*5'
      order by created_at desc nulls last, id desc $q$,
  array['03260326-0326-0326-0326-0326032603a1']::uuid[],
  'an escaped * matches only a literal asterisk');

select results_eq(
  $q$ select id from public_routes
      where tags && array['sorttest0326'] and name ~* 'A_B \(100%\)'
      order by created_at desc nulls last, id desc $q$,
  array['03260326-0326-0326-0326-0326032603a3']::uuid[],
  '_ % and escaped parentheses match literally and case-insensitively');

select results_eq(
  $q$ select id from public_routes
      where tags && array['sorttest0326']
      order by run_count desc nulls last, created_at desc nulls first, id desc $q$,
  array[
    '03260326-0326-0326-0326-0326032603a2',
    '03260326-0326-0326-0326-0326032603a1',
    '03260326-0326-0326-0326-0326032603a3',
    '03260326-0326-0326-0326-0326032603a4'
  ]::uuid[],
  'popular: equal run_count and created_at fall back to id desc');

select ok(
  exists (select 1 from pg_indexes
          where schemaname = 'public'
            and indexname in ('routes_public_popular_sort',
                              'routes_public_featured_sort',
                              'routes_public_newest_sort')
          having count(*) = 3),
  'the three partial sort indexes survive the function drop');

select ok(
  (select count(*) = 3 from pg_indexes
   where indexname in ('routes_public_popular_sort',
                       'routes_public_featured_sort',
                       'routes_public_newest_sort')
     and indexdef like '%is_public = true%'
     and indexdef like '%shadow_hidden = false%'),
  'each sort index is partial on the public_routes visibility predicate');

-- Issue #407: the pre-F17 routes_featured partial index was superseded by
-- routes_public_featured_sort and dropped in 20270423000002.
select ok(
  not exists (select 1 from pg_indexes
              where schemaname = 'public' and indexname = 'routes_featured'),
  'the superseded routes_featured index is gone');

select ok(
  exists (select 1 from pg_indexes
          where schemaname = 'public'
            and indexname = 'routes_public_featured_sort'),
  'the replacement routes_public_featured_sort index remains');

select * from finish();

rollback;
