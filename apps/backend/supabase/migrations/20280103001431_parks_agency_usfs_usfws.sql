-- Two more land managers for parks.agency (issue #1431, decisions § 2593):
-- usfs (a US Forest Service national forest, the George Washington & Jefferson
-- National Forests) and usfws (a US Fish & Wildlife Service national wildlife
-- refuge). Neither is a National Park Service unit, so neither takes an
-- nps_park_code and the NPS alerts sweep (agency = 'nps') passes them by.
-- scripts/parks/lib/catalogue_payload.mjs refuses a value outside
-- PARK_AGENCIES before the database sees it.
--
-- Locks (docs/backend/migration_locks.md): `parks` is a small catalogue table,
-- so the online form is ceremony here, but it is the playbook's widening shape
-- all the same: drop the old CHECK and add the wider one NOT VALID (a metadata
-- flip; new and updated rows are enforced at once), and VALIDATE it in the
-- next migration's own transaction. Every existing row already holds one of
-- the four older values.

alter table public.parks
  drop constraint parks_agency_check,
  add constraint parks_agency_check
    check (agency in ('nps', 'state', 'county', 'usfs', 'usfws', 'other'))
    not valid;

comment on column public.parks.agency is
  'Who runs the place: nps (National Park Service), state, county, usfs (US Forest Service national forest), '
  'usfws (US Fish & Wildlife Service wildlife refuge) or other. Written by load_park_catalogue from park.json '
  '(decisions § 2593).';
