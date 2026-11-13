-- The heart rate and food stored before the consent gate, by runners without
-- consent: hidden now, deleted only on request or after counsel approves
-- (decisions § 2513).
--
-- Food needs no move: the select policy (20271227100004) already hides a
-- runner's rows while they have no consent. Heart rate sits inside runs rows
-- the runner can read, so it is moved out to private.withheld_run_hr.
--
-- 1. The drain. runs is the highest-volume table (migration_locks.md
--    § Large backfills), so the move is not one statement in this file. A
--    pg_cron job walks runs in primary-key order, 2000 ids a minute, from a
--    cursor kept in private.health_backlog_drain. Each step re-writes
--    metadata on only the rows in its range that still carry heart rate for
--    an owner without consent; the BEFORE trigger (20271227100002) does the
--    move. Each step is its own short transaction and locks only the rows it
--    changes. When a step finds no further ids it records done_at and
--    unschedules itself, so the scan never repeats.
--
--    Runs written after the gate never need it (the trigger strips them on
--    the way in), so the drain only ever has the pre-gate rows to find.
--
-- 2. The purge, OFF. private.purge_health_backlog() erases the held heart
--    rate and the hidden food of every runner who still has no consent,
--    through the same private.erase_health_records() a withdrawal uses (which
--    also queues the Storage clean-up). It runs daily and does nothing unless
--    the `health_backlog_purge` feature flag is on. No migration writes that
--    row; apps/backend/ops/prod_config.json declares it off, and turning it on
--    is a counsel sign-off (decisions § 2430), because it deletes data the
--    runner stored before being told it needed consent. 200 runners a day.

create table private.health_backlog_drain (
  singleton   boolean primary key default true check (singleton),
  last_run_id uuid,
  steps       integer not null default 0,
  moved       bigint not null default 0,
  done_at     timestamptz
);

insert into private.health_backlog_drain (singleton) values (true);

alter table private.health_backlog_drain enable row level security;
revoke all on private.health_backlog_drain from public, anon, authenticated;
grant select on private.health_backlog_drain to service_role;

create or replace function private.drain_unconsented_run_hr(p_scan integer default 2000)
returns integer
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_state private.health_backlog_drain%rowtype;
  v_hi    uuid;
  v_seen  integer;
  v_moved integer := 0;
  v_keys  text[] := private.run_hr_metadata_keys();
begin
  select * into v_state from private.health_backlog_drain where singleton for update;
  if v_state.done_at is not null then
    return 0;
  end if;

  select max(id::text)::uuid, count(*)
    into v_hi, v_seen
    from (
      select r.id
        from public.runs r
       where v_state.last_run_id is null or r.id > v_state.last_run_id
       order by r.id
       limit greatest(p_scan, 1)
    ) ids;

  if v_seen = 0 then
    update private.health_backlog_drain
       set done_at = now(), steps = steps + 1
     where singleton;
    if exists (select 1 from cron.job where jobname = 'withhold-unconsented-run-hr') then
      perform cron.unschedule('withhold-unconsented-run-hr');
    end if;
    return 0;
  end if;

  update public.runs r
     set metadata = r.metadata
   where (v_state.last_run_id is null or r.id > v_state.last_run_id)
     and r.id <= v_hi
     and (r.metadata ?| v_keys or r.hr_series_url is not null)
     and not private.health_data_consented(r.user_id);
  get diagnostics v_moved = row_count;

  update private.health_backlog_drain
     set last_run_id = v_hi,
         steps = steps + 1,
         moved = moved + v_moved
   where singleton;
  return v_moved;
end;
$$;

revoke execute on function private.drain_unconsented_run_hr(integer) from public, anon, authenticated;
grant execute on function private.drain_unconsented_run_hr(integer) to service_role;

select cron.schedule(
  'withhold-unconsented-run-hr',
  '* * * * *',
  $$select private.drain_unconsented_run_hr(2000)$$
);

create or replace function private.purge_health_backlog(p_users integer default 200)
returns integer
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_uid uuid;
  v_n   integer := 0;
begin
  if not private.health_backlog_purge_enabled() then
    return 0;
  end if;
  for v_uid in
    select u.user_id
      from (
        select w.user_id from private.withheld_run_hr w
        union
        select f.user_id from public.food_log f
      ) u
     where not private.health_data_consented(u.user_id)
     limit greatest(p_users, 1)
  loop
    perform private.erase_health_records(v_uid);
    v_n := v_n + 1;
  end loop;
  if v_n > 0 then
    raise notice 'purge_health_backlog: erased the held heart rate and food of % runner(s)', v_n;
  end if;
  return v_n;
end;
$$;

revoke execute on function private.purge_health_backlog(integer) from public, anon, authenticated;
grant execute on function private.purge_health_backlog(integer) to service_role;

select cron.schedule(
  'purge-health-backlog',
  '53 3 * * *',  -- 03:53 UTC daily, off the other 03:xx retention minutes.
  $$select private.purge_health_backlog(200)$$
);

comment on function private.purge_health_backlog(integer) is
  'Erases the pre-gate heart rate and food of runners who still have no '
  'health-data consent (decisions § 2513). Does nothing unless the '
  'health_backlog_purge feature flag is on (counsel sign-off, § 2430). '
  'Scheduled by pg_cron entry `purge-health-backlog` (03:53 UTC daily).';
