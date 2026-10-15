-- Pins migration 20270827000001: a route-bucket slot the billed handler can
-- give back on a provider failure, and that the runner cannot give back
-- themselves after a call that succeeded.
--
-- The refund is keyed on a ticket `spend_rate_limit_slot` hands only to the
-- caller of that spend. So the properties that matter are: a spend counts
-- exactly as `check_rate_limit` does; its ticket refunds once and only once;
-- a ticket the caller does not hold refunds nothing; one runner cannot touch
-- another's bucket; and the ticket is not readable off the row.

begin;

select plan(14);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('7e000000-0000-0000-0000-0000000000a1', 'authenticated', 'authenticated',
   'refund-a@rl.local', '', now(), now()),
  ('7e000000-0000-0000-0000-0000000000b2', 'authenticated', 'authenticated',
   'refund-b@rl.local', '', now(), now());

select tests.confirm_consent();

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"7e000000-0000-0000-0000-0000000000a1","role":"authenticated"}';

-- (1) A spend under the ceiling is allowed and carries a ticket.
-- The tickets are parked in transaction-local settings, which survive the
-- role switches below where a temp table's privileges would not.
select set_config('rl_test.first', coalesce((select spend_id::text
    from spend_rate_limit_slot('7e000000-0000-0000-0000-0000000000a1', 'plate-photo', 2, 3600)), ''), true);
select isnt(nullif(current_setting('rl_test.first'), ''), null,
  'an allowed spend returns a refund ticket');

select set_config('rl_test.second', coalesce((select spend_id::text
    from spend_rate_limit_slot('7e000000-0000-0000-0000-0000000000a1', 'plate-photo', 2, 3600)), ''), true);

-- (2) It shares the window counter with check_rate_limit: the third call in
-- a window of two is refused, with no ticket.
select results_eq(
  $$ select allowed, spend_id is null
       from spend_rate_limit_slot('7e000000-0000-0000-0000-0000000000a1', 'plate-photo', 2, 3600) $$,
  $$ values (false, true) $$,
  'past the ceiling the spend is refused and carries no ticket');

-- (3) A refund for the first ticket gives a slot back...
select is(
  refund_rate_limit_slot('7e000000-0000-0000-0000-0000000000a1', 'plate-photo',
                         current_setting('rl_test.first')::uuid),
  true,
  'the holder of a ticket can refund it');

-- (4) ...so the window has room again. Three calls counted (the refused one
-- too) and one was refunded, so a ceiling of 3 admits the next call; without
-- the refund it would be the fourth.
select is(
  (select allowed from check_rate_limit('7e000000-0000-0000-0000-0000000000a1', 'plate-photo', 3, 3600)),
  true,
  'the refunded slot is spendable');

-- (5) The same ticket refunds only once.
select is(
  refund_rate_limit_slot('7e000000-0000-0000-0000-0000000000a1', 'plate-photo',
                         current_setting('rl_test.first')::uuid),
  false,
  'a consumed ticket refunds nothing');

-- (6) A made-up ticket refunds nothing: this is what stops a runner resetting
-- their own ceiling after a call that succeeded.
select is(
  refund_rate_limit_slot('7e000000-0000-0000-0000-0000000000a1', 'plate-photo',
                         gen_random_uuid()),
  false,
  'a ticket the caller was never given refunds nothing');

-- (7) A ticket only refunds in the bucket it was spent in.
select is(
  refund_rate_limit_slot('7e000000-0000-0000-0000-0000000000a1', 'route-request',
                         current_setting('rl_test.second')::uuid),
  false,
  'a ticket from one bucket refunds nothing in another');

-- (8) The ticket is not readable off the row: RLS has no policy at all.
select is(
  (select count(*)::int from rate_limits
    where user_id = '7e000000-0000-0000-0000-0000000000a1'),
  0,
  'a signed-in runner cannot read their own rate_limits rows, tickets included');

-- (9) / (10) Neither function accepts another runner's id.
select throws_ok(
  $$ select refund_rate_limit_slot('7e000000-0000-0000-0000-0000000000b2', 'plate-photo', gen_random_uuid()) $$,
  '42501',
  'refund_rate_limit_slot: not authorized',
  'a runner cannot refund in another runner''s bucket');
select throws_ok(
  $$ select * from spend_rate_limit_slot('7e000000-0000-0000-0000-0000000000b2', 'plate-photo', 2, 3600) $$,
  '42501',
  'spend_rate_limit_slot: not authorized',
  'a runner cannot spend from another runner''s bucket');

-- (11) A bare refund cannot drive the count below zero, even with a real
-- ticket replayed after the window was otherwise emptied.
reset role;
update rate_limits set count = 0
 where user_id = '7e000000-0000-0000-0000-0000000000a1' and bucket = 'plate-photo';
set local role authenticated;
select is(
  refund_rate_limit_slot('7e000000-0000-0000-0000-0000000000a1', 'plate-photo',
                         current_setting('rl_test.second')::uuid),
  true,
  'the second ticket is still unconsumed');
reset role;
select is(
  (select count from rate_limits
    where user_id = '7e000000-0000-0000-0000-0000000000a1' and bucket = 'plate-photo'),
  0,
  'a refund floors the window count at zero');

-- (12) The ticket list is bounded: a flood of direct spends keeps the newest
-- 32, so a runner cannot grow their row without limit.
set local role authenticated;
do $flood$
declare i int;
begin
  for i in 1..40 loop
    perform spend_rate_limit_slot('7e000000-0000-0000-0000-0000000000a1', 'flood', 1000, 3600);
  end loop;
end
$flood$;
reset role;
select is(
  (select cardinality(refundable_spends) from rate_limits
    where user_id = '7e000000-0000-0000-0000-0000000000a1' and bucket = 'flood'),
  32,
  'the ticket list holds the newest 32 spends');

-- (13) Anonymous callers hold no EXECUTE on either function.
select ok(
  not has_function_privilege('anon', 'public.refund_rate_limit_slot(uuid, text, uuid)', 'execute')
  and not has_function_privilege('anon', 'public.spend_rate_limit_slot(uuid, text, integer, integer)', 'execute'),
  'anon cannot execute the spend or the refund');

select * from finish();
rollback;
