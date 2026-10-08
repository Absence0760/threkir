-- The platform's application-fee rate becomes platform config, readable only
-- by the service role, instead of a column the paying host writes.
--
-- event_pricing.platform_fee_bps and fundraisers.platform_fee_bps were
-- documented as "platform config, not host-set", yet each sat on a row the host
-- (or fundraiser owner) inserts and updates under their own RLS policy, with a
-- default of 0. The only writer, setEventPricing, sent 0. So every paid class
-- would have charged no application fee while the platform, as merchant of
-- record on a destination charge, still paid Stripe's processing fee and
-- carried the chargebacks. A host who knew the column existed could also set
-- it to 0 against any rate the platform chose. The checkouts now read the rate
-- from here at charge time, and the rate actually charged is recorded on each
-- order as platform_fee_cents (decisions § 1768).

create table platform_fees (
  id                boolean primary key default true,
  event_fee_bps     integer not null,
  donation_fee_bps  integer not null,
  updated_at        timestamptz not null default now()
);

alter table platform_fees add constraint platform_fees_single_row_check
  check (id);
alter table platform_fees add constraint platform_fees_event_fee_bps_range_check
  check (event_fee_bps >= 0 and event_fee_bps <= 10000);
alter table platform_fees add constraint platform_fees_donation_fee_bps_range_check
  check (donation_fee_bps >= 0 and donation_fee_bps <= 10000);

comment on table platform_fees is
  'Single-row platform config: the application-fee rate, in basis points, '
  'the checkouts charge on a paid-event registration and on a donation. Read '
  'by the service role at charge time; no client role can read or write it. '
  'Change a rate with a migration, which applies to every sale after it lands.';

alter table platform_fees enable row level security;
revoke all on table public.platform_fees from public, anon, authenticated;
grant select, insert, update, delete on table public.platform_fees to service_role;

-- 5% on paid classes (owner decision 2026-10-07, #1081 S0.2). Donations stay
-- at 0, the rate every donation has been built against.
insert into platform_fees (event_fee_bps, donation_fee_bps) values (500, 0);

alter table event_pricing drop constraint event_pricing_fee_bps_range_check;
alter table event_pricing drop column platform_fee_bps;
alter table fundraisers drop constraint fundraisers_fee_bps_range_check;
alter table fundraisers drop column platform_fee_bps;
