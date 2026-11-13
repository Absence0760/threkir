-- A race ping carries heart rate only with health-data consent (decisions
-- § 2514).
--
-- live_run_pings already drops bpm without consent
-- (private.live_run_pings_strip_bpm, 20271104000001). race_pings, its
-- event-keyed twin that every spectator of a race can read, kept whatever
-- bpm the recorder sent. Same pattern: a BEFORE INSERT trigger nulls bpm when
-- the runner has no consent, and the ping itself is kept. An out-of-range
-- value is left for race_pings_bpm_check to refuse, as the live twin does.
--
-- race_pings is insert-only for clients (no UPDATE policy), so BEFORE INSERT
-- is the whole write surface. Pings stored before this gate are not
-- rewritten: the table is high-volume and the retention sweep removes every
-- ping within 48 hours (at most 8 days for a self-timed window), so the
-- backlog ages out on its own; withdraw_health_data_consent() nulls the
-- caller's at once.
--
-- Lock: CREATE TRIGGER, a catalogue change; no scan.

create or replace function private.race_pings_strip_bpm()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
begin
  if new.bpm between 0 and 300 and not private.health_data_consented(new.user_id) then
    new.bpm := null;
  end if;
  return new;
end;
$$;

revoke execute on function private.race_pings_strip_bpm() from public, anon, authenticated;

create trigger race_pings_strip_bpm_before_insert
  before insert on public.race_pings
  for each row execute function private.race_pings_strip_bpm();
