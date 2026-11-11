-- Pins 20271224000800 / 20271224000810 (audit of PR #1359, Low): a pending
-- group invite can be reported by the person it invites, and the report
-- carries the title and the inviter they were shown to the admin queue.
--
--   1-2.  The invitee reports the invite; the report snapshots the title, the
--         inviter and when.
--   3.    The admin queue's detail carries that snapshot.
--   4.    Someone the group never invited cannot report it ("not found").
--   5.    A member who already accepted has no invite left to report.
--   6.    The reasons are the general ones.
--   7.    Both constraints the migration added are validated.

begin;
select plan(7);

insert into private.feature_flags (name, enabled) values ('group_messages', true)
on conflict (name) do update set enabled = true;

insert into auth.users (id, email, encrypted_password, email_confirmed_at, instance_id, aud, role)
select ('b2480000-0000-0000-0000-0000000000' || s)::uuid, 'gir-' || s || '@example.com', '', now(),
       '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'
  from unnest(array['a0', 'a1', 'a2', 'a3', 'ad']) as s;

insert into app_admins (user_id) values ('b2480000-0000-0000-0000-0000000000ad');

insert into user_follows (follower_id, followee_id)
select 'b2480000-0000-0000-0000-0000000000a0', ('b2480000-0000-0000-0000-0000000000' || s)::uuid
  from unnest(array['a1', 'a2']) as s;

create temporary table g (id uuid);
grant all on g to authenticated;

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"b2480000-0000-0000-0000-0000000000a0","role":"authenticated"}';
insert into g select create_group_conversation('Abusive title here',
  array['b2480000-0000-0000-0000-0000000000a1', 'b2480000-0000-0000-0000-0000000000a2']::uuid[]);

set local "request.jwt.claims" = '{"sub":"b2480000-0000-0000-0000-0000000000a1","role":"authenticated"}';
select lives_ok(
  $$ select submit_report('group_invite', (select id from g), 'harassment', 'the title is abuse') $$,
  'the invitee reports the pending invite');

reset role;
select is(
  (select snapshot_body || '|' || snapshot_author_id::text || '|' || (snapshot_sent_at is not null)::text
     from reports where target_kind = 'group_invite' and target_id = (select id from g)),
  'Abusive title here|b2480000-0000-0000-0000-0000000000a0|true',
  'the report snapshots the title, the inviter and when');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"b2480000-0000-0000-0000-0000000000ad","role":"authenticated"}';
select is(
  (select snapshot_body || '|' || snapshot_author_id::text
     from fetch_reports_for_target('group_invite', (select id from g))),
  'Abusive title here|b2480000-0000-0000-0000-0000000000a0',
  'the admin queue''s detail carries the title and the inviter');

set local "request.jwt.claims" = '{"sub":"b2480000-0000-0000-0000-0000000000a3","role":"authenticated"}';
select throws_ok(
  $$ select submit_report('group_invite', (select id from g), 'spam', null) $$,
  '02000', null,
  'someone the group never invited cannot report it');

set local "request.jwt.claims" = '{"sub":"b2480000-0000-0000-0000-0000000000a2","role":"authenticated"}';
select accept_group_invite((select id from g));
select throws_ok(
  $$ select submit_report('group_invite', (select id from g), 'spam', null) $$,
  '02000', null,
  'a member who accepted has no invite left to report');

set local "request.jwt.claims" = '{"sub":"b2480000-0000-0000-0000-0000000000a1","role":"authenticated"}';
select throws_ok(
  $$ select submit_report('group_invite', (select id from g), 'course_hazard', null) $$,
  '22023', 'submit_report: invalid reason course_hazard',
  'an invite takes the general reasons only');

reset role;
select is(
  (select count(*)::int from pg_constraint
    where conrelid = 'public.reports'::regclass
      and conname in ('reports_target_kind_check', 'reports_group_invite_snapshot_check')
      and convalidated),
  2,
  'both constraints are validated');

select * from finish();
rollback;
