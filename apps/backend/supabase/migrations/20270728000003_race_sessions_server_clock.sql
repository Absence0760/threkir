-- race_sessions.started_at and finished_at are the database's clock for every
-- client caller (decisions § 1851).
--
-- 20270727000001 stamped started_at = now() on the move to running, but the
-- trigger fired only on a status change, so a race director could rewrite
-- started_at while the race was running — moving every racer's gun time — and
-- finished_at was whatever the host device sent, which is also the anchor of
-- the 24 h result window. Now, for a client caller:
--
--   * started_at is now() on the move to running and immutable afterwards
--     (running and finished);
--   * finished_at is now() on the move to finished and immutable afterwards.
--
-- The service role and direct SQL (migrations, seed, pgtap with no JWT) keep
-- the values they write: the operator and fixture paths backdate a race on
-- purpose. Trust follows the house test (20270702000001): the service-role
-- JWT claim, or no role claim with a privileged session_user, which no
-- PostgREST request can present.
--
-- The trigger fires on every UPDATE, not just a status change, which is what
-- closes the running-edit gap. Its name sorts after
-- race_sessions_enforce_transition_trg, so an illegal transition is refused
-- before anything is stamped.
--
-- Locks: CREATE TRIGGER on race_sessions (a bounded per-occurrence table) is
-- SHARE ROW EXCLUSIVE, catalogue-only.

set search_path = public;

create or replace function public.race_sessions_server_clock()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_role text := coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'),
    ''
  );
begin
  if v_role = 'service_role'
     or (v_role = '' and session_user in ('postgres', 'supabase_admin'))
  then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.status in ('running', 'finished') then
      new.started_at := now();
    end if;
    if new.status = 'finished' then
      new.finished_at := now();
    end if;
    return new;
  end if;

  if old.status in ('running', 'finished') then
    new.started_at := old.started_at;
  elsif new.status = 'running' then
    new.started_at := now();
  end if;

  if old.status = 'finished' then
    new.finished_at := old.finished_at;
  elsif new.status = 'finished' then
    new.finished_at := now();
  end if;

  return new;
end;
$$;

drop trigger race_sessions_stamp_started_at_trg on public.race_sessions;
drop function public.race_sessions_stamp_started_at();

create trigger race_sessions_server_clock_trg
  before insert or update on public.race_sessions
  for each row execute function public.race_sessions_server_clock();
