-- Pins migration 20270716000001 (decisions § 1768): the application-fee rate is
-- platform config that only the service role can see, not a column on a row
-- the paying host writes.
--   * exactly one row, at the owner-decided 500 bps on events and 0 on donations;
--   * a second row is impossible;
--   * no client role can read or change it;
--   * the host-writable rows no longer carry a rate at all.

begin;
select plan(9);

set local role service_role;

select is(
  (select count(*)::int from platform_fees), 1,
  'platform_fees holds exactly one row'
);
select is(
  (select event_fee_bps from platform_fees), 500,
  'paid events are charged 500 bps'
);
select is(
  (select donation_fee_bps from platform_fees), 0,
  'donations are charged 0 bps'
);
select throws_ok(
  $$ insert into platform_fees (id, event_fee_bps, donation_fee_bps) values (false, 0, 0) $$,
  '23514',
  null,
  'a second row is refused by the single-row CHECK'
);
select throws_ok(
  $$ update platform_fees set event_fee_bps = 10001 $$,
  '23514',
  null,
  'a rate above 100% is refused'
);

set local role authenticated;
set local "request.jwt.claims" =
  '{"sub":"aaaa3333-0000-0000-0000-000000000001","role":"authenticated"}';

select throws_ok(
  $$ select event_fee_bps from platform_fees $$,
  '42501',
  null,
  'a signed-in user cannot read the rate'
);
select throws_ok(
  $$ update platform_fees set event_fee_bps = 0 $$,
  '42501',
  null,
  'a signed-in user cannot change the rate'
);

reset role;

select hasnt_column('public', 'event_pricing', 'platform_fee_bps',
  'event_pricing no longer carries a host-writable rate');
select hasnt_column('public', 'fundraisers', 'platform_fee_bps',
  'fundraisers no longer carries an owner-writable rate');

select * from finish();
rollback;
