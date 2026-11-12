-- Pins migrations 20270415_001 and 20271110000002 (function search_path
-- pins). Catch-all over pg_proc: EVERY function in an app-owned schema
-- (public and private) must carry a pinned search_path in proconfig, so a
-- future migration can't ship a function whose unqualified references
-- resolve against the caller's mutable session search_path (Supabase advisor
-- lint 0011). The advisor reads every non-system schema, so a test that read
-- only public let two private helpers reach prod unpinned (decisions § 2351).
-- Extension-owned functions are excluded (none live in these schemas today,
-- but an extension update must not fail this suite). The failure message
-- names the offending functions.

begin;

select plan(1);

select is(
  (select coalesce(string_agg(n.nspname || '.' || p.proname, ', '
                              order by n.nspname, p.proname), '')
     from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
     where n.nspname in ('public', 'private')
       and p.prokind = 'f'
       and not exists (
         select 1 from pg_depend d
         where d.objid = p.oid and d.deptype = 'e'
       )
       and not exists (
         select 1 from unnest(coalesce(p.proconfig, '{}')) cfg
         where cfg like 'search_path=%'
       )),
  '',
  'every public- and private-schema function pins search_path — an unpinned '
  'function resolves unqualified references against the caller''s mutable '
  'search_path'
);

select * from finish();
rollback;
