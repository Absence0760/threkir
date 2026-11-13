-- A run keeps no heart rate without health-data consent (decisions § 2513).
--
-- BEFORE INSERT OR UPDATE OF metadata, hr_series_url on runs. When the owner
-- has no health-data consent on record:
--
--   * the heart-rate keys of runs.metadata (avg_bpm, max_bpm, hr_coverage)
--     and the hr_series_url sidecar path are stripped from the row being
--     written. The run itself is kept: distance, time, track and every other
--     key go through untouched, so a recorder, an import or a sync never
--     fails for want of consent;
--   * on UPDATE, heart rate the row ALREADY held (stored before this gate)
--     is moved to private.withheld_run_hr rather than discarded, so nothing
--     stored before the gate is deleted without notice. The held copy comes
--     back when consent is given (20271227100008).
--
-- It applies to every writer, the service role included: the Strava webhook
-- and import functions and the Go worker write runs as service_role, and an
-- import is exactly where unconsented heart rate arrives.
--
-- withdraw_health_data_consent() sets `app.health_erase` for its own
-- transaction, so the erasure it performs is not turned back into a hold.
--
-- Per-point bpm inside the stored track blob ({user_id}/{run_id}.json.gz)
-- is not visible to the database. The clients strip it before upload, the
-- server-side importers strip it before they store a track, and storage
-- refuses the .hr.json.gz sidecar without consent (20271227100006).
--
-- Lock: CREATE TRIGGER takes SHARE ROW EXCLUSIVE on runs for the catalogue
-- change only; no scan, no rewrite. The one-off move of the existing backlog
-- is batched by pg_cron (20271227100009), not done here.

create or replace function private.runs_health_hr_gate()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_keys text[] := private.run_hr_metadata_keys();
  v_held jsonb;
begin
  if private.health_data_consented(new.user_id) then
    return new;
  end if;

  if tg_op = 'UPDATE'
     and coalesce(current_setting('app.health_erase', true), '') <> 'on' then
    select coalesce(jsonb_object_agg(k, old.metadata -> k), '{}'::jsonb)
      into v_held
      from unnest(v_keys) as k
     where old.metadata ? k;
    if v_held <> '{}'::jsonb or old.hr_series_url is not null then
      insert into private.withheld_run_hr (run_id, user_id, hr, hr_series_url)
      values (old.id, old.user_id, v_held, old.hr_series_url)
      on conflict (run_id) do update
        set hr = private.withheld_run_hr.hr || excluded.hr,
            hr_series_url = coalesce(excluded.hr_series_url,
                                     private.withheld_run_hr.hr_series_url),
            withheld_at = now();
    end if;
  end if;

  if new.metadata ?| v_keys then
    new.metadata := new.metadata - v_keys;
  end if;
  new.hr_series_url := null;
  return new;
end;
$$;

revoke execute on function private.runs_health_hr_gate() from public, anon, authenticated;

create trigger runs_health_hr_gate
  before insert or update of metadata, hr_series_url on public.runs
  for each row execute function private.runs_health_hr_gate();
