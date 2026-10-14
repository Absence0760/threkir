-- The claim-window edges (migration 20270726000002, decisions § 1840) that
-- event_waitlist_claim_window_test.sql leaves open:
--   * a seat freed on a cancelled occurrence offers nobody;
--   * one fill pass with two free seats makes two offers, and no third;
--   * an offer whose holder's pending checkout has itself expired is lapsed by
--     the mover, the seat goes to the next waiter, and the lapsed holder is
--     never offered it again;
--   * a holder who pays after the lapse is demoted to the waitlist by the
--     capacity trigger and keeps their paid order -- the money is held for the
--     next seat, which they are seated in ahead of anyone unpaid (the webhook's
--     oversold arm; no refund is automatic, § 1833 leaves that arm manual);
--   * the notification names the occurrence whose attendee row carries the
--     deadline -- the notification row itself has no deadline column, and the
--     rails point the reader at the event page for it;
--   * neither the mover nor the fill is executable by a client role.

begin;
select plan(18);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('aaaa7732-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'cw-host@evt.local', '', now(), now()),
  ('aaaa7732-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'cw-a@evt.local', '', now(), now()),
  ('aaaa7732-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'cw-w1@evt.local', '', now(), now()),
  ('aaaa7732-0000-0000-0000-000000000004', 'authenticated', 'authenticated', 'cw-w2@evt.local', '', now(), now()),
  ('aaaa7732-0000-0000-0000-000000000005', 'authenticated', 'authenticated', 'cw-w3@evt.local', '', now(), now());

insert into clubs (id, owner_id, name, slug, is_public)
values ('bbbb7732-0000-0000-0000-000000000001',
        'aaaa7732-0000-0000-0000-000000000001', 'Claim Window Studio', 'cw-studio', true);

insert into instructor_payout_accounts (user_id, stripe_connect_account_id, charges_enabled)
values ('aaaa7732-0000-0000-0000-000000000001', 'acct_test_cw_host', true);

-- E1: cancelled occurrence. E2: two seats. E3: the lapse walk. All priced.
insert into events (id, club_id, title, starts_at, author_id, host_user_id, category, capacity)
select e, 'bbbb7732-0000-0000-0000-000000000001', t, now() + interval '7 days',
       'aaaa7732-0000-0000-0000-000000000001', 'aaaa7732-0000-0000-0000-000000000001', 'class', c
from (values ('cccc7732-0000-0000-0000-000000000001'::uuid, 'Cancelled Flow', 1),
             ('cccc7732-0000-0000-0000-000000000002'::uuid, 'Two Mats', 2),
             ('cccc7732-0000-0000-0000-000000000003'::uuid, 'Lapse Walk', 1)) v(e, t, c);

insert into event_pricing (event_id, price_cents)
values ('cccc7732-0000-0000-0000-000000000001', 2200),
       ('cccc7732-0000-0000-0000-000000000002', 2200),
       ('cccc7732-0000-0000-0000-000000000003', 2200);

create temp table t_occ as select now() + interval '7 days' as i;

-- A holds a paid seat on E1 and E3.
insert into event_orders (id, event_id, instance_start, buyer_user_id, host_user_id,
                          amount_cents, platform_fee_cents, status, paid_at)
select o, e, i, 'aaaa7732-0000-0000-0000-000000000002', 'aaaa7732-0000-0000-0000-000000000001',
       2200, 110, 'paid', now()
from t_occ, (values ('dddd7732-0000-0000-0000-000000000001'::uuid, 'cccc7732-0000-0000-0000-000000000001'::uuid),
                    ('dddd7732-0000-0000-0000-000000000003'::uuid, 'cccc7732-0000-0000-0000-000000000003'::uuid)) v(o, e);
insert into event_attendees (event_id, user_id, status, instance_start, order_id)
select e, 'aaaa7732-0000-0000-0000-000000000002', 'going', i, o
from t_occ, (values ('dddd7732-0000-0000-0000-000000000001'::uuid, 'cccc7732-0000-0000-0000-000000000001'::uuid),
                    ('dddd7732-0000-0000-0000-000000000003'::uuid, 'cccc7732-0000-0000-0000-000000000003'::uuid)) v(o, e);

-- Unpaid waitlisters, in joining order.
insert into event_attendees (event_id, user_id, status, instance_start, joined_at)
select e, u, 'waitlisted', i, j
from t_occ, (values
  ('cccc7732-0000-0000-0000-000000000001'::uuid, 'aaaa7732-0000-0000-0000-000000000003'::uuid, now() - interval '3 hours'),
  ('cccc7732-0000-0000-0000-000000000002'::uuid, 'aaaa7732-0000-0000-0000-000000000003'::uuid, now() - interval '3 hours'),
  ('cccc7732-0000-0000-0000-000000000002'::uuid, 'aaaa7732-0000-0000-0000-000000000004'::uuid, now() - interval '2 hours'),
  ('cccc7732-0000-0000-0000-000000000002'::uuid, 'aaaa7732-0000-0000-0000-000000000005'::uuid, now() - interval '1 hour'),
  ('cccc7732-0000-0000-0000-000000000003'::uuid, 'aaaa7732-0000-0000-0000-000000000003'::uuid, now() - interval '3 hours'),
  ('cccc7732-0000-0000-0000-000000000003'::uuid, 'aaaa7732-0000-0000-0000-000000000004'::uuid, now() - interval '2 hours')
) v(e, u, j);

-- ── E1: a cancelled occurrence offers nobody ──
insert into event_exceptions (event_id, instance_start, cancelled_by)
select 'cccc7732-0000-0000-0000-000000000001', i, 'aaaa7732-0000-0000-0000-000000000001' from t_occ;
delete from event_attendees
where event_id = 'cccc7732-0000-0000-0000-000000000001'
  and user_id = 'aaaa7732-0000-0000-0000-000000000002';

select is(
  (select offer_expires_at from event_attendees
   where event_id = 'cccc7732-0000-0000-0000-000000000001'
     and user_id = 'aaaa7732-0000-0000-0000-000000000003'),
  null, 'a seat freed on a cancelled occurrence is offered to nobody');
select is(
  (select count(*)::int from notifications
   where kind = 'event_waitlist_slot' and event_id = 'cccc7732-0000-0000-0000-000000000001'),
  0, 'and no claim notification is written for it');

-- ── E2: two free seats, one pass ──
do $$ begin
  perform private.fill_event_seats('cccc7732-0000-0000-0000-000000000002', (select i from t_occ));
end $$;

select is(
  (select array_agg(user_id::text order by user_id) from event_attendees
   where event_id = 'cccc7732-0000-0000-0000-000000000002' and offer_expires_at is not null),
  array['aaaa7732-0000-0000-0000-000000000003', 'aaaa7732-0000-0000-0000-000000000004'],
  'one fill pass offers both free seats to the two earliest waiters');
select is(
  (select count(*)::int from notifications
   where kind = 'event_waitlist_slot' and event_id = 'cccc7732-0000-0000-0000-000000000002'),
  2, 'each offer is announced once');
select is(
  (select offer_expires_at from event_attendees
   where event_id = 'cccc7732-0000-0000-0000-000000000002'
     and user_id = 'aaaa7732-0000-0000-0000-000000000005'),
  null, 'the third waiter is not offered a seat that is not free');

-- ── E3: the lapse walk ──
delete from event_attendees
where event_id = 'cccc7732-0000-0000-0000-000000000003'
  and user_id = 'aaaa7732-0000-0000-0000-000000000002';

select is(
  (select offer_expires_at from event_attendees
   where event_id = 'cccc7732-0000-0000-0000-000000000003'
     and user_id = 'aaaa7732-0000-0000-0000-000000000003'),
  now() + interval '12 hours', 'W1 is offered the freed seat');

-- W1 started paying, then let both the checkout hold and the offer run out.
insert into event_orders (id, event_id, instance_start, buyer_user_id, host_user_id,
                          amount_cents, platform_fee_cents, status, reserved_until)
select 'dddd7732-0000-0000-0000-000000000004', 'cccc7732-0000-0000-0000-000000000003', i,
       'aaaa7732-0000-0000-0000-000000000003', 'aaaa7732-0000-0000-0000-000000000001',
       2200, 110, 'pending', now() - interval '1 minute'
from t_occ;
update event_attendees set offer_expires_at = now() - interval '1 minute'
where event_id = 'cccc7732-0000-0000-0000-000000000003'
  and user_id = 'aaaa7732-0000-0000-0000-000000000003';

do $$ begin perform private.expire_event_waitlist_offers(); end $$;

select is(
  (select count(*)::int from event_attendees
   where event_id = 'cccc7732-0000-0000-0000-000000000003'
     and user_id = 'aaaa7732-0000-0000-0000-000000000003'),
  0, 'an offer whose pending checkout also expired is lapsed out of the queue');
select is(
  (select offer_expires_at from event_attendees
   where event_id = 'cccc7732-0000-0000-0000-000000000003'
     and user_id = 'aaaa7732-0000-0000-0000-000000000004'),
  now() + interval '12 hours', 'the next waiter is offered the seat');
select is(private.expire_event_waitlist_offers(), 0,
  'a second mover run has nothing left to lapse');
select is(
  (select count(*)::int from notifications
   where kind = 'event_waitlist_slot' and event_id = 'cccc7732-0000-0000-0000-000000000003'
     and user_id = 'aaaa7732-0000-0000-0000-000000000003'),
  1, 'the lapsed holder was offered the seat once, never in a loop');

-- The notification's occurrence resolves to the deadline on the attendee row.
select is(
  (select a.offer_expires_at
   from notifications n
   join event_attendees a
     on a.event_id = n.event_id and a.instance_start = n.event_instance_start and a.user_id = n.user_id
   where n.kind = 'event_waitlist_slot'
     and n.user_id = 'aaaa7732-0000-0000-0000-000000000004'
     and n.event_id = 'cccc7732-0000-0000-0000-000000000003'),
  now() + interval '12 hours', 'the offer notification names the occurrence whose row holds the deadline');

-- W1's money lands anyway (Stripe's session outlives the 15-minute hold):
-- the webhook's CAS, then its seat upsert.
update event_orders set status = 'paid', paid_at = now()
where id = 'dddd7732-0000-0000-0000-000000000004' and status = 'pending';
insert into event_attendees (event_id, user_id, status, instance_start, order_id)
select 'cccc7732-0000-0000-0000-000000000003', 'aaaa7732-0000-0000-0000-000000000003', 'going', i,
       'dddd7732-0000-0000-0000-000000000004'
from t_occ
on conflict (event_id, user_id, instance_start)
  do update set status = excluded.status, order_id = excluded.order_id;

select is(
  (select status from event_attendees
   where event_id = 'cccc7732-0000-0000-0000-000000000003'
     and user_id = 'aaaa7732-0000-0000-0000-000000000003'),
  'waitlisted', 'paying after the lapse is demoted: the seat is held for the next waiter');
select is(
  (select order_id from event_attendees
   where event_id = 'cccc7732-0000-0000-0000-000000000003'
     and user_id = 'aaaa7732-0000-0000-0000-000000000003'),
  'dddd7732-0000-0000-0000-000000000004'::uuid, 'the demoted row keeps the paid order');
select is(
  (select status from event_orders where id = 'dddd7732-0000-0000-0000-000000000004'),
  'paid', 'the money is held for a place, not refunded automatically');

update event_attendees set status = 'declined'
where event_id = 'cccc7732-0000-0000-0000-000000000003'
  and user_id = 'aaaa7732-0000-0000-0000-000000000004';

select is(
  (select status from event_attendees
   where event_id = 'cccc7732-0000-0000-0000-000000000003'
     and user_id = 'aaaa7732-0000-0000-0000-000000000003'),
  'going', 'when the offered waiter declines, the one who already paid is seated');

-- ── the boundary ──
select is(
  has_function_privilege('anon', 'private.expire_event_waitlist_offers()', 'execute'),
  false, 'anon holds no EXECUTE on the mover');
select is(
  has_function_privilege('authenticated', 'private.fill_event_seats(uuid, timestamptz)', 'execute'),
  false, 'a signed-in client holds no EXECUTE on the fill');

set local role anon;
select throws_ok(
  $$ select private.expire_event_waitlist_offers() $$,
  '42501', null,
  'anon calling the mover is refused');
reset role;

select * from finish();
rollback;
