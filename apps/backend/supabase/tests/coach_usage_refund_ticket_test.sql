-- Pins migration 20270829000011: the AI Coach daily counter refunds only
-- through a ticket the spend handed to its caller, so a runner cannot reset
-- their own cap after a message that succeeded.
--
-- What matters: a spend counts exactly as increment_coach_usage does and
-- returns a ticket; that ticket refunds once and only once, from the day
-- bucket it was spent in; a ticket the caller never held, a used one and
-- another runner's refund nothing; neither RPC accepts another runner's id;
-- the tickets are unreadable to the runner and retire with their usage row;
-- and the bare per-user decrement is gone.

begin;

select plan(19);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('c0a50000-0000-0000-0000-0000000000a1', 'authenticated', 'authenticated',
   'ticket-a@coach.local', '', now(), now()),
  ('c0a50000-0000-0000-0000-0000000000b2', 'authenticated', 'authenticated',
   'ticket-b@coach.local', '', now(), now());

select tests.confirm_consent();

-- (1) The bare decrement is gone, from every role.
select hasnt_function('public', 'decrement_coach_usage', array['uuid'],
  'decrement_coach_usage no longer exists, so no client can reset the counter');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c0a50000-0000-0000-0000-0000000000a1","role":"authenticated"}';

-- (2) A spend counts and carries a ticket. Tickets are parked in
-- transaction-local settings, which survive the role switches below.
select set_config('coach_test.first', coalesce((select spend_id::text
    from spend_coach_usage_slot('c0a50000-0000-0000-0000-0000000000a1')), ''), true);
select isnt(nullif(current_setting('coach_test.first'), ''), null,
  'a spend returns a refund ticket');

-- (3) The count it returns is the rolling count after the bump.
select set_config('coach_test.second', coalesce((select spend_id::text
    from spend_coach_usage_slot('c0a50000-0000-0000-0000-0000000000a1')), ''), true);
select is(get_coach_usage('c0a50000-0000-0000-0000-0000000000a1'), 2,
  'two spends count two messages');

-- (4) A message that succeeded cannot be undone by a direct call: the runner
-- holds no ticket for it, and a made-up one refunds nothing.
select is(
  refund_coach_usage_slot('c0a50000-0000-0000-0000-0000000000a1', gen_random_uuid()),
  false,
  'a ticket the caller was never given refunds nothing');
select is(
  refund_coach_usage_slot('c0a50000-0000-0000-0000-0000000000a1', null),
  false,
  'a refund with no ticket refunds nothing');
select is(get_coach_usage('c0a50000-0000-0000-0000-0000000000a1'), 2,
  'the count is untouched by the refused refunds');

-- (5) The holder of a real ticket gets exactly one message back.
select is(
  refund_coach_usage_slot('c0a50000-0000-0000-0000-0000000000a1',
                          current_setting('coach_test.first')::uuid),
  true,
  'the spend''s own ticket refunds');
select is(get_coach_usage('c0a50000-0000-0000-0000-0000000000a1'), 1,
  'the refund gives back one message');

-- (6) The same ticket refunds only once.
select is(
  refund_coach_usage_slot('c0a50000-0000-0000-0000-0000000000a1',
                          current_setting('coach_test.first')::uuid),
  false,
  'a consumed ticket refunds nothing');
select is(get_coach_usage('c0a50000-0000-0000-0000-0000000000a1'), 1,
  'a replayed ticket does not lower the count again');

-- (7) The tickets are not readable by the runner, so one cannot be lifted
-- off the table and replayed.
select throws_ok(
  $$ select count(*) from private.coach_usage_refund_tickets $$,
  '42501', null,
  'a signed-in runner cannot read the refund tickets');

-- (8) Neither RPC accepts another runner's id.
select throws_ok(
  $$ select * from spend_coach_usage_slot('c0a50000-0000-0000-0000-0000000000b2') $$,
  '42501', 'spend_coach_usage_slot: not authorized',
  'a runner cannot spend from another runner''s counter');
select throws_ok(
  $$ select refund_coach_usage_slot('c0a50000-0000-0000-0000-0000000000b2', gen_random_uuid()) $$,
  '42501', 'refund_coach_usage_slot: not authorized',
  'a runner cannot refund on another runner''s counter');

-- (9) Another runner cannot use A's ticket on their own counter: B spends
-- once (so B has a row and a count to lower), then offers A's live ticket.
set local "request.jwt.claims" = '{"sub":"c0a50000-0000-0000-0000-0000000000b2","role":"authenticated"}';
select spend_id from spend_coach_usage_slot('c0a50000-0000-0000-0000-0000000000b2');
select is(
  refund_coach_usage_slot('c0a50000-0000-0000-0000-0000000000b2',
                          current_setting('coach_test.second')::uuid),
  false,
  'another runner''s ticket refunds nothing');
select is(get_coach_usage('c0a50000-0000-0000-0000-0000000000b2'), 1,
  'the borrowed ticket left the borrower''s count where it was');

-- (10) A refund lowers the day bucket the spend landed in, not today's: a
-- spend at 23:59 UTC refunded at 00:01 gives back the right day.
reset role;
insert into user_coach_usage (user_id, usage_date, message_count)
  values ('c0a50000-0000-0000-0000-0000000000a1', current_date - 1, 1);
insert into private.coach_usage_refund_tickets (user_id, usage_date, tickets)
  values ('c0a50000-0000-0000-0000-0000000000a1', current_date - 1,
          array['c0a5ffff-0000-0000-0000-000000000001'::uuid]);
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c0a50000-0000-0000-0000-0000000000a1","role":"authenticated"}';
select refund_coach_usage_slot('c0a50000-0000-0000-0000-0000000000a1',
                               'c0a5ffff-0000-0000-0000-000000000001');
reset role;
select results_eq(
  $$ select usage_date = current_date, message_count
       from user_coach_usage
      where user_id = 'c0a50000-0000-0000-0000-0000000000a1'
      order by usage_date $$,
  $$ values (false, 0), (true, 1) $$,
  'the refund lowered yesterday''s bucket and left today''s alone');

-- (11) The tickets retire with their usage row (the retention sweep and
-- account deletion both delete that row).
delete from user_coach_usage
 where user_id = 'c0a50000-0000-0000-0000-0000000000a1' and usage_date = current_date - 1;
select is(
  (select count(*)::int from private.coach_usage_refund_tickets
    where user_id = 'c0a50000-0000-0000-0000-0000000000a1' and usage_date = current_date - 1),
  0,
  'deleting a usage row deletes its tickets');

-- (12) The ticket list is bounded: a flood of direct spends keeps the newest 32.
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"c0a50000-0000-0000-0000-0000000000a1","role":"authenticated"}';
do $flood$
declare i int;
begin
  for i in 1..40 loop
    perform spend_coach_usage_slot('c0a50000-0000-0000-0000-0000000000a1');
  end loop;
end
$flood$;
reset role;
select is(
  (select cardinality(tickets) from private.coach_usage_refund_tickets
    where user_id = 'c0a50000-0000-0000-0000-0000000000a1' and usage_date = current_date),
  32,
  'the ticket list holds the newest 32 spends');

-- (13) Anonymous callers hold no EXECUTE on either function.
select ok(
  not has_function_privilege('anon', 'public.spend_coach_usage_slot(uuid)', 'execute')
  and not has_function_privilege('anon', 'public.refund_coach_usage_slot(uuid, uuid)', 'execute'),
  'anon cannot execute the spend or the refund');

select * from finish();
rollback;
