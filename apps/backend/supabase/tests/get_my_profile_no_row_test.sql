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
--   3. anon still cannot execute it (the drop/recreate reset the ACL).
--   4. The function is still SECURITY DEFINER with a pinned search_path.

begin;

select plan(4);

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

reset role;

-- 3. anon cannot execute it.
select ok(
  not has_function_privilege('anon', 'public.get_my_profile()', 'execute'),
  'anon cannot execute get_my_profile()'
);

-- 4. Still a SECURITY DEFINER self-read with a pinned search_path.
select ok(
  (select p.prosecdef and p.proconfig @> array['search_path=public']
     from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'get_my_profile'),
  'get_my_profile() is SECURITY DEFINER with search_path pinned to public'
);

select * from finish();

rollback;
