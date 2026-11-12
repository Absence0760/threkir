-- Two deletes of the same runner's runs deadlocked (decisions § 2111), and
-- /runs bulk delete, which sends one DELETE per selected run in parallel, lost
-- runs to it every time. Every run write takes the per-runner 'achievements:'
-- lock in its statement triggers (award_achievements_for_user), but by then the
-- statement has already locked rows the other statement needs:
--
--  * its own runs row, which the other statement's matcher (20270901000001)
--    and PR refresh reach through a foreign key when they link or record a
--    sibling run, and
--  * through `on delete set null`, the plan_workouts, personal_records and
--    event_results rows that point at it, which the other statement's matcher
--    and PR refresh go on to write.
--
-- So one transaction held a row and waited for the lock while the other held
-- the lock and waited for the row. The fix is to take the lock before any row:
--
--  * a BEFORE STATEMENT trigger takes it for the caller, before the statement
--    touches a single row. A client writes only its own runs (RLS), so this is
--    the owner's lock, and it is the case that deadlocked.
--  * a BEFORE ROW trigger takes it for each row's owner, which covers a
--    service-role write (no caller) ahead of its referencing rows, though not
--    ahead of the runs row itself; nothing can be earlier than that inside a
--    row trigger, and the service-role writers (importers, jobs) do not run
--    same-runner deletes in parallel.
--
-- It adds no serialization that was not there: every INSERT and DELETE already
-- took this lock in runs_award_achievements_*, and an UPDATE the matcher or the
-- PR refresh acts on needs it for the same reason. The lock is re-entrant, so
-- the later calls cost nothing more. Several owners lock in uuid order.

create or replace function private.lock_run_caller()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $$
declare
  v_caller uuid := auth.uid();
begin
  if v_caller is not null then
    perform pg_advisory_xact_lock(hashtext('achievements:' || v_caller::text));
  end if;
  return null;
end;
$$;

revoke execute on function private.lock_run_caller() from public, anon, authenticated;

create or replace function private.lock_run_owner()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $$
declare
  v_user uuid;
begin
  for v_user in
    select distinct u
    from unnest(array[
      case when tg_op <> 'INSERT' then old.user_id end,
      case when tg_op <> 'DELETE' then new.user_id end
    ]) as u
    where u is not null
    order by u
  loop
    perform pg_advisory_xact_lock(hashtext('achievements:' || v_user::text));
  end loop;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

revoke execute on function private.lock_run_owner() from public, anon, authenticated;

drop trigger if exists runs_lock_caller on runs;
create trigger runs_lock_caller
  before insert or update or delete on runs
  for each statement execute function private.lock_run_caller();

drop trigger if exists runs_lock_owner on runs;
create trigger runs_lock_owner
  before insert or update or delete on runs
  for each row execute function private.lock_run_owner();
