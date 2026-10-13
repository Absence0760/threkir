-- Pins migration 20270731000001 (decisions § R7PAID-1): an event that has
-- moved money cannot be deleted by a client.
--   * guard_paid_event_delete refuses an organiser's delete of an event with a
--     paid, a pending or an already refunded order, and of one whose
--     fundraiser holds a paid donation;
--   * an event whose orders never charged (failed / canceled), or that has
--     none, still deletes, and its never-charged orders cascade as before;
--   * a club delete that cascades into a paid event is refused too;
--   * the service role and privileged direct SQL (account erasure) pass, so
--     deleting an account still cascades its clubs' events;
--   * no client role can execute the trigger function.

begin;
select plan(13);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('aaaa7731-0000-0000-0000-000000000001', 'authenticated', 'authenticated', 'pdg-owner@evt.local', '', now(), now()),
  ('aaaa7731-0000-0000-0000-000000000002', 'authenticated', 'authenticated', 'pdg-buyer@evt.local', '', now(), now()),
  ('aaaa7731-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'pdg-erased@evt.local', '', now(), now());

insert into instructor_payout_accounts (user_id, stripe_connect_account_id, charges_enabled)
values ('aaaa7731-0000-0000-0000-000000000001', 'acct_test_pdg_owner', true);

insert into clubs (id, owner_id, name, slug, is_public) values
  ('bbbb7731-0000-0000-0000-000000000001', 'aaaa7731-0000-0000-0000-000000000001', 'Paid Delete Studio', 'pdg-studio', true),
  ('bbbb7731-0000-0000-0000-000000000002', 'aaaa7731-0000-0000-0000-000000000001', 'Paid Delete Annex', 'pdg-annex', true),
  ('bbbb7731-0000-0000-0000-000000000003', 'aaaa7731-0000-0000-0000-000000000003', 'Erased Owner Club', 'pdg-erased', true);

-- E1 paid, E2 refunded, E3 pending, E4 failed + canceled, E5 no orders,
-- E6 a paid fundraiser donation, E7 paid (deleted by the service role),
-- E8 paid in the annex club, E9 paid in the erased owner's club.
insert into events (id, club_id, title, starts_at, author_id, host_user_id, category)
select ('cccc7731-0000-0000-0000-00000000000' || n)::uuid,
       case n when 8 then 'bbbb7731-0000-0000-0000-000000000002'::uuid
              when 9 then 'bbbb7731-0000-0000-0000-000000000003'::uuid
              else 'bbbb7731-0000-0000-0000-000000000001'::uuid end,
       'Class ' || n, '2026-09-01 18:00+00',
       case n when 9 then 'aaaa7731-0000-0000-0000-000000000003'::uuid
              else 'aaaa7731-0000-0000-0000-000000000001'::uuid end,
       case n when 9 then 'aaaa7731-0000-0000-0000-000000000003'::uuid
              else 'aaaa7731-0000-0000-0000-000000000001'::uuid end,
       'class'
from generate_series(1, 9) as n;

insert into event_orders (event_id, instance_start, buyer_user_id, host_user_id,
                          amount_cents, platform_fee_cents, status, paid_at)
select ('cccc7731-0000-0000-0000-00000000000' || o.n)::uuid, '2026-09-01 18:00+00',
       'aaaa7731-0000-0000-0000-000000000002',
       case o.n when 9 then 'aaaa7731-0000-0000-0000-000000000003'::uuid
                else 'aaaa7731-0000-0000-0000-000000000001'::uuid end,
       2200, 55, o.status, case when o.status in ('paid', 'refunded') then now() end
from (values (1, 'paid'), (2, 'refunded'), (3, 'pending'), (4, 'failed'), (4, 'canceled'),
             (7, 'paid'), (8, 'paid'), (9, 'paid')) as o(n, status);

insert into fundraisers (id, owner_user_id, event_id, charity_name, title, goal_cents)
values ('eeee7731-0000-0000-0000-000000000001', 'aaaa7731-0000-0000-0000-000000000001',
        'cccc7731-0000-0000-0000-000000000006', 'Food Bank', 'Class for the food bank', 50000);
insert into donations (fundraiser_id, owner_user_id, amount_cents, status, paid_at)
values ('eeee7731-0000-0000-0000-000000000001', 'aaaa7731-0000-0000-0000-000000000001',
        2500, 'paid', now());

-- ── As the club owner (an event organiser) ──
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"aaaa7731-0000-0000-0000-000000000001","role":"authenticated"}';

select throws_ok(
  $$ delete from events where id = 'cccc7731-0000-0000-0000-000000000001' $$,
  'P0001', 'paid_event_has_orders',
  'an organiser cannot delete an event holding a paid order');

select throws_ok(
  $$ delete from events where id = 'cccc7731-0000-0000-0000-000000000002' $$,
  'P0001', 'paid_event_has_orders',
  'an organiser cannot delete an event whose orders were refunded: the ledger stays');

select throws_ok(
  $$ delete from events where id = 'cccc7731-0000-0000-0000-000000000003' $$,
  'P0001', 'paid_event_has_orders',
  'an organiser cannot delete an event with a checkout in flight');

select lives_ok(
  $$ delete from events where id = 'cccc7731-0000-0000-0000-000000000004' $$,
  'an event whose orders never charged still deletes');

select lives_ok(
  $$ delete from events where id = 'cccc7731-0000-0000-0000-000000000005' $$,
  'a free event with no orders still deletes');

select throws_ok(
  $$ delete from events where id = 'cccc7731-0000-0000-0000-000000000006' $$,
  'P0001', 'paid_event_has_orders',
  'an organiser cannot delete an event whose fundraiser took a donation');

select throws_ok(
  $$ delete from clubs where id = 'bbbb7731-0000-0000-0000-000000000002' $$,
  'P0001', 'paid_event_has_orders',
  'a club delete that cascades into a paid event is refused');

-- ── As the service role ──
set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';

select lives_ok(
  $$ delete from events where id = 'cccc7731-0000-0000-0000-000000000007' $$,
  'the service role passes the guard');

-- ── Direct SQL with no role claim: the account-erasure cascade ──
reset role;
set local "request.jwt.claims" = '';

select lives_ok(
  $$ delete from auth.users where id = 'aaaa7731-0000-0000-0000-000000000003' $$,
  'erasing an account still cascades through its club''s paid event');

select is(
  (select count(*)::int from events where id = 'cccc7731-0000-0000-0000-000000000009'),
  0,
  'the erased owner''s paid event is gone');

select is(
  (select count(*)::int from events
    where id in ('cccc7731-0000-0000-0000-000000000001', 'cccc7731-0000-0000-0000-000000000002',
                 'cccc7731-0000-0000-0000-000000000003', 'cccc7731-0000-0000-0000-000000000006',
                 'cccc7731-0000-0000-0000-000000000008')),
  5,
  'every refused event is still there');

select is(
  (select count(*)::int from event_orders where event_id = 'cccc7731-0000-0000-0000-000000000004'),
  0,
  'the never-charged orders of a deleted event cascade as before');

select is(
  has_function_privilege('authenticated', 'public.guard_paid_event_delete()', 'execute'),
  false,
  'a client role cannot execute the guard directly');

select * from finish();
rollback;
