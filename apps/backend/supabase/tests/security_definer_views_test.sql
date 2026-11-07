-- Pins the set of views in the app schemas (public, private) that run as
-- their owner rather than the caller. Each one is a Supabase advisor
-- "Security Definer View" finding, accepted by decisions § 244 and § 2351
-- because the view is the redaction layer and the only read path to rows
-- whose base tables are owner-only: the public_* views pre-filter
-- is_public = true, and shared_runs / shared_routes / coached_runs carry
-- their own auth.uid() audience or coach-link predicate. A new view that
-- leaves security_invoker off fails here until a decision names it, instead
-- of surfacing first as a CRITICAL on the prod dashboard. Postgres stores
-- the option value as written, so on / true / yes / 1 all count as invoker.

begin;

select plan(1);

select is(
  (select coalesce(string_agg(n.nspname || '.' || c.relname, ', '
                              order by n.nspname, c.relname), '')
     from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname in ('public', 'private')
      and c.relkind in ('v', 'm')
      and not exists (
        select 1 from pg_depend d
        where d.objid = c.oid and d.deptype = 'e'
      )
      and not exists (
        select 1 from unnest(coalesce(c.reloptions, '{}')) opt
        where lower(opt) in ('security_invoker=true', 'security_invoker=on',
                             'security_invoker=yes', 'security_invoker=1')
      )),
  'public.coached_runs, public.public_food_log, public.public_gym_routines, '
  'public.public_gym_sets, public.public_gym_workouts, public.public_profiles, '
  'public.public_race_listings, public.public_routes, public.public_runs, '
  'public.shared_routes, public.shared_runs',
  'exactly the eleven accepted views run as their owner; any other view sets '
  'security_invoker = true or is recorded in decisions.md first'
);

select * from finish();
rollback;
