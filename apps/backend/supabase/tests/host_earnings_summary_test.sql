-- Pins migration 20270723000001 (instructor_business.md M7, decisions § 1816):
-- host_earnings_summary() is the PAYEE's read of their paid-event money.
--   * one row per (class instance, currency), never a cross-currency sum;
--   * paid + partially_refunded are registrations; refunded nets to zero fee;
--     refund_failed is reported only as unsettled; pending is ignored;
--   * a partial refund is the order's non-failed payment_refunds children, and
--     a partial refund with none is counted as unrecorded rather than hidden;
--   * the month is the event's own timezone, UTC for a NULL or unknown zone;
--   * scope is event_orders.host_user_id: an organiser of the club who was not
--     paid sees nothing of it, though the table's own policy lets them read
--     the orders; a stranger sees nothing; anon cannot call it.

begin;
select plan(13);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('a7a70000-0000-0000-0000-000000000001', 'authenticated', 'authenticated',
   'he-host@evt.local', '', now(), now()),
  ('a7a70000-0000-0000-0000-000000000002', 'authenticated', 'authenticated',
   'he-organiser@evt.local', '', now(), now()),
  ('a7a70000-0000-0000-0000-000000000003', 'authenticated', 'authenticated',
   'he-buyer@evt.local', '', now(), now()),
  ('a7a70000-0000-0000-0000-000000000004', 'authenticated', 'authenticated',
   'he-stranger@evt.local', '', now(), now());

set local role service_role;
set local "request.jwt.claims" = '{"role":"service_role"}';

-- The club belongs to the ORGANISER; the classes are hosted (and paid to) the
-- HOST, who is not a member of it at all.
insert into clubs (id, owner_id, name, slug, is_public)
values ('b7b70000-0000-0000-0000-000000000001',
        'a7a70000-0000-0000-0000-000000000002', 'Earnings Studio', 'he-studio', true);

insert into events (id, club_id, title, starts_at, author_id, host_user_id, category, timezone)
values
  ('c7c70000-0000-0000-0000-000000000001', 'b7b70000-0000-0000-0000-000000000001',
   'Evening Reformer', '2026-11-01 02:00+00', 'a7a70000-0000-0000-0000-000000000002',
   'a7a70000-0000-0000-0000-000000000001', 'class', 'America/Los_Angeles'),
  ('c7c70000-0000-0000-0000-000000000002', 'b7b70000-0000-0000-0000-000000000001',
   'Legacy Barre', '2026-12-01 00:30+00', 'a7a70000-0000-0000-0000-000000000002',
   'a7a70000-0000-0000-0000-000000000001', 'class', null),
  ('c7c70000-0000-0000-0000-000000000003', 'b7b70000-0000-0000-0000-000000000001',
   'Mystery Zone Flow', '2026-12-01 00:30+00', 'a7a70000-0000-0000-0000-000000000002',
   'a7a70000-0000-0000-0000-000000000001', 'class', 'Not/AZone'),
  ('c7c70000-0000-0000-0000-000000000004', 'b7b70000-0000-0000-0000-000000000001',
   'Organiser Own Class', '2026-11-05 18:00+00', 'a7a70000-0000-0000-0000-000000000002',
   'a7a70000-0000-0000-0000-000000000002', 'class', 'UTC');

insert into event_orders (id, event_id, instance_start, buyer_user_id, host_user_id,
                          amount_cents, currency, platform_fee_cents, status, paid_at)
values
  -- Evening Reformer, 19:00 on 31 Oct in Los Angeles = 02:00 UTC on 1 Nov.
  ('d7d70000-0000-0000-0000-000000000001', 'c7c70000-0000-0000-0000-000000000001',
   '2026-11-01 02:00+00', 'a7a70000-0000-0000-0000-000000000003',
   'a7a70000-0000-0000-0000-000000000001', 2000, 'usd', 100, 'paid', now()),
  ('d7d70000-0000-0000-0000-000000000002', 'c7c70000-0000-0000-0000-000000000001',
   '2026-11-01 02:00+00', 'a7a70000-0000-0000-0000-000000000003',
   'a7a70000-0000-0000-0000-000000000001', 2000, 'usd', 100, 'paid', now()),
  ('d7d70000-0000-0000-0000-000000000003', 'c7c70000-0000-0000-0000-000000000001',
   '2026-11-01 02:00+00', 'a7a70000-0000-0000-0000-000000000003',
   'a7a70000-0000-0000-0000-000000000001', 2000, 'usd', 100, 'refunded', now()),
  ('d7d70000-0000-0000-0000-000000000004', 'c7c70000-0000-0000-0000-000000000001',
   '2026-11-01 02:00+00', 'a7a70000-0000-0000-0000-000000000003',
   'a7a70000-0000-0000-0000-000000000001', 2000, 'usd', 100, 'partially_refunded', now()),
  ('d7d70000-0000-0000-0000-000000000005', 'c7c70000-0000-0000-0000-000000000001',
   '2026-11-01 02:00+00', 'a7a70000-0000-0000-0000-000000000003',
   'a7a70000-0000-0000-0000-000000000001', 2000, 'usd', 100, 'refund_failed', now()),
  ('d7d70000-0000-0000-0000-000000000006', 'c7c70000-0000-0000-0000-000000000001',
   '2026-11-01 02:00+00', 'a7a70000-0000-0000-0000-000000000003',
   'a7a70000-0000-0000-0000-000000000001', 2000, 'usd', 100, 'pending', null),
  ('d7d70000-0000-0000-0000-000000000007', 'c7c70000-0000-0000-0000-000000000001',
   '2026-11-01 02:00+00', 'a7a70000-0000-0000-0000-000000000003',
   'a7a70000-0000-0000-0000-000000000001', 3000, 'eur', 150, 'paid', now()),
  -- Legacy Barre: no zone, so 00:30 UTC on 1 Dec is December.
  ('d7d70000-0000-0000-0000-000000000008', 'c7c70000-0000-0000-0000-000000000002',
   '2026-12-01 00:30+00', 'a7a70000-0000-0000-0000-000000000003',
   'a7a70000-0000-0000-0000-000000000001', 1500, 'usd', 75, 'partially_refunded', now()),
  ('d7d70000-0000-0000-0000-000000000009', 'c7c70000-0000-0000-0000-000000000003',
   '2026-12-01 00:30+00', 'a7a70000-0000-0000-0000-000000000003',
   'a7a70000-0000-0000-0000-000000000001', 1000, 'usd', 50, 'paid', now()),
  -- Paid to the ORGANISER, on their own class.
  ('d7d70000-0000-0000-0000-00000000000a', 'c7c70000-0000-0000-0000-000000000004',
   '2026-11-05 18:00+00', 'a7a70000-0000-0000-0000-000000000003',
   'a7a70000-0000-0000-0000-000000000002', 2500, 'usd', 125, 'paid', now());

-- Order 4's partial refund: 500 came back, a further 300 bounced. Order 8 was
-- partially refunded with no refund the ledger heard about.
insert into payment_refunds (stripe_refund_id, event_order_id, amount_cents, status, failure_reason)
values
  ('re_he_ok', 'd7d70000-0000-0000-0000-000000000004', 500, 'succeeded', null),
  ('re_he_bounced', 'd7d70000-0000-0000-0000-000000000004', 300, 'failed', 'insufficient_funds');

-- ── as the HOST ──
set local role authenticated;
set local "request.jwt.claims" = '{"sub":"a7a70000-0000-0000-0000-000000000001","role":"authenticated"}';

select results_eq(
  $$ select local_month, timezone, registrations, refunded_orders,
            partially_refunded_orders, partial_refunds_unrecorded, refund_failed_orders,
            gross_cents, refunded_cents, platform_fee_cents, net_cents, unsettled_cents
       from host_earnings_summary()
      where event_id = 'c7c70000-0000-0000-0000-000000000001' and currency = 'usd' $$,
  $$ values ('2026-10-01'::date, 'America/Los_Angeles'::text, 3, 1, 1, 0, 1,
             8000::bigint, 2500::bigint, 300::bigint, 5200::bigint, 2000::bigint) $$,
  'a Los Angeles class at 02:00 UTC on 1 Nov is October; paid/partial/refunded/refund_failed each land in their own figure and pending is ignored'
);

select results_eq(
  $$ select registrations, gross_cents, platform_fee_cents, net_cents
       from host_earnings_summary()
      where event_id = 'c7c70000-0000-0000-0000-000000000001' and currency = 'eur' $$,
  $$ values (1, 3000::bigint, 150::bigint, 2850::bigint) $$,
  'a second currency on the same instance is its own row, never summed into the first'
);

select results_eq(
  $$ select local_month, timezone, partially_refunded_orders, partial_refunds_unrecorded,
            refunded_cents, net_cents
       from host_earnings_summary()
      where event_id = 'c7c70000-0000-0000-0000-000000000002' $$,
  $$ values ('2026-12-01'::date, 'UTC'::text, 1, 1, 0::bigint, 1425::bigint) $$,
  'a NULL zone falls back to UTC, and a partial refund with no recorded refund is counted as unrecorded'
);

select results_eq(
  $$ select local_month, timezone, registrations
       from host_earnings_summary()
      where event_id = 'c7c70000-0000-0000-0000-000000000003' $$,
  $$ values ('2026-12-01'::date, 'UTC'::text, 1) $$,
  'an unknown zone name falls back to UTC instead of failing the whole summary'
);

select is(
  (select count(*)::int from host_earnings_summary()), 4,
  'the host has exactly four rows: three instances, one of them in two currencies'
);

-- refusal: the organiser's own class was paid to the organiser, not this host
select is(
  (select count(*)::int from host_earnings_summary()
    where event_id = 'c7c70000-0000-0000-0000-000000000004'),
  0,
  'the host does not see a class paid to someone else in the same club'
);

-- ── as the ORGANISER, who runs the club but was not paid for these classes ──
set local "request.jwt.claims" = '{"sub":"a7a70000-0000-0000-0000-000000000002","role":"authenticated"}';

select isnt_empty(
  $$ select 1 from event_orders where event_id = 'c7c70000-0000-0000-0000-000000000001' $$,
  'positive control: the organiser can read the host''s orders through the table policy'
);

-- refusal: the organiser was not the payee of the host's classes
select is(
  (select count(*)::int from host_earnings_summary()
    where event_id = 'c7c70000-0000-0000-0000-000000000001'),
  0,
  'the organiser''s summary excludes classes whose money went to another host'
);

select results_eq(
  $$ select event_id, registrations, net_cents from host_earnings_summary() $$,
  $$ values ('c7c70000-0000-0000-0000-000000000004'::uuid, 1, 2375::bigint) $$,
  'the organiser''s summary is exactly the class paid to them'
);

-- ── as a STRANGER ──
set local "request.jwt.claims" = '{"sub":"a7a70000-0000-0000-0000-000000000004","role":"authenticated"}';

-- refusal: someone who was paid for nothing has no earnings to read
select is_empty(
  $$ select 1 from host_earnings_summary() $$,
  'a stranger''s summary is empty'
);

-- ── as ANON ──
set local role anon;
set local "request.jwt.claims" = '{"role":"anon"}';

select throws_ok(
  $$ select * from host_earnings_summary() $$,
  '42501',
  null,
  'anon cannot call host_earnings_summary'
);

reset role;

select is(
  (select provolatile from pg_proc where oid = 'public.host_earnings_summary()'::regprocedure),
  's',
  'host_earnings_summary is STABLE, so the web reads it as a GET'
);

select is(
  (select prosecdef from pg_proc where oid = 'public.host_earnings_summary()'::regprocedure),
  true,
  'host_earnings_summary is SECURITY DEFINER: payment_refunds has no client read path'
);

select * from finish();
rollback;
