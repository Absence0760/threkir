-- Pins migration 20270723000002 (decisions § 1817): the operator's platform-fee
-- earnings read.
--
--   * the boundary: a signed-in non-admin, a HOST whose own orders those are,
--     and anon are all refused (42501) by both readers, and the line function
--     they share is not callable by any client role;
--   * the money: which statuses carry a fee, how each refund state moves it,
--     the proportional give-back on a partial refund on both ledgers, and that
--     currencies are never summed together;
--   * the month: the UTC calendar month of the sale, pinned on a charge whose
--     local date is a different month from its UTC one.

begin;
select plan(16);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('9f1e0000-0000-0000-0000-0000000000a1', 'authenticated', 'authenticated',
   'pfe-admin@fee.local', '', now(), now()),
  ('9f1e0000-0000-0000-0000-0000000000b1', 'authenticated', 'authenticated',
   'pfe-host-one@fee.local', '', now(), now()),
  ('9f1e0000-0000-0000-0000-0000000000b2', 'authenticated', 'authenticated',
   'pfe-host-two@fee.local', '', now(), now()),
  ('9f1e0000-0000-0000-0000-0000000000c1', 'authenticated', 'authenticated',
   'pfe-buyer@fee.local', '', now(), now()),
  ('9f1e0000-0000-0000-0000-0000000000d1', 'authenticated', 'authenticated',
   'pfe-nobody@fee.local', '', now(), now());

insert into app_admins (user_id) values ('9f1e0000-0000-0000-0000-0000000000a1');

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';

insert into user_profiles (id, display_name)
values ('9f1e0000-0000-0000-0000-0000000000b1', 'Fee Host One'),
       ('9f1e0000-0000-0000-0000-0000000000b2', 'Fee Host Two');

insert into instructor_payout_accounts (user_id, stripe_connect_account_id, charges_enabled)
values ('9f1e0000-0000-0000-0000-0000000000b1', 'acct_test_pfe_one', true),
       ('9f1e0000-0000-0000-0000-0000000000b2', 'acct_test_pfe_two', true);

insert into clubs (id, owner_id, name, slug, is_public)
values ('9f1e0000-0000-0000-0000-0000000001c1', '9f1e0000-0000-0000-0000-0000000000b1',
        'Fee Studio One', 'pfe-studio-one', true),
       ('9f1e0000-0000-0000-0000-0000000001c2', '9f1e0000-0000-0000-0000-0000000000b2',
        'Fee Studio Two', 'pfe-studio-two', true);

insert into events (id, club_id, title, starts_at, author_id, host_user_id, category)
values ('9f1e0000-0000-0000-0000-0000000001e1', '9f1e0000-0000-0000-0000-0000000001c1',
        'Reformer', '2026-09-01 18:00+00', '9f1e0000-0000-0000-0000-0000000000b1',
        '9f1e0000-0000-0000-0000-0000000000b1', 'class'),
       ('9f1e0000-0000-0000-0000-0000000001e2', '9f1e0000-0000-0000-0000-0000000001c2',
        'Bootcamp', '2026-09-01 18:00+00', '9f1e0000-0000-0000-0000-0000000000b2',
        '9f1e0000-0000-0000-0000-0000000000b2', 'class');

insert into event_pricing (event_id, price_cents)
values ('9f1e0000-0000-0000-0000-0000000001e1', 2000),
       ('9f1e0000-0000-0000-0000-0000000001e2', 3000);

-- Host one, September 2026 (UTC), USD unless stated:
--   o1 paid               fee 100, nothing given back
--   o2 refunded           fee 100, all of it given back
--   o3 partially_refunded fee 100, 500 of 2000 refunded (a 300 refund that
--                         FAILED is not a give-back) -> round(100*500/2000) = 25
--   o4 refund_failed      fee 100, owed back, not counted as earned
--   o5 pending            never charged, not a line at all
--   o8 paid, EUR          fee 50, its own currency row
-- Host two:
--   o6 paid 2026-08-31 23:30 UTC          -> August
--   o7 paid 2026-09-30 23:30 -05:00        -> 2026-10-01 04:30 UTC -> October
insert into event_orders (id, event_id, instance_start, buyer_user_id, host_user_id,
                          amount_cents, currency, platform_fee_cents, status, paid_at)
values
  ('9f1e0000-0000-0000-0000-0000000002a1', '9f1e0000-0000-0000-0000-0000000001e1',
   '2026-09-01 18:00+00', '9f1e0000-0000-0000-0000-0000000000c1',
   '9f1e0000-0000-0000-0000-0000000000b1', 2000, 'usd', 100, 'paid', '2026-09-10 12:00+00'),
  ('9f1e0000-0000-0000-0000-0000000002a2', '9f1e0000-0000-0000-0000-0000000001e1',
   '2026-09-01 18:00+00', '9f1e0000-0000-0000-0000-0000000000c1',
   '9f1e0000-0000-0000-0000-0000000000b1', 2000, 'usd', 100, 'refunded', '2026-09-11 12:00+00'),
  ('9f1e0000-0000-0000-0000-0000000002a3', '9f1e0000-0000-0000-0000-0000000001e1',
   '2026-09-01 18:00+00', '9f1e0000-0000-0000-0000-0000000000c1',
   '9f1e0000-0000-0000-0000-0000000000b1', 2000, 'usd', 100, 'partially_refunded', '2026-09-12 12:00+00'),
  ('9f1e0000-0000-0000-0000-0000000002a4', '9f1e0000-0000-0000-0000-0000000001e1',
   '2026-09-01 18:00+00', '9f1e0000-0000-0000-0000-0000000000c1',
   '9f1e0000-0000-0000-0000-0000000000b1', 2000, 'usd', 100, 'refund_failed', '2026-09-13 12:00+00'),
  ('9f1e0000-0000-0000-0000-0000000002a5', '9f1e0000-0000-0000-0000-0000000001e1',
   '2026-09-01 18:00+00', '9f1e0000-0000-0000-0000-0000000000c1',
   '9f1e0000-0000-0000-0000-0000000000b1', 2000, 'usd', 100, 'pending', null),
  ('9f1e0000-0000-0000-0000-0000000002a8', '9f1e0000-0000-0000-0000-0000000001e1',
   '2026-09-01 18:00+00', '9f1e0000-0000-0000-0000-0000000000c1',
   '9f1e0000-0000-0000-0000-0000000000b1', 1000, 'eur', 50, 'paid', '2026-09-14 12:00+00'),
  ('9f1e0000-0000-0000-0000-0000000002a6', '9f1e0000-0000-0000-0000-0000000001e2',
   '2026-09-01 18:00+00', '9f1e0000-0000-0000-0000-0000000000c1',
   '9f1e0000-0000-0000-0000-0000000000b2', 3000, 'usd', 150, 'paid', '2026-08-31 23:30+00'),
  ('9f1e0000-0000-0000-0000-0000000002a7', '9f1e0000-0000-0000-0000-0000000001e2',
   '2026-09-01 18:00+00', '9f1e0000-0000-0000-0000-0000000000c1',
   '9f1e0000-0000-0000-0000-0000000000b2', 1000, 'usd', 50, 'paid', '2026-09-30 23:30-05');

insert into payment_refunds (stripe_refund_id, event_order_id, amount_cents, status)
values ('re_pfe_ok', '9f1e0000-0000-0000-0000-0000000002a3', 500, 'succeeded'),
       ('re_pfe_bounced', '9f1e0000-0000-0000-0000-0000000002a3', 300, 'failed');

-- Host two's fundraiser, anchored on their club's event: 10000 donated, fee
-- 200, 2500 recorded refunded of which a 500 refund FAILED, so 2000 net went
-- back -> round(200*2000/10000) = 40 given back.
insert into fundraisers (id, owner_user_id, event_id, charity_name, title, goal_cents)
values ('9f1e0000-0000-0000-0000-0000000003f1', '9f1e0000-0000-0000-0000-0000000000b2',
        '9f1e0000-0000-0000-0000-0000000001e2', 'Charity', 'Bootcamp for good', 100000);

insert into donations (id, fundraiser_id, owner_user_id, amount_cents, platform_fee_cents,
                       status, refunded_cents, paid_at)
values ('9f1e0000-0000-0000-0000-0000000003d1', '9f1e0000-0000-0000-0000-0000000003f1',
        '9f1e0000-0000-0000-0000-0000000000b2', 10000, 200, 'partially_refunded', 2500,
        '2026-09-20 12:00+00');

insert into payment_refunds (stripe_refund_id, donation_id, amount_cents, status)
values ('re_pfe_don_bounced', '9f1e0000-0000-0000-0000-0000000003d1', 500, 'failed');

reset role;

-- ── 1. the line function is not a client surface ────────────────────────────
select ok(
  not has_function_privilege('authenticated', 'private.platform_fee_lines()', 'EXECUTE')
    and not has_function_privilege('anon', 'private.platform_fee_lines()', 'EXECUTE'),
  'no client role can call private.platform_fee_lines'
);

-- ── 2. everyone but an admin is refused ─────────────────────────────────────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"9f1e0000-0000-0000-0000-0000000000d1","role":"authenticated"}';

select throws_ok(
  $$select * from admin_platform_fee_months()$$,
  '42501', null, 'a signed-in non-admin is refused the monthly fee view');
select throws_ok(
  $$select * from admin_platform_fees_by_host('2026-09-01')$$,
  '42501', null, 'a signed-in non-admin is refused the per-host fee view');

-- The host can read these very orders through their own RLS policy; that does
-- not make them the operator.
set local "request.jwt.claims" = '{"sub":"9f1e0000-0000-0000-0000-0000000000b1","role":"authenticated"}';

select isnt_empty(
  $$select 1 from event_orders where host_user_id = '9f1e0000-0000-0000-0000-0000000000b1'$$,
  'the host reads their own orders (the rows the fee view would sum exist)'
);
select throws_ok(
  $$select * from admin_platform_fee_months()$$,
  '42501', null, 'a host is refused the monthly fee view over their own sales');
select throws_ok(
  $$select * from admin_platform_fees_by_host(null)$$,
  '42501', null, 'a host is refused the per-host fee view over their own sales');

set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';

select throws_ok(
  $$select * from admin_platform_fee_months()$$,
  '42501', null, 'anon is refused the monthly fee view');

-- ── 3. the admin sees the months ────────────────────────────────────────────
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"9f1e0000-0000-0000-0000-0000000000a1","role":"authenticated"}';

select is(
  (select array[charge_count, gross_fee_cents, reversed_fee_cents, net_fee_cents,
                refunded_count, partially_refunded_count, refund_failed_count]::bigint[]
     from admin_platform_fee_months() where month = '2026-09-01' and currency = 'usd' and source = 'event'),
  array[4, 400, 225, 175, 1, 1, 1]::bigint[],
  'September USD events: four charges (pending excluded), 100 + 25 + 100 given back'
);
select is(
  (select net_fee_cents from admin_platform_fee_months()
    where month = '2026-09-01' and currency = 'eur' and source = 'event'),
  50::bigint,
  'a EUR fee is its own row, never added to USD'
);
select is(
  (select array[charge_count, gross_fee_cents, reversed_fee_cents, net_fee_cents,
                partially_refunded_count]::bigint[]
     from admin_platform_fee_months() where month = '2026-09-01' and currency = 'usd' and source = 'donation'),
  array[1, 200, 40, 160, 1]::bigint[],
  'a partly refunded donation gives back its net-refunded share of the fee (failed refund excluded)'
);
select is(
  (select net_fee_cents from admin_platform_fee_months()
    where month = '2026-08-01' and currency = 'usd' and source = 'event'),
  150::bigint,
  'a charge at 23:30 UTC on 31 August is August'
);
select is(
  (select net_fee_cents from admin_platform_fee_months()
    where month = '2026-10-01' and currency = 'usd' and source = 'event'),
  50::bigint,
  'a charge at 23:30 on 30 September in UTC-5 is October: months are UTC'
);
select is(
  (select count(*)::int from admin_platform_fee_months()
    where month in ('2026-08-01', '2026-09-01', '2026-10-01')),
  5,
  'exactly the five month/currency/source rows the fixture implies'
);

-- ── 4. the admin sees one month split by host + club ────────────────────────
select is(
  (select array_agg(host_display_name || '/' || club_slug || '/' || currency || '=' || net_fee_cents
                    order by net_fee_cents desc)
     from admin_platform_fees_by_host('2026-09-17')
    where host_user_id in ('9f1e0000-0000-0000-0000-0000000000b1',
                           '9f1e0000-0000-0000-0000-0000000000b2')),
  array['Fee Host One/pfe-studio-one/usd=175',
        'Fee Host Two/pfe-studio-two/usd=160',
        'Fee Host One/pfe-studio-one/eur=50'],
  'any day in September selects September, one row per host + club + currency'
);
select is(
  (select sum(charge_count)::int from admin_platform_fees_by_host('2026-09-01')
    where host_user_id = '9f1e0000-0000-0000-0000-0000000000b1'),
  5,
  'host one: the four USD charges and the EUR one, the pending order excluded'
);
select is(
  (select sum(net_fee_cents)::int from admin_platform_fees_by_host(null)
    where host_user_id = '9f1e0000-0000-0000-0000-0000000000b2'),
  360,
  'null month is all time: host two earns 150 (Aug) + 160 (Sep donation) + 50 (Oct)'
);

select * from finish();
rollback;
