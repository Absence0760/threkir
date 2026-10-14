-- Pins the new-device sign-in alert's database half (migration
-- 20270804000002_sign_in_devices.sql, docs/features/email.md § Security
-- emails):
--
--   * the first-ever sign-in is a silent baseline, a repeat of a known class
--     is silent, and only a class new to an account that already had one
--     enqueues a `security_email` job;
--   * the job carries the two coarse classes and a time — never the raw
--     User-Agent, never an IP;
--   * a token refresh (an UPDATE that rewrites user_agent with the same
--     value) never enqueues, while a session whose user_agent is filled in
--     after the insert is evaluated once, when it first becomes known;
--   * anonymous sessions are ignored;
--   * RLS: the owner reads their own classes, nobody else does, and no client
--     can write one;
--   * retention: a class unseen for 180 days is pruned, a still-live session
--     refreshes its class first, and an account's newest class is never
--     pruned.
--
-- Runs as the superuser except where a role is set; auth.sessions inserts
-- stand in for GoTrue's own sign-in writes.

begin;

select plan(19);

insert into auth.users (id, email, encrypted_password, email_confirmed_at, instance_id, aud, role, is_anonymous)
values
  ('e1e1e1e1-0000-4000-8000-00000000000a', 'device-a@example.com', '', now(),
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', false),
  ('e1e1e1e1-0000-4000-8000-00000000000b', 'device-b@example.com', '', now(),
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', false),
  ('e1e1e1e1-0000-4000-8000-00000000000c', null, '', null,
   '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', true);

-- The User-Agents a real browser and the mobile app send.
create temporary table ua (name text primary key, value text not null);
insert into ua values
  ('firefox_linux', 'Mozilla/5.0 (X11; Linux x86_64; rv:131.0) Gecko/20100101 Firefox/131.0'),
  ('chrome_android', 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Mobile Safari/537.36'),
  ('safari_ios', 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1'),
  ('edge_windows', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36 Edg/129.0.0.0'),
  ('dart_app', 'Dart/3.5 (dart:io)');

create temporary view a_security_jobs as
  select payload from public.jobs
   where kind = 'security_email'
     and payload->>'user_id' = 'e1e1e1e1-0000-4000-8000-00000000000a';

-- ── classifiers ──

select is(
  public.sign_in_browser_class((select value from ua where name = 'edge_windows')),
  'edge',
  'an Edge User-Agent classifies as edge, not as the Chrome token it also carries'
);
select is(
  public.sign_in_platform_class((select value from ua where name = 'chrome_android')),
  'android',
  'an Android User-Agent classifies as android, not as the Linux token it also carries'
);
select is(
  public.sign_in_browser_class((select value from ua where name = 'dart_app'))
    || '/' || public.sign_in_platform_class((select value from ua where name = 'dart_app')),
  'threkir_app/other',
  'the mobile app''s dart:io User-Agent is its own class with no platform'
);

-- ── first sign-in, repeat, new class ──

insert into auth.sessions (id, user_id, created_at, updated_at, user_agent)
values ('e1e1e1e1-1111-4000-8000-000000000001', 'e1e1e1e1-0000-4000-8000-00000000000a',
        now(), now(), (select value from ua where name = 'firefox_linux'));

select is(
  (select count(*)::int from public.sign_in_devices
    where user_id = 'e1e1e1e1-0000-4000-8000-00000000000a'
      and browser = 'firefox' and platform = 'linux'),
  1,
  'the first sign-in records its device class'
);
select is(
  (select count(*)::int from a_security_jobs),
  0,
  'the first-ever sign-in is a silent baseline and enqueues no alert'
);

insert into auth.sessions (id, user_id, created_at, updated_at, user_agent)
values ('e1e1e1e1-1111-4000-8000-000000000002', 'e1e1e1e1-0000-4000-8000-00000000000a',
        now(), now(), (select value from ua where name = 'firefox_linux'));

select is(
  (select count(*)::int from a_security_jobs),
  0,
  'a second sign-in from a known class enqueues no alert'
);

insert into auth.sessions (id, user_id, created_at, updated_at, user_agent)
values ('e1e1e1e1-1111-4000-8000-000000000003', 'e1e1e1e1-0000-4000-8000-00000000000a',
        now(), now(), (select value from ua where name = 'chrome_android'));

select is(
  (select count(*)::int from a_security_jobs),
  1,
  'a sign-in from a class new to the account enqueues one security_email'
);
select is(
  (select payload - 'signed_in_at' from a_security_jobs),
  jsonb_build_object(
    'user_id', 'e1e1e1e1-0000-4000-8000-00000000000a',
    'template', 'new_device_sign_in',
    'browser', 'chrome',
    'platform', 'android'
  ),
  'the job carries the two classes and the template, and no User-Agent or IP key'
);
select ok(
  (select (payload->>'signed_in_at')::timestamptz between now() - interval '1 minute' and now() + interval '1 minute'
     from a_security_jobs),
  'the job stamps the sign-in time as an ISO instant'
);

-- ── refresh vs a late User-Agent ──

-- A refresh rewrites user_agent with the value it already had.
update auth.sessions
   set updated_at = now(), user_agent = (select value from ua where name = 'chrome_android')
 where id = 'e1e1e1e1-1111-4000-8000-000000000003';

select is(
  (select count(*)::int from a_security_jobs),
  1,
  'a token refresh on an existing session enqueues nothing'
);

insert into auth.sessions (id, user_id, created_at, updated_at, user_agent)
values ('e1e1e1e1-1111-4000-8000-000000000004', 'e1e1e1e1-0000-4000-8000-00000000000a',
        now(), now(), null);
update auth.sessions
   set user_agent = (select value from ua where name = 'safari_ios')
 where id = 'e1e1e1e1-1111-4000-8000-000000000004';

select is(
  (select count(*)::int from a_security_jobs where payload->>'browser' = 'safari'),
  1,
  'a session whose User-Agent arrives after the insert is evaluated when it first becomes known'
);

-- ── anonymous ──

insert into auth.sessions (id, user_id, created_at, updated_at, user_agent)
values ('e1e1e1e1-1111-4000-8000-000000000005', 'e1e1e1e1-0000-4000-8000-00000000000c',
        now(), now(), (select value from ua where name = 'firefox_linux'));

select is(
  (select count(*)::int from public.sign_in_devices
    where user_id = 'e1e1e1e1-0000-4000-8000-00000000000c'),
  0,
  'an anonymous session records no device class'
);

-- B's own baseline, used by the RLS and retention halves below.
insert into auth.sessions (id, user_id, created_at, updated_at, user_agent)
values ('e1e1e1e1-1111-4000-8000-000000000006', 'e1e1e1e1-0000-4000-8000-00000000000b',
        now(), now(), (select value from ua where name = 'edge_windows'));

-- ── RLS ──

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"e1e1e1e1-0000-4000-8000-00000000000a","role":"authenticated"}';

select is(
  (select count(*)::int from public.sign_in_devices),
  3,
  'the owner reads their own three device classes'
);
select throws_ok(
  $$ insert into public.sign_in_devices (user_id, browser, platform)
     values ('e1e1e1e1-0000-4000-8000-00000000000a', 'opera', 'macos') $$,
  '42501',
  null,
  'a client has no INSERT on sign_in_devices, so it cannot pre-register a class to mute a future alert'
);

set local "request.jwt.claims" = '{"sub":"e1e1e1e1-0000-4000-8000-00000000000b","role":"authenticated"}';

select is(
  (select count(*)::int from public.sign_in_devices
    where user_id = 'e1e1e1e1-0000-4000-8000-00000000000a'),
  0,
  'another account cannot see the owner''s device classes'
);

reset role;
set local "request.jwt.claims" = '';

-- ── retention ──

-- A signed out of Firefox long ago: no live session, last seen 200 days back.
delete from auth.sessions
 where user_id = 'e1e1e1e1-0000-4000-8000-00000000000a'
   and user_agent = (select value from ua where name = 'firefox_linux');
update public.sign_in_devices
   set last_seen_at = now() - interval '200 days'
 where user_id = 'e1e1e1e1-0000-4000-8000-00000000000a' and browser = 'firefox';

-- A's phone stayed signed in and only refreshed: the row looks stale, the
-- session does not.
update public.sign_in_devices
   set last_seen_at = now() - interval '200 days'
 where user_id = 'e1e1e1e1-0000-4000-8000-00000000000a' and browser = 'chrome';

-- B's only class, signed out and stale.
delete from auth.sessions where user_id = 'e1e1e1e1-0000-4000-8000-00000000000b';
update public.sign_in_devices
   set last_seen_at = now() - interval '200 days'
 where user_id = 'e1e1e1e1-0000-4000-8000-00000000000b';

select lives_ok($$ select public.prune_sign_in_devices() $$, 'the prune runs');

select is(
  (select count(*)::int from public.sign_in_devices
    where user_id = 'e1e1e1e1-0000-4000-8000-00000000000a' and browser = 'firefox'),
  0,
  'a class unseen for 180 days with no live session is pruned'
);
select ok(
  (select last_seen_at > now() - interval '1 day' from public.sign_in_devices
    where user_id = 'e1e1e1e1-0000-4000-8000-00000000000a' and browser = 'chrome'),
  'a class with a live session is refreshed from it rather than pruned'
);
select is(
  (select count(*)::int from public.sign_in_devices
    where user_id = 'e1e1e1e1-0000-4000-8000-00000000000b'),
  1,
  'an account''s newest class survives the prune however stale, so the alert never resets to a silent baseline'
);

select * from finish();
rollback;
