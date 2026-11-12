-- pgtap suite for the routes.tags set invariant (migrations 20270816000011 +
-- 20270816000012).
--
-- `routes.tags` is rendered by the web in keyed `{#each … (t)}` blocks, so one
-- stored duplicate throws Svelte's each_key_duplicate and takes the page into
-- the 500 boundary. Only the web tag editor deduped; the restores, mobile
-- `saveRoute` and a direct PostgREST PATCH stored whatever they were handed.
--
-- Covers:
--   * the canonical form: NULLs dropped, first occurrence kept, exact equality
--   * an owner's INSERT and UPDATE carrying duplicates are normalised, not
--     refused — which also proves `authenticated` may evaluate the CHECK, since
--     a CHECK naming a function ACL-checks it against the writing role
--   * a write that bypasses triggers is refused by the CHECK
--   * the CHECK is validated, not left NOT VALID

begin;

select plan(7);

-- ── The canonical form ──────────────────────────────────────────────────────

select is(
  private.distinct_text_array(array['trail', 'hills', 'trail', null, 'hills', 'loop']),
  array['trail', 'hills', 'loop'],
  'duplicates and NULLs are dropped, each value kept at its first position'
);

select is(
  private.distinct_text_array(array['Trail', 'trail']),
  array['Trail', 'trail'],
  'equality is exact: values differing only in case are distinct'
);

select is(
  private.distinct_text_array('{}'::text[]),
  '{}'::text[],
  'the empty array is its own canonical form'
);

-- ── Every write path through the trigger ────────────────────────────────────

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('00000000-0000-0000-0000-0000000d7a01', 'authenticated', 'authenticated',
        'tags@route.local', '', now(), now());

select tests.confirm_consent();

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000d7a01"}';

insert into routes (id, user_id, name, waypoints, distance_m, tags)
values ('11111111-1111-1111-1111-1111110d7a01',
        '00000000-0000-0000-0000-0000000d7a01',
        'Tagged Loop',
        '[{"lat":47.37,"lng":8.54},{"lat":47.38,"lng":8.55}]',
        5000,
        array['hills', 'trail', 'hills']);

select is(
  (select tags from routes where id = '11111111-1111-1111-1111-1111110d7a01'),
  array['hills', 'trail'],
  'an owner INSERT carrying a duplicate tag stores the set'
);

update routes
set tags = array['loop', 'loop', 'hills', 'loop']
where id = '11111111-1111-1111-1111-1111110d7a01';

select is(
  (select tags from routes where id = '11111111-1111-1111-1111-1111110d7a01'),
  array['loop', 'hills'],
  'an owner UPDATE carrying duplicate tags stores the set'
);

-- ── The floor under the trigger ─────────────────────────────────────────────

reset role;
set local session_replication_role = replica;

select throws_ok(
  $$ update routes set tags = array['loop', 'loop']
     where id = '11111111-1111-1111-1111-1111110d7a01' $$,
  '23514',
  null,
  'a write that bypasses triggers cannot store a duplicate tag'
);

set local session_replication_role = origin;

select is(
  (select convalidated from pg_constraint
   where conrelid = 'public.routes'::regclass
     and conname = 'routes_tags_distinct_check'),
  true,
  'routes_tags_distinct_check is validated'
);

select * from finish();

rollback;
