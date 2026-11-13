-- Heart rate and the food log follow health-data consent (decisions § 2514).
--
-- The privacy policy (§§ 2-3) and the health-data notice (§ 2) say heart
-- rate and nutrition / food logs are special-category data processed only
-- with explicit consent (Art 9(2)(a)). Until now only height, gender, the
-- weight series, cycle data and the date-of-birth mirror were gated. This
-- file adds what the gates in the following migrations share:
--
--   * private.health_data_consented(uid): the one consent predicate. Every
--     gate reads it, so the rule is written once.
--   * private.run_hr_metadata_keys(): the heart-rate keys of runs.metadata
--     (docs/backend/metadata.md): avg_bpm, max_bpm, hr_coverage.
--   * private.withheld_run_hr: where heart rate stored before the gate, by a
--     runner who has not consented, is moved instead of deleted. Nothing reads
--     it except the consent transition (which puts it back) and the erasure
--     paths. The private schema is not exposed through PostgREST, so a held
--     value is hidden from every client read.
--   * private.health_backlog_purge_enabled(): the deploy gate on the purge of
--     that held backlog. No migration writes the row, so every environment
--     starts closed; apps/backend/ops/prod_config.json declares it off until
--     counsel approves deleting data that was stored before the gate.
--
-- Only new objects; no lock on a populated table beyond the brief SHARE ROW
-- EXCLUSIVE the withheld table's foreign key to runs takes in the catalogue.

create or replace function private.health_data_consented(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select p_user_id is not null
     and exists (
       select 1 from public.user_profiles p
        where p.id = p_user_id
          and p.health_data_consent_at is not null
     );
$$;

revoke execute on function private.health_data_consented(uuid) from public, anon;
grant execute on function private.health_data_consented(uuid) to authenticated, service_role;

comment on function private.health_data_consented(uuid) is
  'Whether a user has health-data consent (Art 9(2)(a)) on record. The one '
  'predicate the heart-rate and food-log gates read (decisions § 2514).';

-- The server-side importers' question (the Strava webhook and import Edge
-- Functions, the Go worker's strava_event and health_hr_erase handlers):
-- whether to keep a heart-rate stream for this runner. Service role only;
-- a client must not be able to ask about another runner's consent.
create or replace function public.health_data_consented(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, private
as $$
  select private.health_data_consented(p_user_id);
$$;

revoke execute on function public.health_data_consented(uuid) from public, anon, authenticated;
grant execute on function public.health_data_consented(uuid) to service_role;

create or replace function private.run_hr_metadata_keys()
returns text[]
language sql
immutable
set search_path = pg_catalog
as $$
  select array['avg_bpm', 'max_bpm', 'hr_coverage']::text[];
$$;

revoke execute on function private.run_hr_metadata_keys() from public, anon, authenticated;
grant execute on function private.run_hr_metadata_keys() to service_role;

create table private.withheld_run_hr (
  run_id        uuid primary key references public.runs(id) on delete cascade,
  user_id       uuid not null references auth.users(id) on delete cascade,
  hr            jsonb not null default '{}'::jsonb
                check (jsonb_typeof(hr) = 'object'),
  hr_series_url text,
  withheld_at   timestamptz not null default now()
);

create index withheld_run_hr_user on private.withheld_run_hr (user_id);

alter table private.withheld_run_hr enable row level security;
revoke all on private.withheld_run_hr from public, anon, authenticated;
grant select, insert, update, delete on private.withheld_run_hr to service_role;

comment on table private.withheld_run_hr is
  'Heart rate a runner stored before the consent gate (decisions § 2514), '
  'held out of runs while they have no health-data consent. Restored when '
  'consent is given, erased by withdraw_health_data_consent(), purged only '
  'when the health_backlog_purge feature flag is on.';

create or replace function private.health_backlog_purge_enabled()
returns boolean
language sql
stable
security definer
set search_path = public, private
as $$
  select coalesce(
    (select f.enabled from private.feature_flags f where f.name = 'health_backlog_purge'),
    false
  );
$$;

revoke execute on function private.health_backlog_purge_enabled() from public, anon, authenticated;
grant execute on function private.health_backlog_purge_enabled() to service_role;
