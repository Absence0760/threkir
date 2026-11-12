-- Pins 20271210001217 (issue #1215 Phase 4): only the athlete grants or
-- withdraws the coach assistant on their own active link, a coach can never
-- mint a consented link, ending a link drops the consent, and only an active
-- coach may mark a message to their athlete as AI-assisted.

begin;
select plan(17);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('ca500000-0000-0000-0000-00000000000a', 'authenticated', 'authenticated', 'athlete@coachassist.local', '', now(), now()),
  ('ca500000-0000-0000-0000-00000000000c', 'authenticated', 'authenticated', 'coach@coachassist.local', '', now(), now()),
  ('ca500000-0000-0000-0000-00000000000d', 'authenticated', 'authenticated', 'other@coachassist.local', '', now(), now());

insert into coach_athletes (id, coach_id, athlete_id, status, invite_token, accepted_at) values
  ('ca500000-0000-0000-0000-0000000000e1', 'ca500000-0000-0000-0000-00000000000c', 'ca500000-0000-0000-0000-00000000000a', 'active', 'coachassist-active', now()),
  ('ca500000-0000-0000-0000-0000000000e2', 'ca500000-0000-0000-0000-00000000000d', 'ca500000-0000-0000-0000-00000000000a', 'ended', 'coachassist-ended', now());

select is(coach_assist_consent_current_version(), 1::smallint, 'the athlete-side copy is at version 1');

set local role authenticated;

-- ── The coach cannot consent for the athlete ────────────────────────────
set local "request.jwt.claims" = '{"sub":"ca500000-0000-0000-0000-00000000000c","role":"authenticated"}';

select throws_ok(
  $$select set_coach_ai_assist_consent('ca500000-0000-0000-0000-0000000000e1', 1::smallint)$$,
  'P0002', 'set_coach_ai_assist_consent: link not found',
  'the coach cannot grant the athlete''s consent');
select throws_ok(
  $$insert into coach_athletes (coach_id, status, invite_token, ai_assist_consent_version, ai_assist_consent_at)
    values ('ca500000-0000-0000-0000-00000000000c', 'pending', 'coachassist-forged', 1, now())$$,
  '42501', null,
  'a coach cannot mint an invite that arrives consented');
select lives_ok(
  $$insert into coach_athletes (coach_id, status, invite_token)
    values ('ca500000-0000-0000-0000-00000000000c', 'pending', 'coachassist-plain')$$,
  'an ordinary invite still works');

-- ── The athlete ─────────────────────────────────────────────────────────
set local "request.jwt.claims" = '{"sub":"ca500000-0000-0000-0000-00000000000a","role":"authenticated"}';

select ok(
  (select ai_assist_consent_version = 1 and ai_assist_consent_at is not null and invite_token is null
     from set_coach_ai_assist_consent('ca500000-0000-0000-0000-0000000000e1', 1::smallint)),
  'the athlete allows the assistant on their link, and the row comes back without the invite token');
select is(
  (select ai_assist_consent_version from coach_athletes where id = 'ca500000-0000-0000-0000-0000000000e1'),
  1::smallint,
  'the consent is stored');
select throws_ok(
  $$select set_coach_ai_assist_consent('ca500000-0000-0000-0000-0000000000e1', 2::smallint)$$,
  '22023', null,
  'a version the copy does not have is refused');
select throws_ok(
  $$select set_coach_ai_assist_consent('ca500000-0000-0000-0000-0000000000e1', 0::smallint)$$,
  '22023', null,
  'version 0 is refused');
select throws_ok(
  $$select set_coach_ai_assist_consent('ca500000-0000-0000-0000-0000000000e2', 1::smallint)$$,
  'P0002', null,
  'an ended link cannot be consented');
select throws_ok(
  $$insert into direct_messages (sender_id, recipient_id, body, kind)
    values ('ca500000-0000-0000-0000-00000000000a', 'ca500000-0000-0000-0000-00000000000c', 'hi coach', 'ai_assisted')$$,
  '42501', null,
  'the athlete has no assistant to declare');
select ok(
  (select ai_assist_consent_version is null and ai_assist_consent_at is null
     from set_coach_ai_assist_consent('ca500000-0000-0000-0000-0000000000e1', null)),
  'the athlete withdraws');
select ok(
  (select ai_assist_consent_version = 1
     from set_coach_ai_assist_consent('ca500000-0000-0000-0000-0000000000e1', 1::smallint)),
  'and grants again');

-- ── Someone else ────────────────────────────────────────────────────────
set local "request.jwt.claims" = '{"sub":"ca500000-0000-0000-0000-00000000000d","role":"authenticated"}';

select throws_ok(
  $$select set_coach_ai_assist_consent('ca500000-0000-0000-0000-0000000000e1', null)$$,
  'P0002', null,
  'a stranger cannot withdraw it either');

-- ── The coach marks a message ───────────────────────────────────────────
set local "request.jwt.claims" = '{"sub":"ca500000-0000-0000-0000-00000000000c","role":"authenticated"}';

select lives_ok(
  $$insert into direct_messages (sender_id, recipient_id, body, kind)
    values ('ca500000-0000-0000-0000-00000000000c', 'ca500000-0000-0000-0000-00000000000a', 'easy week', 'ai_assisted')$$,
  'the active coach sends an AI-assisted message to their athlete');
select throws_ok(
  $$insert into direct_messages (sender_id, recipient_id, body, kind)
    values ('ca500000-0000-0000-0000-00000000000c', 'ca500000-0000-0000-0000-00000000000a', 'x', 'coach_share')$$,
  '42501', null,
  'the coach still cannot write a coach_share');

-- ── Ending the link drops the consent ───────────────────────────────────
set local "request.jwt.claims" = '{"sub":"ca500000-0000-0000-0000-00000000000a","role":"authenticated"}';

select ok(end_coach_link('ca500000-0000-0000-0000-0000000000e1'), 'the athlete ends the link');
select ok(
  (select ai_assist_consent_version is null and ai_assist_consent_at is null
     from coach_athletes where id = 'ca500000-0000-0000-0000-0000000000e1'),
  'the ended link keeps no consent');

select * from finish();
rollback;
