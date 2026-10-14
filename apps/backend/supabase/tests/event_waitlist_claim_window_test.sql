-- Pins migration 20270726000002 (waitlist notify-to-pay on a paid occurrence,
-- decisions § 1840):
--   * an unpaid `waitlisted` row is legal on a priced occurrence; an unpaid
--     `going` row still is not;
--   * a freed seat on a priced occurrence OFFERS the earliest waitlister a
--     12-hour claim (an event_waitlist_slot notification), seats nobody, and
--     holds the seat against every other path;
--   * the claim (the webhook's upsert to going with a paid order) lands on the
--     held seat and clears the offer without offering anyone else;
--   * the mover lapses an unclaimed offer and offers the seat to the next
--     person, is idempotent, and skips a holder who is mid-checkout;
--   * declining ends the offer; a waitlister who already paid goes first and
--     is seated outright; the deadline clamps to sales close and no offer is
--     made once sales have closed;
--   * a free occurrence keeps direct promotion;
--   * the column is not client-writable, the mover is not client-executable,
--     and it is scheduled.

begin;
select plan(28);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('aaaa7726-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'wl-host@evt.local', '', now(), now()),
  ('aaaa7726-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'wl-a@evt.local', '', now(), now()),
  ('aaaa7726-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'wl-w1@evt.local', '', now(), now()),
  ('aaaa7726-0000-0000-0000-000000000004', 'authenticated', 'authenticated', 'wl-w2@evt.local', '', now(), now()),
  ('aaaa7726-0000-0000-0000-000000000005', 'authenticated', 'authenticated', 'wl-w3@evt.local', '', now(), now()),
  ('aaaa7726-0000-0000-0000-000000000006', 'authenticated', 'authenticated', 'wl-s@evt.local', '', now(), now()),
  ('aaaa7726-0000-0000-0000-000000000007', 'authenticated', 'authenticated', 'wl-x@evt.local', '', now(), now()),
  ('aaaa7726-0000-0000-0000-000000000008', 'authenticated', 'authenticated', 'wl-y@evt.local', '', now(), now());

insert into clubs (id, owner_id, name, slug, is_public)
values ('bbbb7726-0000-0000-0000-000000000001',
        'aaaa7726-0000-0000-0000-000000000001', 'Waitlist Studio', 'wl-studio', true);

insert into events (id, club_id, title, starts_at, author_id, host_user_id, category, capacity)
values
  ('cccc7726-0000-0000-0000-000000000001', 'bbbb7726-0000-0000-0000-000000000001', 'Reformer',
   now() + interval '7 days', 'aaaa7726-0000-0000-0000-000000000001',
   'aaaa7726-0000-0000-0000-000000000001', 'class', 1),
  ('cccc7726-0000-0000-0000-000000000002', 'bbbb7726-0000-0000-0000-000000000001', 'Free run',
   now() + interval '7 days', 'aaaa7726-0000-0000-0000-000000000001',
   'aaaa7726-0000-0000-0000-000000000001', 'run', 1);

insert into instructor_payout_accounts (user_id, stripe_connect_account_id, charges_enabled)
values ('aaaa7726-0000-0000-0000-000000000001', 'acct_test_wl_host', true);
insert into event_pricing (event_id, price_cents)
values ('cccc7726-0000-0000-0000-000000000001', 2200);

-- One occurrence instant for the main walk, held in a temp table so every
-- statement names the same value (now() is the transaction's, so it is fixed).
create temp table t_occ as select now() + interval '7 days' as i;

-- A: seated, paid.
insert into event_orders (id, event_id, instance_start, buyer_user_id, host_user_id,
                          amount_cents, platform_fee_cents, status, paid_at)
select 'dddd7726-0000-0000-0000-000000000001', 'cccc7726-0000-0000-0000-000000000001', i,
       'aaaa7726-0000-0000-0000-000000000002', 'aaaa7726-0000-0000-0000-000000000001', 2200, 110, 'paid', now()
from t_occ;
insert into event_attendees (event_id, user_id, status, instance_start, order_id)
select 'cccc7726-0000-0000-0000-000000000001', 'aaaa7726-0000-0000-0000-000000000002', 'going', i,
       'dddd7726-0000-0000-0000-000000000001'
from t_occ;

-- ── 1. joining ──
insert into event_attendees (event_id, user_id, status, instance_start, joined_at)
select 'cccc7726-0000-0000-0000-000000000001', u, 'waitlisted', i, j
from t_occ, (values ('aaaa7726-0000-0000-0000-000000000003'::uuid, now() - interval '3 hours'),
                    ('aaaa7726-0000-0000-0000-000000000004'::uuid, now() - interval '2 hours'),
                    ('aaaa7726-0000-0000-0000-000000000005'::uuid, now() - interval '1 hour')) v(u, j);

select is(
  (select count(*)::int from event_attendees
   where event_id = 'cccc7726-0000-0000-0000-000000000001'
     and status = 'waitlisted' and order_id is null),
  3, 'an unpaid waitlist entry is accepted on a priced occurrence');

insert into event_attendees (event_id, user_id, status, instance_start)
select 'cccc7726-0000-0000-0000-000000000001', 'aaaa7726-0000-0000-0000-000000000006', 'maybe', i from t_occ;

select throws_ok(
  $$ update event_attendees set status = 'going'
     where user_id = 'aaaa7726-0000-0000-0000-000000000006' $$,
  '23514', null,
  'an unpaid going row on a priced occurrence is still refused');

-- ── 2. a freed seat is offered, not given ──
delete from event_attendees
where event_id = 'cccc7726-0000-0000-0000-000000000001'
  and user_id = 'aaaa7726-0000-0000-0000-000000000002';

select is(
  (select status from event_attendees where user_id = 'aaaa7726-0000-0000-0000-000000000003'),
  'waitlisted', 'the earliest waitlister is not seated without paying');
select is(
  (select offer_expires_at from event_attendees where user_id = 'aaaa7726-0000-0000-0000-000000000003'),
  now() + interval '12 hours', 'they are offered the seat with a 12-hour claim window');
select is(
  (select count(*)::int from notifications
   where kind = 'event_waitlist_slot' and user_id = 'aaaa7726-0000-0000-0000-000000000003'
     and event_id = 'cccc7726-0000-0000-0000-000000000001'
     and event_instance_start = (select i from t_occ)),
  1, 'the offer is announced once, naming the occurrence');
select is(
  (select offer_expires_at from event_attendees where user_id = 'aaaa7726-0000-0000-0000-000000000004'),
  null, 'one freed seat makes one offer');

-- The held seat is not anyone else's: a paid stranger's seat is demoted.
insert into event_orders (id, event_id, instance_start, buyer_user_id, host_user_id,
                          amount_cents, platform_fee_cents, status, paid_at)
select 'dddd7726-0000-0000-0000-000000000002', 'cccc7726-0000-0000-0000-000000000001', i,
       'aaaa7726-0000-0000-0000-000000000006', 'aaaa7726-0000-0000-0000-000000000001', 2200, 110, 'paid', now()
from t_occ;
update event_attendees set status = 'going', order_id = 'dddd7726-0000-0000-0000-000000000002'
where user_id = 'aaaa7726-0000-0000-0000-000000000006';
select is(
  (select status from event_attendees where user_id = 'aaaa7726-0000-0000-0000-000000000006'),
  'waitlisted', 'a live offer holds its seat against another paid seating');
delete from event_attendees where user_id = 'aaaa7726-0000-0000-0000-000000000006';

-- ── 3. the claim ──
insert into event_orders (id, event_id, instance_start, buyer_user_id, host_user_id,
                          amount_cents, platform_fee_cents, status, paid_at)
select 'dddd7726-0000-0000-0000-000000000003', 'cccc7726-0000-0000-0000-000000000001', i,
       'aaaa7726-0000-0000-0000-000000000003', 'aaaa7726-0000-0000-0000-000000000001', 2200, 110, 'paid', now()
from t_occ;
insert into event_attendees (event_id, user_id, status, instance_start, order_id)
select 'cccc7726-0000-0000-0000-000000000001', 'aaaa7726-0000-0000-0000-000000000003', 'going', i,
       'dddd7726-0000-0000-0000-000000000003'
from t_occ
on conflict (event_id, user_id, instance_start)
  do update set status = excluded.status, order_id = excluded.order_id;

select is(
  (select status from event_attendees where user_id = 'aaaa7726-0000-0000-0000-000000000003'),
  'going', 'paying for the offer seats the holder on the held seat');
select is(
  (select offer_expires_at from event_attendees where user_id = 'aaaa7726-0000-0000-0000-000000000003'),
  null, 'the claim clears the offer');
select is(
  (select count(*)::int from notifications
   where kind = 'event_waitlist_slot' and user_id = 'aaaa7726-0000-0000-0000-000000000004'),
  0, 'a claimed offer frees nothing, so the next waitlister is not offered');

-- ── 4. expiry hands the seat on ──
delete from event_attendees where user_id = 'aaaa7726-0000-0000-0000-000000000003';
select isnt(
  (select offer_expires_at from event_attendees where user_id = 'aaaa7726-0000-0000-0000-000000000004'),
  null, 'the next freed seat is offered to the next waitlister');

update event_attendees set offer_expires_at = now() - interval '1 minute'
where user_id = 'aaaa7726-0000-0000-0000-000000000004';

select is(private.expire_event_waitlist_offers(), 1, 'the mover lapses the unclaimed offer');
select is(
  (select count(*)::int from event_attendees where user_id = 'aaaa7726-0000-0000-0000-000000000004'),
  0, 'a lapsed offer leaves the queue');
select is(
  (select offer_expires_at from event_attendees where user_id = 'aaaa7726-0000-0000-0000-000000000005'),
  now() + interval '12 hours', 'the lapsed seat is offered to the next waitlister');
select is(private.expire_event_waitlist_offers(), 0, 'a second run finds nothing to lapse');
select is(
  (select count(*)::int from notifications
   where kind = 'event_waitlist_slot' and user_id = 'aaaa7726-0000-0000-0000-000000000005'),
  1, 'and announces nothing twice');

-- A holder mid-checkout keeps the seat past the deadline.
update event_attendees set offer_expires_at = now() - interval '1 minute'
where user_id = 'aaaa7726-0000-0000-0000-000000000005';
insert into event_orders (id, event_id, instance_start, buyer_user_id, host_user_id,
                          amount_cents, platform_fee_cents, status, reserved_until)
select 'dddd7726-0000-0000-0000-000000000004', 'cccc7726-0000-0000-0000-000000000001', i,
       'aaaa7726-0000-0000-0000-000000000005', 'aaaa7726-0000-0000-0000-000000000001', 2200, 110, 'pending',
       now() + interval '10 minutes'
from t_occ;
select is(private.expire_event_waitlist_offers(), 0,
  'an offer whose holder has a live checkout reservation is not lapsed');

-- ── 5. declining ends the offer ──
update event_attendees set status = 'declined'
where user_id = 'aaaa7726-0000-0000-0000-000000000005';
select is(
  (select offer_expires_at from event_attendees where user_id = 'aaaa7726-0000-0000-0000-000000000005'),
  null, 'declining clears the offer');

-- ── 6. a waitlister who already paid goes first ──
-- The seat is free now. Z (the host, as a stand-in buyer) takes it, X joins
-- the waitlist early and unpaid, Y joins later having paid (the oversold arm).
insert into event_orders (id, event_id, instance_start, buyer_user_id, host_user_id,
                          amount_cents, platform_fee_cents, status, paid_at)
select o, 'cccc7726-0000-0000-0000-000000000001', i, u,
       'aaaa7726-0000-0000-0000-000000000001', 2200, 110, 'paid', now()
from t_occ, (values ('dddd7726-0000-0000-0000-000000000005'::uuid, 'aaaa7726-0000-0000-0000-000000000001'::uuid),
                    ('dddd7726-0000-0000-0000-000000000006'::uuid, 'aaaa7726-0000-0000-0000-000000000008'::uuid)) v(o, u);
insert into event_attendees (event_id, user_id, status, instance_start, order_id, joined_at)
select 'cccc7726-0000-0000-0000-000000000001', u, s, i, o, j
from t_occ, (values
  ('aaaa7726-0000-0000-0000-000000000001'::uuid, 'going', 'dddd7726-0000-0000-0000-000000000005'::uuid, now()),
  ('aaaa7726-0000-0000-0000-000000000007'::uuid, 'waitlisted', null::uuid, now() - interval '9 hours'),
  ('aaaa7726-0000-0000-0000-000000000008'::uuid, 'waitlisted', 'dddd7726-0000-0000-0000-000000000006'::uuid, now())
) v(u, s, o, j);
delete from event_attendees where user_id = 'aaaa7726-0000-0000-0000-000000000001';

select is(
  (select status from event_attendees where user_id = 'aaaa7726-0000-0000-0000-000000000008'),
  'going', 'a waitlister holding a paid order is seated outright, ahead of an earlier unpaid one');
select is(
  (select offer_expires_at from event_attendees where user_id = 'aaaa7726-0000-0000-0000-000000000007'),
  null, 'and the unpaid waitlister is not offered a seat that is no longer free');

-- ── 7. the deadline respects sales close ──
-- An occurrence two hours out (series pricing, sales close at the start):
-- the offer runs to the start, not twelve hours.
insert into event_orders (id, event_id, instance_start, buyer_user_id, host_user_id,
                          amount_cents, platform_fee_cents, status, paid_at)
values ('dddd7726-0000-0000-0000-000000000007', 'cccc7726-0000-0000-0000-000000000001', now() + interval '2 hours',
        'aaaa7726-0000-0000-0000-000000000002', 'aaaa7726-0000-0000-0000-000000000001', 2200, 110, 'paid', now()),
       ('dddd7726-0000-0000-0000-000000000008', 'cccc7726-0000-0000-0000-000000000001', now() - interval '1 hour',
        'aaaa7726-0000-0000-0000-000000000002', 'aaaa7726-0000-0000-0000-000000000001', 2200, 110, 'paid', now());
insert into event_attendees (event_id, user_id, status, instance_start, order_id, joined_at)
values
  ('cccc7726-0000-0000-0000-000000000001', 'aaaa7726-0000-0000-0000-000000000002', 'going',
   now() + interval '2 hours', 'dddd7726-0000-0000-0000-000000000007', now()),
  ('cccc7726-0000-0000-0000-000000000001', 'aaaa7726-0000-0000-0000-000000000004', 'waitlisted',
   now() + interval '2 hours', null, now()),
  ('cccc7726-0000-0000-0000-000000000001', 'aaaa7726-0000-0000-0000-000000000002', 'going',
   now() - interval '1 hour', 'dddd7726-0000-0000-0000-000000000008', now()),
  ('cccc7726-0000-0000-0000-000000000001', 'aaaa7726-0000-0000-0000-000000000004', 'waitlisted',
   now() - interval '1 hour', null, now());
delete from event_attendees
where user_id = 'aaaa7726-0000-0000-0000-000000000002'
  and instance_start in (now() + interval '2 hours', now() - interval '1 hour');

select is(
  (select offer_expires_at from event_attendees
   where user_id = 'aaaa7726-0000-0000-0000-000000000004' and instance_start = now() + interval '2 hours'),
  now() + interval '2 hours', 'the claim window is clamped to sales close');
select is(
  (select offer_expires_at from event_attendees
   where user_id = 'aaaa7726-0000-0000-0000-000000000004' and instance_start = now() - interval '1 hour'),
  null, 'no offer is made once sales have closed');

-- ── 8. a free occurrence keeps direct promotion ──
insert into event_attendees (event_id, user_id, status, instance_start, joined_at)
select 'cccc7726-0000-0000-0000-000000000002', u, s, i, j
from t_occ, (values ('aaaa7726-0000-0000-0000-000000000006'::uuid, 'going', now()),
                    ('aaaa7726-0000-0000-0000-000000000007'::uuid, 'going', now() + interval '1 second')) v(u, s, j);
delete from event_attendees
where event_id = 'cccc7726-0000-0000-0000-000000000002'
  and user_id = 'aaaa7726-0000-0000-0000-000000000006';
select is(
  (select status from event_attendees
   where event_id = 'cccc7726-0000-0000-0000-000000000002'
     and user_id = 'aaaa7726-0000-0000-0000-000000000007'),
  'going', 'a free occurrence still promotes the waitlister straight to going');
select is(
  (select count(*)::int from notifications
   where kind = 'event_waitlist_slot' and event_id = 'cccc7726-0000-0000-0000-000000000002'),
  0, 'and sends no claim notification');

-- ── 9. the boundaries ──
select is(
  has_column_privilege('authenticated', 'public.event_attendees', 'offer_expires_at', 'UPDATE'),
  false, 'a client cannot set or extend an offer');
select is(
  has_column_privilege('authenticated', 'public.event_attendees', 'offer_expires_at', 'INSERT'),
  false, 'a client cannot insert itself an offer');
select is(
  has_function_privilege('authenticated', 'private.expire_event_waitlist_offers()', 'execute'),
  false, 'a client cannot run the mover');
select is(
  (select count(*)::int from cron.job
   where jobname = 'expire-event-waitlist-offers'
     and command = 'select private.expire_event_waitlist_offers()'),
  1, 'the mover is scheduled');

select * from finish();
rollback;
