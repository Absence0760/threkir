-- Pins the subscribable plan calendar feed's database half (migration
-- 20270910000001_plan_calendar_feeds.sql, docs/features/training.md
-- § Calendar feed):
--
--   * rotate mints a 96-hex token whose first half is the row id and whose
--     second half hashes to secret_hash; only the hash is stored;
--   * rotating again replaces both halves, so the previous URL stops
--     resolving; revoke deletes the row;
--   * no client grant on the table: the owner's status RPC returns
--     created_at / last_fetched_at and nothing else, another account sees
--     nothing, no client can read or write the row;
--   * the feed body (service role only) carries the active plan's non-rest
--     workouts and nothing from another plan, and never a note or race name;
--   * the anonymous caller can reach none of the three functions;
--   * deleting the auth user cascades the feed away (Art 17).

begin;

select plan(28);

insert into auth.users (id, email, encrypted_password, email_confirmed_at, instance_id, aud, role)
values
  ('ca1e0000-0000-4000-8000-00000000000a', 'cal-a@example.com', '', now(),
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
  ('ca1e0000-0000-4000-8000-00000000000b', 'cal-b@example.com', '', now(),
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated');

insert into public.user_profiles (id, preferred_unit)
values ('ca1e0000-0000-4000-8000-00000000000a', 'km'),
       ('ca1e0000-0000-4000-8000-00000000000b', 'km')
on conflict (id) do update set preferred_unit = excluded.preferred_unit;

insert into public.user_settings (user_id, prefs)
values ('ca1e0000-0000-4000-8000-00000000000a', '{"preferred_unit": "mi", "locale": "de"}')
on conflict (user_id) do update set prefs = excluded.prefs;

-- A's active plan, and an older abandoned one whose workouts must not leak.
insert into public.training_plans (id, user_id, name, goal_event, goal_distance_m,
                                   start_date, end_date, status, notes)
values
  ('ca1e0001-0000-4000-8000-000000000001', 'ca1e0000-0000-4000-8000-00000000000a',
   'Boston build', 'distance_5k', 5000, '2026-10-01', '2026-11-01', 'active', 'private plan note'),
  ('ca1e0001-0000-4000-8000-000000000002', 'ca1e0000-0000-4000-8000-00000000000a',
   'Old plan', 'distance_5k', 5000, '2026-01-01', '2026-02-01', 'abandoned', null);

insert into public.plan_weeks (id, plan_id, week_index)
values ('ca1e0002-0000-4000-8000-000000000001', 'ca1e0001-0000-4000-8000-000000000001', 0),
       ('ca1e0002-0000-4000-8000-000000000002', 'ca1e0001-0000-4000-8000-000000000002', 0);

insert into public.plan_workouts (id, week_id, scheduled_date, kind, target_distance_m,
                                  target_pace_sec_per_km, target_pace_tolerance_sec, notes, race_name)
values
  ('ca1e0003-0000-4000-8000-000000000001', 'ca1e0002-0000-4000-8000-000000000001',
   '2026-10-05', 'tempo', 8000, 290, 5, 'meet at the river bridge', null),
  ('ca1e0003-0000-4000-8000-000000000002', 'ca1e0002-0000-4000-8000-000000000001',
   '2026-10-06', 'rest', null, null, null, null, null),
  ('ca1e0003-0000-4000-8000-000000000003', 'ca1e0002-0000-4000-8000-000000000001',
   '2026-10-31', 'race', 5000, null, null, null, 'Riverside 5K at Main St'),
  ('ca1e0003-0000-4000-8000-000000000004', 'ca1e0002-0000-4000-8000-000000000002',
   '2026-01-05', 'easy', 6000, null, null, null, null);

-- ── anon reaches nothing ──

select ok(
  not has_function_privilege('anon', 'public.rotate_plan_calendar_feed()', 'EXECUTE'),
  'anon cannot mint a feed token'
);
select ok(
  not has_function_privilege('anon', 'public.revoke_plan_calendar_feed()', 'EXECUTE'),
  'anon cannot revoke a feed'
);
select ok(
  not has_function_privilege('anon', 'public.plan_calendar_feed_events(uuid)', 'EXECUTE')
    and not has_function_privilege('anon', 'public.plan_calendar_feed_status()', 'EXECUTE'),
  'anon cannot read a feed body or a feed status'
);
select ok(
  not has_function_privilege('authenticated', 'public.plan_calendar_feed_events(uuid)', 'EXECUTE'),
  'a signed-in client cannot read a feed body by id either; only the Edge Function can, after the secret check'
);
select ok(
  not has_table_privilege('authenticated', 'public.plan_calendar_feeds', 'SELECT')
    and not has_column_privilege('authenticated', 'public.plan_calendar_feeds', 'secret_hash', 'SELECT')
    and not has_column_privilege('authenticated', 'public.plan_calendar_feeds', 'id', 'SELECT'),
  'no client can read the table, the hash or the selector half of the URL'
);

-- ── rotate as A ──

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"ca1e0000-0000-4000-8000-00000000000a","role":"authenticated"}';

create temporary table tok (n int primary key, value text not null) on commit drop;
grant all on tok to authenticated;

insert into tok values (1, public.rotate_plan_calendar_feed());

select matches(
  (select value from tok where n = 1),
  '^[0-9a-f]{96}$',
  'the token is 96 lowercase hex characters'
);
select is(
  (select count(*)::int from public.plan_calendar_feed_status()),
  1,
  'the owner''s status reads their one feed'
);
select ok(
  (select created_at > now() - interval '1 minute' and last_fetched_at is null
     from public.plan_calendar_feed_status()),
  'the owner reads when the feed was made, and that no calendar has read it yet'
);
select throws_ok(
  $$ select secret_hash from public.plan_calendar_feeds $$,
  '42501',
  null,
  'the owner cannot read the stored hash'
);
select throws_ok(
  $$ insert into public.plan_calendar_feeds (user_id, secret_hash)
     values ('ca1e0000-0000-4000-8000-00000000000a', sha256('x')) $$,
  '42501',
  null,
  'a client cannot plant a feed row with a secret of its own choosing'
);
select throws_ok(
  $$ update public.plan_calendar_feeds set last_fetched_at = null $$,
  '42501',
  null,
  'a client cannot rewrite its feed row'
);

set local "request.jwt.claims" = '{"sub":"ca1e0000-0000-4000-8000-00000000000b","role":"authenticated"}';

select is(
  (select count(*)::int from public.plan_calendar_feed_status()),
  0,
  'another account''s status does not see A''s feed'
);
select is(
  public.revoke_plan_calendar_feed(),
  false,
  'B revoking touches only B''s (absent) feed'
);

reset role;
set local "request.jwt.claims" = '';

select is(
  (select replace(id::text, '-', '') from public.plan_calendar_feeds
    where user_id = 'ca1e0000-0000-4000-8000-00000000000a'),
  (select left(value, 32) from tok where n = 1),
  'the first 32 hex characters are the row id'
);
select is(
  (select secret_hash from public.plan_calendar_feeds
    where user_id = 'ca1e0000-0000-4000-8000-00000000000a'),
  (select sha256(convert_to(substr(value, 33), 'UTF8')) from tok where n = 1),
  'the stored hash is the SHA-256 of the secret half'
);
-- ── the feed body ──

create temporary table body (doc jsonb) on commit drop;
insert into body
select public.plan_calendar_feed_events(
  (select id from public.plan_calendar_feeds where user_id = 'ca1e0000-0000-4000-8000-00000000000a'));

select is(
  (select jsonb_array_length(doc -> 'workouts') from body),
  2,
  'the body carries the active plan''s two non-rest workouts and nothing from the abandoned plan'
);
select is(
  (select jsonb_agg(w ->> 'kind' order by w ->> 'date') from body, jsonb_array_elements(doc -> 'workouts') w),
  '["tempo", "race"]'::jsonb,
  'rest days are left out'
);
select is(
  (select (doc ->> 'unit') || '/' || (doc ->> 'locale') from body),
  'mi/de',
  'the body carries the owner''s chosen unit (the bag beats the profile column) and language'
);
select ok(
  (select doc::text !~ '(river bridge|Riverside|Main St|private plan note|Boston build)' from body),
  'no note, race name or plan name reaches the feed'
);
select is(
  (select array_agg(k order by k) from body, jsonb_array_elements(doc -> 'workouts') w, jsonb_object_keys(w) k
    where w ->> 'kind' = 'tempo'),
  array['date', 'id', 'kind', 'target_distance_m', 'target_duration_seconds',
        'target_pace_end_sec_per_km', 'target_pace_sec_per_km', 'target_pace_tolerance_sec'],
  'each workout projects exactly id, date, kind and the prescribed target'
);
select ok(
  (select last_fetched_at > now() - interval '1 minute' from public.plan_calendar_feeds
    where user_id = 'ca1e0000-0000-4000-8000-00000000000a'),
  'a read stamps last_fetched_at'
);
select is(
  public.plan_calendar_feed_events('00000000-0000-4000-8000-000000000000'),
  null,
  'an unknown feed id reads as null'
);

-- ── rotate again, then revoke ──

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"ca1e0000-0000-4000-8000-00000000000a","role":"authenticated"}';
insert into tok values (2, public.rotate_plan_calendar_feed());
reset role;
set local "request.jwt.claims" = '';

select ok(
  (select left(a.value, 32) <> left(b.value, 32) and substr(a.value, 33) <> substr(b.value, 33)
     from tok a, tok b where a.n = 1 and b.n = 2),
  'rotating replaces both the selector and the secret'
);
select is(
  public.plan_calendar_feed_events(
    (select left(value, 32) from tok where n = 1)::uuid),
  null,
  'the pre-rotation URL no longer resolves'
);

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"ca1e0000-0000-4000-8000-00000000000a","role":"authenticated"}';
select is(public.revoke_plan_calendar_feed(), true, 'revoke reports that a feed existed');
reset role;
set local "request.jwt.claims" = '';

select is(
  (select count(*)::int from public.plan_calendar_feeds
    where user_id = 'ca1e0000-0000-4000-8000-00000000000a'),
  0,
  'revoke deletes the row'
);

-- ── rotate is rate-limited ──

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"ca1e0000-0000-4000-8000-00000000000a","role":"authenticated"}';
select throws_like(
  $$ do $d$ begin
       for i in 1..21 loop perform public.rotate_plan_calendar_feed(); end loop;
     end $d$ $$,
  'rate limit exceeded for plan_calendar_rotate%',
  'minting is capped at 20 an hour, so a hijacked session cannot churn links'
);
reset role;
set local "request.jwt.claims" = '';

-- ── Art 17 ──

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"ca1e0000-0000-4000-8000-00000000000b","role":"authenticated"}';
select public.rotate_plan_calendar_feed();
reset role;
set local "request.jwt.claims" = '';

delete from auth.users where id = 'ca1e0000-0000-4000-8000-00000000000b';

select is(
  (select count(*)::int from public.plan_calendar_feeds
    where user_id = 'ca1e0000-0000-4000-8000-00000000000b'),
  0,
  'deleting the account cascades its feed away'
);

select * from finish();
rollback;
