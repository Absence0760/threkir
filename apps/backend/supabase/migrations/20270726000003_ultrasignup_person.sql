-- The runner's UltraSignup person, stored as an `integrations` row
-- (decisions § 1841).
--
-- UltraSignup's only keyless results feed is keyed by NAME —
-- `/service/events.svc/historybyname/{first}/{last}/` — and answers with every
-- same-named person it knows, each with their own numeric `Id`. Importing a
-- result therefore needs both halves: the name to fetch with and the `Id` that
-- says which of the people it returns is this runner. Settings looks the name up
-- once, the runner picks themselves from the candidates, and the pair is kept
-- here so a per-race import on /races needs no input at all.
--
-- `external_id` already holds a provider-side identity for every other row in
-- this table, so the `Id` goes there. The name gets two columns of its own rather
-- than a jsonb bag: it is two fixed fields, and both are interpolated into an
-- outbound URL, so they are worth a type and a cap rather than a registry entry.
-- They are named for the role they play — the provider-side name the identity
-- was looked up by — not for UltraSignup, because nothing about them is
-- specific to one provider.

-- The provider vocabulary widens by one. `integrations_provider_check` has been
-- the four-value list since 20260505_001; NOT VALID + VALIDATE keeps the swap
-- off an ACCESS EXCLUSIVE scan (docs/backend/migration_locks.md).
alter table public.integrations
  drop constraint integrations_provider_check;
alter table public.integrations
  add constraint integrations_provider_check
    check (provider in ('strava', 'garmin', 'parkrun', 'runsignup', 'ultrasignup'))
    not valid;
alter table public.integrations
  validate constraint integrations_provider_check;

alter table public.integrations
  add column external_first_name text,
  add column external_last_name text;

comment on column public.integrations.external_first_name is
  'Provider-side first name the identity in external_id was looked up by (UltraSignup historybyname). Owner-only, like the row.';
comment on column public.integrations.external_last_name is
  'Provider-side last name the identity in external_id was looked up by (UltraSignup historybyname). Owner-only, like the row.';

-- 60 matches the cap race-results-import applies before the name reaches the
-- URL (`ULTRASIGNUP_NAME_MAX_LEN`), so the column can hold nothing the function
-- would refuse to send.
alter table public.integrations
  add constraint integrations_external_first_name_len_chk
    check (char_length(external_first_name) <= 60) not valid;
alter table public.integrations
  add constraint integrations_external_last_name_len_chk
    check (char_length(external_last_name) <= 60) not valid;
-- A first name without a last one (or the reverse) cannot be fetched with, so it
-- is not a stored identity — refuse the half-written row rather than read it.
alter table public.integrations
  add constraint integrations_external_name_pair_chk
    check ((external_first_name is null) = (external_last_name is null)) not valid;

-- An UltraSignup row is only useful as the whole pair: a numeric person `Id`
-- (the feed's `Id` is an integer) and the name it was found under.
alter table public.integrations
  add constraint integrations_ultrasignup_identity_chk
    check (
      provider <> 'ultrasignup'
      or (external_id ~ '^[0-9]{1,12}$' and external_first_name is not null)
    ) not valid;

alter table public.integrations validate constraint integrations_external_first_name_len_chk;
alter table public.integrations validate constraint integrations_external_last_name_len_chk;
alter table public.integrations validate constraint integrations_external_name_pair_chk;
alter table public.integrations validate constraint integrations_ultrasignup_identity_chk;
