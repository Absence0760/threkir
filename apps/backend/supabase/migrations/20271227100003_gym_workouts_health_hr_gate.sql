-- A gym session keeps no heart rate without health-data consent (decisions
-- § 2514).
--
-- No writer stores heart rate on gym_workouts today: neither gym_sets nor
-- the gym_workouts.metadata registry (docs/backend/metadata.md) has a
-- heart-rate field. The policy still names gym heart rate as consent-gated,
-- so the gate is in place before the first writer is: the same heart-rate
-- keys runs.metadata uses (private.run_hr_metadata_keys) are stripped from
-- gym_workouts.metadata on every insert or update by an owner without
-- consent. Nothing is stored there to hold, so there is no backlog.
--
-- gym_workouts is not a high-volume table (migration_locks.md); CREATE
-- TRIGGER is a catalogue change.

create or replace function private.gym_workouts_health_hr_gate()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_keys text[] := private.run_hr_metadata_keys();
begin
  if new.metadata ?| v_keys and not private.health_data_consented(new.user_id) then
    new.metadata := new.metadata - v_keys;
  end if;
  return new;
end;
$$;

revoke execute on function private.gym_workouts_health_hr_gate() from public, anon, authenticated;

create trigger gym_workouts_health_hr_gate
  before insert or update of metadata on public.gym_workouts
  for each row execute function private.gym_workouts_health_hr_gate();
