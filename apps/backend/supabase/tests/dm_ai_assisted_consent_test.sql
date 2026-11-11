-- Pins 20271224000300 (audit of PR #1359, Low): a message marked ai_assisted
-- is admitted only from an active coach whose athlete consented to the
-- assistant on that link, the gates /api/coach/assist checks before a draft.

begin;
select plan(6);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('ca524000-0000-0000-0000-00000000000a', 'authenticated', 'authenticated', 'athlete@aiconsent.local', '', now(), now()),
  ('ca524000-0000-0000-0000-00000000000c', 'authenticated', 'authenticated', 'coach@aiconsent.local', '', now(), now());

insert into coach_athletes (id, coach_id, athlete_id, status, invite_token, accepted_at) values
  ('ca524000-0000-0000-0000-0000000000e1', 'ca524000-0000-0000-0000-00000000000c',
   'ca524000-0000-0000-0000-00000000000a', 'active', 'aiconsent-active', now());

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"ca524000-0000-0000-0000-00000000000c","role":"authenticated"}';

select throws_ok(
  $$insert into direct_messages (sender_id, recipient_id, body, kind)
    values ('ca524000-0000-0000-0000-00000000000c', 'ca524000-0000-0000-0000-00000000000a', 'drafted', 'ai_assisted')$$,
  '42501', null,
  'an active coach whose athlete never consented cannot mark a message ai_assisted');

select lives_ok(
  $$insert into direct_messages (sender_id, recipient_id, body, kind)
    values ('ca524000-0000-0000-0000-00000000000c', 'ca524000-0000-0000-0000-00000000000a', 'plain', 'text')$$,
  'the same coach still sends that athlete a plain message');

set local "request.jwt.claims" = '{"sub":"ca524000-0000-0000-0000-00000000000a","role":"authenticated"}';
select ok(
  (select ai_assist_consent_version = 1
     from set_coach_ai_assist_consent('ca524000-0000-0000-0000-0000000000e1', 1::smallint)),
  'the athlete consents');

set local "request.jwt.claims" = '{"sub":"ca524000-0000-0000-0000-00000000000c","role":"authenticated"}';
select lives_ok(
  $$insert into direct_messages (sender_id, recipient_id, body, kind)
    values ('ca524000-0000-0000-0000-00000000000c', 'ca524000-0000-0000-0000-00000000000a', 'drafted', 'ai_assisted')$$,
  'with consent on the link the coach sends an ai_assisted message');

set local "request.jwt.claims" = '{"sub":"ca524000-0000-0000-0000-00000000000a","role":"authenticated"}';
select ok(
  (select ai_assist_consent_version is null
     from set_coach_ai_assist_consent('ca524000-0000-0000-0000-0000000000e1', null)),
  'the athlete withdraws');

set local "request.jwt.claims" = '{"sub":"ca524000-0000-0000-0000-00000000000c","role":"authenticated"}';
select throws_ok(
  $$insert into direct_messages (sender_id, recipient_id, body, kind)
    values ('ca524000-0000-0000-0000-00000000000c', 'ca524000-0000-0000-0000-00000000000a', 'drafted again', 'ai_assisted')$$,
  '42501', null,
  'after the withdrawal the coach can no longer mark a message ai_assisted');

select * from finish();
rollback;
