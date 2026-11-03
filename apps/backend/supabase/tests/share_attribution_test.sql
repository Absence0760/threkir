-- Share-link attribution (migration 20271104000004, decisions § 2268).
--
-- Pins: record_share_visit is anon-callable, counts a public entity's view in
-- an aggregate daily bucket, splits the owner's ref and named bots, writes
-- nothing for an unknown, non-public or own view or while the gate is closed,
-- and stops at the cap; the counter tables are unreadable by any client role;
-- my_share_ref mints one stable code; a sign-up whose metadata names the
-- owner's ref is counted once, on confirmation or on the OAuth metadata write,
-- and a foreign ref is not; attribute_share_start marks a fresh copy or join
-- once and a client cannot write either mark; my_share_stats returns the
-- caller's own links only; the purge job is scheduled and keeps 90 days.

begin;

select plan(34);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000a7700001', 'authenticated', 'authenticated', 'creator@sa.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000a7700002', 'authenticated', 'authenticated', 'follower@sa.local', '', now(), now()),
  ('00000000-0000-0000-0000-0000a7700003', 'authenticated', 'authenticated', 'other@sa.local', '', now(), now());

insert into user_profiles (id, display_name)
values
  ('00000000-0000-0000-0000-0000a7700001', 'Creator Cleo'),
  ('00000000-0000-0000-0000-0000a7700002', 'Follower Finn'),
  ('00000000-0000-0000-0000-0000a7700003', 'Other Ola')
on conflict (id) do update set display_name = excluded.display_name;

select tests.confirm_consent();

insert into private.feature_flags (name, enabled) values ('share_attribution', true)
  on conflict (name) do update set enabled = true;

insert into training_plans (
  id, user_id, name, goal_event, goal_distance_m, start_date, end_date,
  days_per_week, status, is_template, is_public_template
) values
  ('aaaaaaaa-0000-0000-0000-0000a7700001', '00000000-0000-0000-0000-0000a7700001',
   'Marathon block', 'distance_full', 42195, '2026-03-02', '2026-05-24', 5,
   'completed', true, true),
  ('aaaaaaaa-0000-0000-0000-0000a7700002', '00000000-0000-0000-0000-0000a7700001',
   'Private plan', 'distance_full', 42195, '2026-03-02', '2026-05-24', 4,
   'active', false, false);

insert into challenges (id, creator_id, title, metric, scope, goal_value, starts_at, ends_at, is_public)
values
  ('eeeeeeee-eeee-eeee-eeee-eeeea7700001', '00000000-0000-0000-0000-0000a7700001',
   'Run 50 km with me', 'distance', 'individual', 50000,
   now() - interval '1 day', now() + interval '29 days', true);

-- Codes for the creator and the other user, minted the way a client mints them.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000a7700001","role":"authenticated"}';
select matches(my_share_ref(), '^[a-z0-9]{10}$', 'my_share_ref mints a ten-character code');
select is(my_share_ref(), (select my_share_ref()), 'my_share_ref returns the same code again');
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000a7700003","role":"authenticated"}';
select isnt(my_share_ref(), null, 'another user gets a code of their own');
reset role;

create temporary table codes as
  select user_id, code from private.share_ref_codes
   where user_id in ('00000000-0000-0000-0000-0000a7700001', '00000000-0000-0000-0000-0000a7700003');
grant select on codes to anon, authenticated;

select is((select count(distinct code)::int from codes), 2, 'the two codes differ');

-- ── The counters are unreachable from a client role ──
set local role anon;
select throws_ok($$ select * from private.share_link_daily $$, '42501', null,
  'anon cannot read the counters');
select throws_ok($$ select * from private.share_ref_codes $$, '42501', null,
  'anon cannot read the ref codes');
select throws_ok($$ select my_share_ref() $$, '42501', null,
  'anon cannot mint a ref code');

-- ── Visits ──
set local "request.jwt.claims" = '{"role":"anon"}';
select lives_ok($$ select record_share_visit('plan', 'aaaaaaaa-0000-0000-0000-0000a7700001') $$,
  'anon records a visit');
select record_share_visit('plan', 'aaaaaaaa-0000-0000-0000-0000a7700001',
  (select code from codes where user_id = '00000000-0000-0000-0000-0000a7700001'));
select record_share_visit('plan', 'aaaaaaaa-0000-0000-0000-0000a7700001',
  (select code from codes where user_id = '00000000-0000-0000-0000-0000a7700003'));
select record_share_visit('plan', 'aaaaaaaa-0000-0000-0000-0000a7700001', null, true);
select record_share_visit('plan', 'aaaaaaaa-0000-0000-0000-0000a7700002');
select record_share_visit('plan', 'aaaaaaaa-0000-0000-0000-0000a7700999');
select record_share_visit('club', 'aaaaaaaa-0000-0000-0000-0000a7700001');
select record_share_visit('profile', '00000000-0000-0000-0000-0000a7700001');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000a7700001","role":"authenticated"}';
select record_share_visit('plan', 'aaaaaaaa-0000-0000-0000-0000a7700001');
reset role;

select is(
  (select row(visits, ref_visits, bot_visits)::text from private.share_link_daily
    where kind = 'plan' and entity_id = 'aaaaaaaa-0000-0000-0000-0000a7700001'),
  '(3,1,1)',
  'three visits, one through the owner''s ref (a foreign ref is not), one bot apart, the owner''s own view uncounted');
select is(
  (select owner_id from private.share_link_daily
    where kind = 'plan' and entity_id = 'aaaaaaaa-0000-0000-0000-0000a7700001'),
  '00000000-0000-0000-0000-0000a7700001'::uuid, 'the bucket names the plan''s owner');
select is(
  (select count(*)::int from private.share_link_daily
    where entity_id in ('aaaaaaaa-0000-0000-0000-0000a7700002', 'aaaaaaaa-0000-0000-0000-0000a7700999')),
  0, 'a non-public plan and an unknown id write nothing');
select is(
  (select count(*)::int from private.share_link_daily where kind not in ('plan', 'profile')),
  0, 'a kind outside the creator view writes nothing');
select is(
  (select visits from private.share_link_daily
    where kind = 'profile' and entity_id = '00000000-0000-0000-0000-0000a7700001'),
  1, 'a public profile view is counted');

update private.share_link_daily set visits = private.share_link_daily_cap()
 where kind = 'plan' and entity_id = 'aaaaaaaa-0000-0000-0000-0000a7700001';
select record_share_visit('plan', 'aaaaaaaa-0000-0000-0000-0000a7700001');
select is(
  (select visits from private.share_link_daily
    where kind = 'plan' and entity_id = 'aaaaaaaa-0000-0000-0000-0000a7700001'),
  1000000, 'a counter stops at the daily cap');
update private.share_link_daily set visits = 3
 where kind = 'plan' and entity_id = 'aaaaaaaa-0000-0000-0000-0000a7700001';

-- ── Sign-ups ──
-- Email sign-up with confirmation on: counted when the link is opened.
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at, raw_user_meta_data)
values ('00000000-0000-0000-0000-0000a7700010', 'authenticated', 'authenticated', 'new1@sa.local', '',
        now(), now(),
        jsonb_build_object('signup_share', jsonb_build_object(
          'kind', 'plan', 'id', 'aaaaaaaa-0000-0000-0000-0000a7700001',
          'ref', (select code from codes where user_id = '00000000-0000-0000-0000-0000a7700001'))));
select is(
  (select signups from private.share_link_daily
    where kind = 'plan' and entity_id = 'aaaaaaaa-0000-0000-0000-0000a7700001'),
  0, 'an unconfirmed sign-up is not counted yet');
update auth.users set email_confirmed_at = now() where id = '00000000-0000-0000-0000-0000a7700010';
select is(
  (select signups from private.share_link_daily
    where kind = 'plan' and entity_id = 'aaaaaaaa-0000-0000-0000-0000a7700001'),
  1, 'the confirmation counts the sign-up');

-- The same account writing the metadata again is not a second sign-up.
update auth.users
   set raw_user_meta_data = raw_user_meta_data
         || jsonb_build_object('signup_share', (raw_user_meta_data -> 'signup_share') || '{"x":1}'::jsonb)
 where id = '00000000-0000-0000-0000-0000a7700010';
select is(
  (select signups from private.share_link_daily
    where kind = 'plan' and entity_id = 'aaaaaaaa-0000-0000-0000-0000a7700001'),
  1, 'an account is counted once');

-- OAuth: confirmed at insert with no metadata, then the callback writes it.
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at, email_confirmed_at)
values ('00000000-0000-0000-0000-0000a7700011', 'authenticated', 'authenticated', 'new2@sa.local', '',
        now(), now(), now());
update auth.users
   set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb) || jsonb_build_object(
         'signup_share', jsonb_build_object(
           'kind', 'challenge', 'id', 'eeeeeeee-eeee-eeee-eeee-eeeea7700001',
           'ref', (select code from codes where user_id = '00000000-0000-0000-0000-0000a7700001')))
 where id = '00000000-0000-0000-0000-0000a7700011';
select is(
  (select signups from private.share_link_daily
    where kind = 'challenge' and entity_id = 'eeeeeeee-eeee-eeee-eeee-eeeea7700001'),
  1, 'the OAuth metadata write counts the sign-up');

-- A foreign ref, a malformed id and an account older than a day are not counted.
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at, email_confirmed_at, raw_user_meta_data)
values
  ('00000000-0000-0000-0000-0000a7700012', 'authenticated', 'authenticated', 'new3@sa.local', '',
   now(), now(), now(),
   jsonb_build_object('signup_share', jsonb_build_object(
     'kind', 'challenge', 'id', 'eeeeeeee-eeee-eeee-eeee-eeeea7700001',
     'ref', (select code from codes where user_id = '00000000-0000-0000-0000-0000a7700003')))),
  ('00000000-0000-0000-0000-0000a7700013', 'authenticated', 'authenticated', 'new4@sa.local', '',
   now(), now(), now(),
   '{"signup_share":{"kind":"challenge","id":"not-a-uuid","ref":"abc"}}'::jsonb),
  ('00000000-0000-0000-0000-0000a7700014', 'authenticated', 'authenticated', 'new5@sa.local', '',
   now() - interval '3 days', now(), now(),
   jsonb_build_object('signup_share', jsonb_build_object(
     'kind', 'challenge', 'id', 'eeeeeeee-eeee-eeee-eeee-eeeea7700001',
     'ref', (select code from codes where user_id = '00000000-0000-0000-0000-0000a7700001'))));
select is(
  (select signups from private.share_link_daily
    where kind = 'challenge' and entity_id = 'eeeeeeee-eeee-eeee-eeee-eeeea7700001'),
  1, 'a foreign ref, a malformed id and an old account add nothing');

-- ── Plan starts and challenge joins ──
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000a7700002","role":"authenticated"}';
create temporary table copy on commit drop as
  select clone_public_plan('aaaaaaaa-0000-0000-0000-0000a7700001'::uuid, '2026-09-07'::date) as id;

select ok(
  attribute_share_start('plan', (select id from copy),
    (select code from codes where user_id = '00000000-0000-0000-0000-0000a7700001')),
  'a fresh copy started from the owner''s link is attributed');
select ok(
  not attribute_share_start('plan', (select id from copy),
    (select code from codes where user_id = '00000000-0000-0000-0000-0000a7700001')),
  'a copy is attributed once');

select throws_ok($$ delete from private.plan_share_starts $$, '42501', null,
  'a client cannot clear the start attribution');

insert into challenge_participants (challenge_id, user_id)
values ('eeeeeeee-eeee-eeee-eeee-eeeea7700001', '00000000-0000-0000-0000-0000a7700002');
select throws_ok($$ select * from private.challenge_share_joins $$, '42501', null,
  'a client cannot read or write the join attribution');
select ok(
  not attribute_share_start('challenge', 'eeeeeeee-eeee-eeee-eeee-eeeea7700001',
    (select code from codes where user_id = '00000000-0000-0000-0000-0000a7700003')),
  'a foreign ref does not attribute a join');
select ok(
  attribute_share_start('challenge', 'eeeeeeee-eeee-eeee-eeee-eeeea7700001',
    (select code from codes where user_id = '00000000-0000-0000-0000-0000a7700001')),
  'a join through the creator''s link is attributed');

-- ── The creator view ──
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000a7700001","role":"authenticated"}';
select is(
  (select row(title, visits, ref_visits, bot_visits, signups, starts, ref_starts)::text
     from my_share_stats() where kind = 'plan'),
  '("Marathon block",3,1,1,1,1,1)',
  'the creator sees the plan''s visits, sign-ups and starts');
select is(
  (select row(signups, joins, ref_joins)::text from my_share_stats() where kind = 'challenge'),
  '(1,1,1)', 'the creator sees the challenge''s sign-ups and joins');
select is(
  (select visits from my_share_stats() where kind = 'profile'),
  1, 'the creator sees their profile''s visits');

set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000a7700002","role":"authenticated"}';
-- refusal: share stats are the owner's alone, and the creator's buckets exist
select is((select count(*)::int from my_share_stats()), 0,
  'nobody else sees the creator''s numbers');

-- ── The gate ──
reset role;
update private.feature_flags set enabled = false where name = 'share_attribution';
set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';
select record_share_visit('plan', 'aaaaaaaa-0000-0000-0000-0000a7700001');
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000a7700001","role":"authenticated"}';
select is(my_share_ref(), null, 'no ref code while the gate is closed');
-- refusal: the share_attribution gate is fail-closed, and the creator's buckets exist
select is((select count(*)::int from my_share_stats()), 0, 'no creator view while the gate is closed');
reset role;
select is(
  (select visits from private.share_link_daily
    where kind = 'plan' and entity_id = 'aaaaaaaa-0000-0000-0000-0000a7700001'),
  3, 'no visit is counted while the gate is closed');

-- ── Retention ──
insert into private.share_link_daily (kind, entity_id, day, owner_id, visits)
values ('plan', 'aaaaaaaa-0000-0000-0000-0000a7700001', (now() at time zone 'utc')::date - 91,
        '00000000-0000-0000-0000-0000a7700001', 5);
select private.purge_share_link_daily();
select is(
  (select count(*)::int from private.share_link_daily
    where kind = 'plan' and entity_id = 'aaaaaaaa-0000-0000-0000-0000a7700001'),
  1, 'the purge drops buckets older than 90 days and keeps today''s');
select is(
  (select count(*)::int from cron.job where jobname = 'purge-share-link-daily'),
  1, 'pg_cron entry purge-share-link-daily is registered');

select * from finish();
rollback;
