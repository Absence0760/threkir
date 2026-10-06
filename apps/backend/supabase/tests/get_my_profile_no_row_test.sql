-- Pin get_my_profile()'s empty case (migration 20270715000001, issue #1065).
--
-- A caller with no user_profiles row must get ZERO rows back. The old
-- `returns user_profiles` shape yielded one all-null row instead, which
-- PostgREST sent as an object of nulls: the mobile parser threw on `id`,
-- and both clients' "create the row when it is missing" bootstraps saw a
-- row and never created one.
--
-- Coverage:
--   1. A caller with a row gets exactly that one row.
--   2. A caller with no row gets no rows — not one row of nulls.
--   3. That caller can create its own default row with a plain insert
--      (the web + mobile bootstrap; an upsert is refused because
--      ON CONFLICT DO UPDATE needs SELECT on the locked-down columns)...
--   4. ...and then reads exactly that row back.
--   5. anon still cannot execute it (the drop/recreate reset the ACL).
--   6. The function is still SECURITY DEFINER with a pinned search_path.

begin;

select plan(6);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-00000000ee01', 'authenticated', 'authenticated',
   'has-row@profile.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000000ee02', 'authenticated', 'authenticated',
   'no-row@profile.local', '', now(), now());

set local role service_role;

insert into user_profiles (id, display_name)
values ('00000000-0000-0000-0000-00000000ee01', 'Has Row');

set local role authenticated;

-- 1. The row's owner reads exactly one row.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000ee01","role":"authenticated"}';
select results_eq(
  $$ select id, display_name from get_my_profile() $$,
  $$ values ('00000000-0000-0000-0000-00000000ee01'::uuid, 'Has Row'::text) $$,
  'a caller with a profile row reads exactly that row'
);

-- 2. A caller with no row reads nothing.
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000000ee02","role":"authenticated"}';
select is_empty(
  $$ select * from get_my_profile() $$,
  'a caller with no profile row reads zero rows, not a row of nulls'
);

-- 3-4. The client bootstrap's plain insert lands, and the row reads back.
select lives_ok(
  $$ insert into user_profiles (id, preferred_unit, subscription_tier)
     values ('00000000-0000-0000-0000-00000000ee02', 'km', 'free') $$,
  'a caller with no row can create its own default row with a plain insert'
);
select results_eq(
  $$ select id, subscription_tier from get_my_profile() $$,
  $$ values ('00000000-0000-0000-0000-00000000ee02'::uuid, 'free'::text) $$,
  'the bootstrapped row is the one get_my_profile() now returns'
);

reset role;

-- 5. anon cannot execute it.
select ok(
  not has_function_privilege('anon', 'public.get_my_profile()', 'execute'),
  'anon cannot execute get_my_profile()'
);

-- 6. Still a SECURITY DEFINER self-read with a pinned search_path.
select ok(
  (select p.prosecdef and p.proconfig @> array['search_path=public']
     from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'get_my_profile'),
  'get_my_profile() is SECURITY DEFINER with search_path pinned to public'
);

select * from finish();

rollback;
