-- First-touch sign-up source (migration 20271110000001, decisions § 2350).
--
-- Pins: the gate is anon-readable and records nothing while closed; a
-- confirmed account's signup_source metadata is recorded once, on
-- confirmation or on the OAuth metadata write, and never overwritten; a
-- malformed medium / campaign / host is dropped and a malformed source records
-- nothing, without failing the write it rides on; an account older than a
-- day records nothing; no client role can read the table or the daily view;
-- the view counts recorded sources and 'unknown' for the rest; the row goes
-- with the account.

begin;

select plan(19);

insert into private.feature_flags (name, enabled) values ('signup_source', false)
  on conflict (name) do update set enabled = false;

-- ── Gate closed ──
set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';
select is(signup_source_enabled(), false, 'anon reads the closed gate');
reset role;

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at, email_confirmed_at, raw_user_meta_data)
values ('00000000-0000-0000-0000-00005c000001', 'authenticated', 'authenticated', 'closed@ss.local', '',
        now(), now(), now(),
        '{"signup_source":{"source":"instagram","medium":"social","campaign":"bio"}}'::jsonb);
select is(
  (select count(*)::int from private.signup_sources where user_id = '00000000-0000-0000-0000-00005c000001'),
  0, 'a closed gate records nothing');

update private.feature_flags set enabled = true where name = 'signup_source';

set local role anon;
select is(signup_source_enabled(), true, 'anon reads the open gate');
reset role;

-- ── Email sign-up, confirmation on ──
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at, raw_user_meta_data)
values ('00000000-0000-0000-0000-00005c000002', 'authenticated', 'authenticated', 'email@ss.local', '',
        now(), now(),
        '{"signup_source":{"source":"instagram","medium":"social","campaign":"bio","referrer_host":"l.instagram.com"}}'::jsonb);
select is(
  (select count(*)::int from private.signup_sources where user_id = '00000000-0000-0000-0000-00005c000002'),
  0, 'an unconfirmed sign-up is not recorded yet');
update auth.users set email_confirmed_at = now() where id = '00000000-0000-0000-0000-00005c000002';
select is(
  (select row(source, medium, campaign, referrer_host)::text from private.signup_sources
    where user_id = '00000000-0000-0000-0000-00005c000002'),
  '(instagram,social,bio,l.instagram.com)',
  'the confirmation records source, medium, campaign and referrer host');

-- ── Confirmed at insert, with malformed optional fields ──
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at, email_confirmed_at, raw_user_meta_data)
values ('00000000-0000-0000-0000-00005c000003', 'authenticated', 'authenticated', 'loose@ss.local', '',
        now(), now(), now(),
        '{"signup_source":{"source":"tiktok","medium":"Not Valid","campaign":42,"referrer_host":"a b"}}'::jsonb);
select is(
  (select row(source, medium, campaign, referrer_host)::text from private.signup_sources
    where user_id = '00000000-0000-0000-0000-00005c000003'),
  '(tiktok,,,)',
  'a malformed medium, campaign and host are dropped, the source kept');

-- ── A malformed source records nothing and fails nothing ──
select lives_ok(
  $$ insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at, email_confirmed_at, raw_user_meta_data)
     values ('00000000-0000-0000-0000-00005c000004', 'authenticated', 'authenticated', 'bad@ss.local', '',
             now(), now(), now(), '{"signup_source":{"source":"<script>"}}'::jsonb) $$,
  'a malformed source does not fail the sign-up');
select is(
  (select count(*)::int from private.signup_sources where user_id = '00000000-0000-0000-0000-00005c000004'),
  0, 'a malformed source records nothing');
select lives_ok(
  $$ insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at, email_confirmed_at, raw_user_meta_data)
     values ('00000000-0000-0000-0000-00005c000007', 'authenticated', 'authenticated', 'str@ss.local', '',
             now(), now(), now(), '{"signup_source":"instagram"}'::jsonb) $$,
  'a non-object signup_source does not fail the sign-up');

-- ── OAuth: metadata written after the first callback ──
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at, email_confirmed_at)
values ('00000000-0000-0000-0000-00005c000005', 'authenticated', 'authenticated', 'oauth@ss.local', '',
        now(), now(), now());
update auth.users
   set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb)
         || '{"signup_source":{"source":"x","referrer_host":"t.co"}}'::jsonb
 where id = '00000000-0000-0000-0000-00005c000005';
select is(
  (select row(source, referrer_host)::text from private.signup_sources
    where user_id = '00000000-0000-0000-0000-00005c000005'),
  '(x,t.co)', 'the OAuth metadata write records the source');

update auth.users
   set raw_user_meta_data = raw_user_meta_data || '{"signup_source":{"source":"facebook"}}'::jsonb
 where id = '00000000-0000-0000-0000-00005c000005';
select is(
  (select source from private.signup_sources where user_id = '00000000-0000-0000-0000-00005c000005'),
  'x', 'a later write never overwrites the first touch');

-- ── An old account writing the key records nothing ──
insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at, email_confirmed_at)
values ('00000000-0000-0000-0000-00005c000006', 'authenticated', 'authenticated', 'old@ss.local', '',
        now() - interval '2 days', now(), now() - interval '2 days');
update auth.users
   set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb)
         || '{"signup_source":{"source":"youtube"}}'::jsonb
 where id = '00000000-0000-0000-0000-00005c000006';
select is(
  (select count(*)::int from private.signup_sources where user_id = '00000000-0000-0000-0000-00005c000006'),
  0, 'an account older than a day records nothing');

-- ── No client role reads it ──
set local role anon;
select throws_ok($$ select * from private.signup_sources $$, '42501', null,
  'anon cannot read the sources');
select throws_ok($$ select * from private.signup_sources_daily $$, '42501', null,
  'anon cannot read the daily view');
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-00005c000002","role":"authenticated"}';
select throws_ok($$ select * from private.signup_sources $$, '42501', null,
  'a signed-in user cannot read the sources, their own included');
select throws_ok($$ select * from private.signup_sources_daily $$, '42501', null,
  'a signed-in user cannot read the daily view');
reset role;

-- ── The owner's daily view ──
select is(
  (select signups from private.signup_sources_daily
    where day = (now() at time zone 'utc')::date and source = 'instagram'),
  1, 'the view counts a recorded source on its sign-up day (the closed-gate account is not one)');
select is(
  (select signups from private.signup_sources_daily
    where day = (now() at time zone 'utc')::date and source = 'unknown'),
  (select count(*)::int from auth.users u
    where u.email_confirmed_at is not null
      and (u.created_at at time zone 'utc')::date = (now() at time zone 'utc')::date
      and not exists (select 1 from private.signup_sources s where s.user_id = u.id)),
  'every confirmed account with no recorded source counts as unknown');

-- ── The row goes with the account ──
delete from auth.users where id = '00000000-0000-0000-0000-00005c000002';
select is(
  (select count(*)::int from private.signup_sources where user_id = '00000000-0000-0000-0000-00005c000002'),
  0, 'deleting the account deletes its source');

select * from finish();
rollback;
