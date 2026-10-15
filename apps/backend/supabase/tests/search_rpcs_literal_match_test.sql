-- Pins migration 20270817000031 (decisions § 1930): every text-search RPC
-- matches the typed term literally, through `private.like_escape`.
--
-- One fixture set of five names per searched table, all sharing the `Zqx`
-- token so seed rows never intrude:
--   'Zqx 50% Off' / 'Zqx 500 Off'   `%`  — a raw '%50%%' matches both
--   'Zqx a_b'     / 'Zqx aXb'       `_`  — a raw '%a_b%' matches both
--   'Zqx back\slash'                `\`  — a raw '%back\s%' means the literal
--                                          'backs'; a raw trailing `\` escapes
--                                          the closing `%`, so '%k\%' means
--                                          "ends in k%" and '%\%' means
--                                          "contains a percent sign"
-- Each function is asked for `50%`, `a_b`, `back\s`, `k\`, a lone `\`, and the
-- plain `Zqx`. Before the fix the first two return two names each, `back\s`
-- and `k\` return none, and a lone `\` returns 'Zqx 50% Off' instead of the
-- backslash name.
--
-- The SECURITY INVOKER functions (search_clubs, search_public_events,
-- search_race_listings) are called as anon, so the helper's EXECUTE grant to
-- every caller role is exercised too; search_user_profiles as authenticated
-- (anon is revoked); browse_public_challenges as anon.

begin;

select plan(36);

-- ── 1. the helper ───────────────────────────────────────────────────────────
select is(private.like_escape('a%b_c\d'), 'a\%b\_c\\d',
  'like_escape prefixes %, _ and \ with \');
select is(private.like_escape('\%'), '\\\%',
  'like_escape escapes the backslash first, so its own escapes are not doubled');
select is(private.like_escape('plain text'), 'plain text',
  'like_escape leaves text without metacharacters unchanged');
select is(private.like_escape(''), '', 'like_escape of the empty string is empty');
select is(private.like_escape(null), null::text, 'like_escape is strict: NULL in, NULL out');

-- ── fixtures (as the test superuser; no request claims, so the challenge
--    create rate limit is bypassed exactly as on the seed path) ──────────────
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-00000e5c0001', 'authenticated', 'authenticated', 'esc1@esc.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000e5c0002', 'authenticated', 'authenticated', 'esc2@esc.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000e5c0003', 'authenticated', 'authenticated', 'esc3@esc.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000e5c0004', 'authenticated', 'authenticated', 'esc4@esc.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000e5c0005', 'authenticated', 'authenticated', 'esc5@esc.local', '', now(), now()),
  ('00000000-0000-0000-0000-00000e5c0006', 'authenticated', 'authenticated', 'esc6@esc.local', '', now(), now());

create temporary table zqx_names (n int primary key, name text not null);
insert into zqx_names values
  (1, 'Zqx 50% Off'),
  (2, 'Zqx 500 Off'),
  (3, 'Zqx a_b'),
  (4, 'Zqx aXb'),
  (5, 'Zqx back\slash');

insert into user_profiles (id, display_name)
select ('00000000-0000-0000-0000-00000e5c000' || n)::uuid, name from zqx_names
on conflict (id) do update set display_name = excluded.display_name;

insert into clubs (id, owner_id, name, slug, is_public)
select ('cccccccc-0000-0000-0000-00000e5c000' || n)::uuid,
       '00000000-0000-0000-0000-00000e5c0006', name, 'zqx-esc-' || n, true
from zqx_names;

insert into events (id, club_id, author_id, title, category, starts_at)
select ('eeeeeeee-0000-0000-0000-00000e5c000' || n)::uuid,
       'cccccccc-0000-0000-0000-00000e5c0001',
       '00000000-0000-0000-0000-00000e5c0006', name, 'run', now() + interval '3 days'
from zqx_names;

insert into race_listings (id, provider, provider_race_id, name, race_date, distance_m)
select ('11111111-1111-1111-1111-11110e5c000' || n)::uuid,
       'manual', 'zqx-esc-' || n, name, current_date + 30, 10000
from zqx_names;

insert into challenges (id, creator_id, title, metric, scope, goal_value, starts_at, ends_at, is_public, created_at)
select ('bbbbbbbb-0000-0000-0000-00000e5c000' || n)::uuid,
       '00000000-0000-0000-0000-00000e5c0006', name, 'distance', 'individual', 100000,
       now() - interval '1 day', now() + interval '20 days', true, now()
from zqx_names;

-- The fixture names a search returns, sorted. Dynamic SQL runs as the current
-- role, so the role switches below apply to the RPC call.
create or replace function pg_temp.hits(fn text, col text, q text)
returns text[] language plpgsql as $fn$
declare
  v text[];
begin
  execute format(
    'select coalesce(array_agg(%1$I order by %1$I), ''{}''::text[]) from %2$s($1) where %1$I like ''Zqx%%''',
    col, fn)
    into v using q;
  return v;
end;
$fn$;

-- ── 2. the trigram index still serves an escaped pattern ───────────────────
set local enable_seqscan = off;
create or replace function pg_temp.plan_of(q text)
returns text language plpgsql as $fn$
declare
  r record;
  v text := '';
begin
  for r in execute 'explain ' || q loop
    v := v || r."QUERY PLAN" || E'\n';
  end loop;
  return v;
end;
$fn$;

select ok(
  pg_temp.plan_of(
    $q$ select id from clubs where name ilike '%' || private.like_escape('50%') || '%' $q$
  ) like '%clubs_name_trgm%',
  'clubs_name_trgm serves ilike over a like_escape''d pattern');
set local enable_seqscan = on;

-- ── 3. each RPC ─────────────────────────────────────────────────────────────
set local role anon;

select is(pg_temp.hits('search_clubs', 'name', '50%'), array['Zqx 50% Off'],
  'search_clubs: % matches only a literal percent');
select is(pg_temp.hits('search_clubs', 'name', 'a_b'), array['Zqx a_b'],
  'search_clubs: _ matches only a literal underscore');
select is(pg_temp.hits('search_clubs', 'name', 'back\s'), array['Zqx back\slash'],
  'search_clubs: \ matches a literal backslash');
select is(pg_temp.hits('search_clubs', 'name', 'k\'), array['Zqx back\slash'],
  'search_clubs: a query ending in \ keeps its closing wildcard');
select is(pg_temp.hits('search_clubs', 'name', '\'), array['Zqx back\slash'],
  'search_clubs: a lone \ matches a backslash, not a percent sign');
select is(pg_temp.hits('search_clubs', 'name', 'Zqx'),
  array['Zqx 50% Off', 'Zqx 500 Off', 'Zqx a_b', 'Zqx aXb', 'Zqx back\slash'],
  'search_clubs: a plain substring still matches every name containing it');

select is(pg_temp.hits('search_public_events', 'title', '50%'), array['Zqx 50% Off'],
  'search_public_events: % matches only a literal percent');
select is(pg_temp.hits('search_public_events', 'title', 'a_b'), array['Zqx a_b'],
  'search_public_events: _ matches only a literal underscore');
select is(pg_temp.hits('search_public_events', 'title', 'back\s'), array['Zqx back\slash'],
  'search_public_events: \ matches a literal backslash');
select is(pg_temp.hits('search_public_events', 'title', 'k\'), array['Zqx back\slash'],
  'search_public_events: a query ending in \ keeps its closing wildcard');
select is(pg_temp.hits('search_public_events', 'title', '\'), array['Zqx back\slash'],
  'search_public_events: a lone \ matches a backslash, not a percent sign');
select is(pg_temp.hits('search_public_events', 'title', 'Zqx'),
  array['Zqx 50% Off', 'Zqx 500 Off', 'Zqx a_b', 'Zqx aXb', 'Zqx back\slash'],
  'search_public_events: a plain substring still matches every title containing it');

select is(pg_temp.hits('search_race_listings', 'name', '50%'), array['Zqx 50% Off'],
  'search_race_listings: % matches only a literal percent');
select is(pg_temp.hits('search_race_listings', 'name', 'a_b'), array['Zqx a_b'],
  'search_race_listings: _ matches only a literal underscore');
select is(pg_temp.hits('search_race_listings', 'name', 'back\s'), array['Zqx back\slash'],
  'search_race_listings: \ matches a literal backslash');
select is(pg_temp.hits('search_race_listings', 'name', 'k\'), array['Zqx back\slash'],
  'search_race_listings: a query ending in \ keeps its closing wildcard');
select is(pg_temp.hits('search_race_listings', 'name', '\'), array['Zqx back\slash'],
  'search_race_listings: a lone \ matches a backslash, not a percent sign');
select is(pg_temp.hits('search_race_listings', 'name', 'Zqx'),
  array['Zqx 50% Off', 'Zqx 500 Off', 'Zqx a_b', 'Zqx aXb', 'Zqx back\slash'],
  'search_race_listings: a plain substring still matches every name containing it');

select is(pg_temp.hits('browse_public_challenges', 'title', '50%'), array['Zqx 50% Off'],
  'browse_public_challenges: % matches only a literal percent');
select is(pg_temp.hits('browse_public_challenges', 'title', 'a_b'), array['Zqx a_b'],
  'browse_public_challenges: _ matches only a literal underscore');
select is(pg_temp.hits('browse_public_challenges', 'title', 'back\s'), array['Zqx back\slash'],
  'browse_public_challenges: \ matches a literal backslash');
select is(pg_temp.hits('browse_public_challenges', 'title', ' k\ '), array['Zqx back\slash'],
  'browse_public_challenges: a trimmed query ending in \ keeps its closing wildcard');
select is(pg_temp.hits('browse_public_challenges', 'title', '\'), array['Zqx back\slash'],
  'browse_public_challenges: a lone \ matches a backslash, not a percent sign');
select is(pg_temp.hits('browse_public_challenges', 'title', 'Zqx'),
  array['Zqx 50% Off', 'Zqx 500 Off', 'Zqx a_b', 'Zqx aXb', 'Zqx back\slash'],
  'browse_public_challenges: a plain substring still matches every title containing it');

reset role;
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00000e5c0006","role":"authenticated"}';

select is(pg_temp.hits('search_user_profiles', 'display_name', '50%'), array['Zqx 50% Off'],
  'search_user_profiles: % matches only a literal percent');
select is(pg_temp.hits('search_user_profiles', 'display_name', 'a_b'), array['Zqx a_b'],
  'search_user_profiles: _ matches only a literal underscore');
select is(pg_temp.hits('search_user_profiles', 'display_name', 'back\s'), array['Zqx back\slash'],
  'search_user_profiles: \ matches a literal backslash');
select is(pg_temp.hits('search_user_profiles', 'display_name', 'k\'), array['Zqx back\slash'],
  'search_user_profiles: a query ending in \ keeps its closing wildcard');
select is(pg_temp.hits('search_user_profiles', 'display_name', '\'), array['Zqx back\slash'],
  'search_user_profiles: a lone \ matches a backslash, not a percent sign');
select is(pg_temp.hits('search_user_profiles', 'display_name', 'Zqx'),
  array['Zqx 50% Off', 'Zqx 500 Off', 'Zqx a_b', 'Zqx aXb', 'Zqx back\slash'],
  'search_user_profiles: a plain substring still matches every name containing it');

select * from finish();

rollback;
