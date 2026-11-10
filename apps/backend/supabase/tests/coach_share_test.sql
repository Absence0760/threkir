-- Pins 20271210001215 (issue #1215 Phase 3): an athlete shares paragraphs of
-- their own AI Coach answer with their active coach. Only the RPC writes a
-- coach_share message, it copies the text server-side, and every refusal is
-- the one the migration names.

begin;
select plan(36);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('c5000000-0000-0000-0000-00000000000a', 'authenticated', 'authenticated', 'athlete@coachshare.local', '', now(), now()),
  ('c5000000-0000-0000-0000-00000000000c', 'authenticated', 'authenticated', 'coach@coachshare.local', '', now(), now()),
  ('c5000000-0000-0000-0000-00000000000d', 'authenticated', 'authenticated', 'other@coachshare.local', '', now(), now()),
  ('c5000000-0000-0000-0000-00000000000e', 'authenticated', 'authenticated', 'ended@coachshare.local', '', now(), now());

insert into coach_athletes (coach_id, athlete_id, status, invite_token, accepted_at) values
  ('c5000000-0000-0000-0000-00000000000c', 'c5000000-0000-0000-0000-00000000000a', 'active', 'coachshare-active', now()),
  ('c5000000-0000-0000-0000-00000000000e', 'c5000000-0000-0000-0000-00000000000a', 'ended', 'coachshare-ended', now());

insert into coach_messages (id, user_id, role, content) values
  ('c5000000-0000-0000-0000-0000000000a1', 'c5000000-0000-0000-0000-00000000000a', 'assistant',
   E'First para.\n\n\n  Second\nline  \n \t\nThird\r\n\r\nFourth\n\n'),
  ('c5000000-0000-0000-0000-0000000000a2', 'c5000000-0000-0000-0000-00000000000a', 'user', 'my own question'),
  ('c5000000-0000-0000-0000-0000000000a3', 'c5000000-0000-0000-0000-00000000000a', 'assistant', repeat('x', 4001)),
  ('c5000000-0000-0000-0000-0000000000d1', 'c5000000-0000-0000-0000-00000000000d', 'assistant', 'someone else''s answer');

insert into private.feature_flags (name, enabled) values ('coach_share', false)
  on conflict (name) do update set enabled = false;

-- ── Grants and the split ────────────────────────────────────────────────

select ok(
  has_column_privilege('authenticated', 'public.direct_messages', 'kind', 'SELECT'),
  'authenticated can select direct_messages.kind');
select ok(
  has_column_privilege('authenticated', 'public.direct_messages', 'coach_message_id', 'SELECT'),
  'authenticated can select direct_messages.coach_message_id');
select is(
  private.coach_answer_paragraphs(E'First para.\n\n\n  Second\nline  \n \t\nThird\r\n\r\nFourth\n\n'),
  array['First para.', E'Second\nline', 'Third', 'Fourth'],
  'the answer splits as coach_share.ts / coach_share.dart split it');
select is(private.coach_answer_paragraphs(E'   \n\n  '), '{}'::text[], 'a blank answer has no paragraphs');
select throws_ok(
  $$select share_coach_message('c5000000-0000-0000-0000-0000000000a1', 'c5000000-0000-0000-0000-00000000000c', array[0])$$,
  '42501', null,
  'share_coach_message refuses a caller with no session');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c5000000-0000-0000-0000-00000000000a","role":"authenticated"}';

select is(public.coach_share_enabled(), false, 'the gate reads closed');
select throws_ok(
  $$select share_coach_message('c5000000-0000-0000-0000-0000000000a1', 'c5000000-0000-0000-0000-00000000000c', array[0])$$,
  '0A000', 'share_coach_message: sharing with a coach is not available',
  'the RPC refuses while the gate is closed');

reset role;
update private.feature_flags set enabled = true where name = 'coach_share';
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c5000000-0000-0000-0000-00000000000a","role":"authenticated"}';

select is(public.coach_share_enabled(), true, 'the gate reads open');

-- ── A client cannot write a card itself ─────────────────────────────────

select throws_ok(
  $$insert into direct_messages (sender_id, recipient_id, body, kind)
    values ('c5000000-0000-0000-0000-00000000000a', 'c5000000-0000-0000-0000-00000000000c', 'I am the AI', 'coach_share')$$,
  '42501', null,
  'a direct insert of kind coach_share is refused');
select throws_ok(
  $$insert into direct_messages (sender_id, recipient_id, body, coach_message_id)
    values ('c5000000-0000-0000-0000-00000000000a', 'c5000000-0000-0000-0000-00000000000c', 'x',
            'c5000000-0000-0000-0000-0000000000a1')$$,
  '42501', null,
  'a direct insert naming a coach_message_id is refused');

-- ── The share ───────────────────────────────────────────────────────────

select is(
  (select body from share_coach_message('c5000000-0000-0000-0000-0000000000a1', 'c5000000-0000-0000-0000-00000000000c', array[3, 1, 1])),
  E'Second\nline\n\nFourth',
  'the card holds the picked paragraphs in answer order, repeats dropped');
select is(
  (select kind from direct_messages where sender_id = 'c5000000-0000-0000-0000-00000000000a' order by created_at desc limit 1),
  'coach_share',
  'the message is a coach_share');
select is(
  (select coach_message_id from direct_messages where sender_id = 'c5000000-0000-0000-0000-00000000000a' order by created_at desc limit 1),
  'c5000000-0000-0000-0000-0000000000a1'::uuid,
  'it links back to the answer');
select ok(
  (select read_at is null and original_body is null
     from share_coach_message('c5000000-0000-0000-0000-0000000000a1', 'c5000000-0000-0000-0000-00000000000c', array[0])),
  'the returned row carries neither read_at nor original_body');

-- ── Refusals ────────────────────────────────────────────────────────────

select throws_ok(
  $$select share_coach_message('c5000000-0000-0000-0000-0000000000a2', 'c5000000-0000-0000-0000-00000000000c', array[0])$$,
  'P0002', 'share_coach_message: answer not found',
  'the athlete''s own question is not an AI answer');
select throws_ok(
  $$select share_coach_message('c5000000-0000-0000-0000-0000000000d1', 'c5000000-0000-0000-0000-00000000000c', array[0])$$,
  'P0002', 'share_coach_message: answer not found',
  'someone else''s answer cannot be shared');
select throws_ok(
  $$select share_coach_message('c5000000-0000-0000-0000-0000000000a1', 'c5000000-0000-0000-0000-00000000000d', array[0])$$,
  '42501', 'share_coach_message: not your coach',
  'a recipient who is not the athlete''s coach is refused');
select throws_ok(
  $$select share_coach_message('c5000000-0000-0000-0000-0000000000a1', 'c5000000-0000-0000-0000-00000000000e', array[0])$$,
  '42501', 'share_coach_message: not your coach',
  'a coach whose link ended is refused');
select throws_ok(
  $$select share_coach_message('c5000000-0000-0000-0000-0000000000a1', 'c5000000-0000-0000-0000-00000000000c', '{}')$$,
  '22023', null,
  'no paragraph is refused');
select throws_ok(
  $$select share_coach_message('c5000000-0000-0000-0000-0000000000a1', 'c5000000-0000-0000-0000-00000000000c', array[4])$$,
  '22023', null,
  'a paragraph past the end is refused');
select throws_ok(
  $$select share_coach_message('c5000000-0000-0000-0000-0000000000a1', 'c5000000-0000-0000-0000-00000000000c', array[-1, 0])$$,
  '22023', null,
  'a negative paragraph is refused');
select throws_ok(
  $$select share_coach_message('c5000000-0000-0000-0000-0000000000a3', 'c5000000-0000-0000-0000-00000000000c', array[0])$$,
  '22001', null,
  'an excerpt past 4000 characters is refused');

-- ── A card cannot be edited; unsend drops the link back ─────────────────

select throws_ok(
  format($$select edit_direct_message(%L, 'now I wrote this')$$,
    (select id from direct_messages where kind = 'coach_share' and sender_id = 'c5000000-0000-0000-0000-00000000000a' limit 1)),
  '55000', 'edit_direct_message: message can no longer be edited',
  'the athlete cannot rewrite a card under its AI label');

select ok(
  (select unsent_at is not null and body is null and coach_message_id is null
     from unsend_direct_message(
       (select id from direct_messages where kind = 'coach_share' and sender_id = 'c5000000-0000-0000-0000-00000000000a'
         order by created_at limit 1))),
  'unsend clears the text and the link back');

-- ── The coach reads it ──────────────────────────────────────────────────

set local "request.jwt.claims" = '{"sub":"c5000000-0000-0000-0000-00000000000c","role":"authenticated"}';

select is(
  (select count(*)::int from direct_messages where kind = 'coach_share' and recipient_id = 'c5000000-0000-0000-0000-00000000000c'),
  2,
  'the coach reads both cards');
select is(
  (select count(*)::int from coach_messages where user_id = 'c5000000-0000-0000-0000-00000000000a'),
  0,
  'the coach still cannot read the athlete''s Coach conversation');
select throws_ok(
  $$select share_coach_message('c5000000-0000-0000-0000-0000000000a1', 'c5000000-0000-0000-0000-00000000000a', array[0])$$,
  'P0002', 'share_coach_message: answer not found',
  'the coach cannot share the athlete''s answer');
select is(
  (select last_kind from dm_threads() where partner_id = 'c5000000-0000-0000-0000-00000000000a'),
  'coach_share',
  'the coach''s inbox knows the newest message is a shared AI answer');
select is(
  (select request_state from conversation_participants
    where user_id = 'c5000000-0000-0000-0000-00000000000c'
      and conversation_id = (select conversation_id from direct_messages
                              where sender_id = 'c5000000-0000-0000-0000-00000000000a' limit 1)),
  null,
  'the coaching link admits the card as an ordinary message, not a request');
select ok(
  exists (select 1 from notifications
           where user_id = 'c5000000-0000-0000-0000-00000000000c'
             and actor_id = 'c5000000-0000-0000-0000-00000000000a'
             and kind = 'message'),
  'the coach is notified');
select lives_ok(
  $$insert into direct_messages (sender_id, recipient_id, body)
    values ('c5000000-0000-0000-0000-00000000000c', 'c5000000-0000-0000-0000-00000000000a', 'thanks, noted')$$,
  'the coach can reply with no follow edge between them');

-- ── Blocks ──────────────────────────────────────────────────────────────

reset role;
insert into user_blocks (blocker_id, blocked_id) values
  ('c5000000-0000-0000-0000-00000000000c', 'c5000000-0000-0000-0000-00000000000a');
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c5000000-0000-0000-0000-00000000000a","role":"authenticated"}';

select throws_ok(
  $$select share_coach_message('c5000000-0000-0000-0000-0000000000a1', 'c5000000-0000-0000-0000-00000000000c', array[0])$$,
  '42501', 'share_coach_message: not your coach',
  'a coach who blocked the athlete is refused, with the same answer');

reset role;
delete from user_blocks where blocker_id = 'c5000000-0000-0000-0000-00000000000c';

-- ── The source going away keeps the card ────────────────────────────────

delete from coach_messages where id = 'c5000000-0000-0000-0000-0000000000a1';

select is(
  (select count(*)::int from direct_messages where kind = 'coach_share' and sender_id = 'c5000000-0000-0000-0000-00000000000a'),
  2,
  'deleting the answer keeps the cards the coach received');
select is(
  (select count(*)::int from direct_messages where coach_message_id is not null and sender_id = 'c5000000-0000-0000-0000-00000000000a'),
  0,
  'and nulls their link back');

-- ── The CHECKs ──────────────────────────────────────────────────────────

select throws_ok(
  $$insert into direct_messages (sender_id, recipient_id, body, kind)
    values ('c5000000-0000-0000-0000-00000000000a', 'c5000000-0000-0000-0000-00000000000c', 'x', 'html')$$,
  '23514', null,
  'an unknown kind is refused by the CHECK');
select throws_ok(
  $$insert into direct_messages (sender_id, recipient_id, body, kind, coach_message_id)
    values ('c5000000-0000-0000-0000-00000000000a', 'c5000000-0000-0000-0000-00000000000c', 'x', 'text',
            'c5000000-0000-0000-0000-0000000000a2')$$,
  '23514', null,
  'a text message cannot carry a coach_message_id');

select * from finish();
rollback;
