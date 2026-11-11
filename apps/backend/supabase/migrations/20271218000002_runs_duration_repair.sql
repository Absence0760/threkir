-- Repairs the runs stored above runs_duration_s_max_check's ten days, so the
-- constraint can be validated (20271218000003). Owner decision on issue #1300
-- § 5, 2026-11-10, decisions § 2464: a release-applied repair, never
-- hand-run SQL.
--
-- Two steps, because the honest duration of such a row, where there is one,
-- is in its track, and the track is a gzipped object in Storage that SQL
-- cannot read:
--
--   1. Here: every such row is capped at 864000 and marked. The bag gains
--      `duration_repaired: true` (the stored duration is a placeholder, not a
--      measurement) and `duration_s_original` (the value it replaced). A row
--      with a stored track also gets a `duration_repair` job.
--   2. The job_worker's `duration_repair` handler reads the track's
--      timestamps and, when they give a believable span, writes it in place
--      of the cap. A row with no track (a manual entry, like the issue's own)
--      keeps the cap until its owner edits the duration.
--
-- The cap must not count as ten days of running. `private.run_duration_in_bound`
-- and its client twins (`isPlausibleRunDuration`, the `run_duration` parity
-- pair) become strict at the top: exactly 864000 s is the repair's
-- placeholder, so every duration total leaves a capped row out, as it left out
-- the original value, and the personal-records refresher ranks none. The column still admits 864000 (the cap must satisfy the
-- CHECK); the manual forms now refuse it too, so no writer produces it.
--
-- The flag follows the duration. `runs_keep_duration_repair` keeps
-- `duration_repaired` while `duration_s` is unchanged and drops it on the
-- write that changes it, whoever writes: the owner's edit and the job alike.
-- `duration_s_original` is kept on every later write. A client holding a copy
-- from before this migration writes a duration over the bound, which the
-- constraint refuses and api_client parks as `durationOutOfRange`. One holding
-- a copy of the capped row (the batch sync's whole-row upsert, a backup
-- restore) writes 864000 back after the job or the owner replaced it; the
-- trigger keeps the stored duration for that write, as
-- `runs_keep_distance_recompute` keeps a recomputed distance, and the flag
-- stays off, so the repair is not undone.
--
-- Locks (docs/backend/migration_locks.md): the UPDATE is scoped by its
-- predicate and touches only the out-of-bound rows, a handful, so it row-locks
-- those and nothing else; finding them is a sequential read that blocks no
-- reader or writer. Batching by id range would split the read without
-- shortening any lock. Its `jobs` insert runs in the same order a run save
-- does (the `runs` row, then `jobs`), so it cannot deadlock against one.
-- CREATE TRIGGER comes last: its SHARE ROW EXCLUSIVE then lasts only to the
-- commit, rather than across the read.

create or replace function private.run_duration_in_bound(p_duration_s integer)
returns boolean
language sql
immutable
set search_path = pg_catalog
as $$
  select p_duration_s >= 0 and p_duration_s < 864000
$$;

revoke execute on function private.run_duration_in_bound(integer) from public, anon, authenticated;

comment on function private.run_duration_in_bound(integer) is
  'The read-side bound on runs.duration_s: 0 <= duration_s < 864000. A duration '
  'aggregate sums only rows inside it. Exactly 864000 is the placeholder '
  '20271218000002 stored over an out-of-bound row, so it is left out with '
  'them. SQL twin of isPlausibleRunDuration in the run_duration parity pair '
  '(decisions § 2359, § 2464).';

-- The cap is no best either. The whole-run branch of the personal-records
-- refresher ranks on `duration_s asc` with a floor and no ceiling, so a capped
-- run that is its owner's only run in a bracket would hold that PR at
-- 240:00:00, and the cap itself, being faster than the value it replaced,
-- would be logged as an improvement and notified for a run of the last seven
-- days. The branch now takes only in-bound durations. The live body
-- (20271104000002) with that one predicate added; it must precede the cap
-- below, whose UPDATE fires the refresh.
CREATE OR REPLACE FUNCTION public.refresh_personal_records_for_user(p_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_role text := coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'),
    ''
  );
  v_before jsonb;
begin
  if v_role <> 'service_role' and v_role <> '' then
    if auth.uid() is null or auth.uid() is distinct from p_user_id then
      raise exception 'refresh_personal_records_for_user: not authorized'
        using errcode = '42501';
    end if;
  end if;

  perform pg_advisory_xact_lock(
    hashtext('personal_records:' || p_user_id::text)
  );

  select coalesce(jsonb_object_agg(distance, best_time_s), '{}'::jsonb)
    into v_before
    from personal_records
   where user_id = p_user_id;

  delete from personal_records where user_id = p_user_id;

  insert into personal_records (user_id, distance, best_time_s, run_id, achieved_at)
  select
    p_user_id, distance, duration_s, run_id, achieved_at
  from (
    select
      run_id, duration_s, achieved_at, distance,
      row_number() over (
        partition by distance
        order by duration_s asc, achieved_at asc, run_id asc
      ) as rn
    from (
      -- Whole-run candidates, widened brackets, DNFs excluded.
      select
        id as run_id,
        duration_s,
        started_at as achieved_at,
        case
          when distance_m between 1559  and 1659   then '1_mile'
          when distance_m between 4900  and 5100   then '5k'
          when distance_m between 7840  and 8160   then '8k'
          when distance_m between 9800  and 10200  then '10k'
          when distance_m between 11760 and 12240  then '12k'
          when distance_m between 20675 and 21519  then 'half_marathon'
          when distance_m between 41351 and 43039  then 'marathon'
        end as distance
      from runs
      where user_id = p_user_id
        -- 'parkrun' (certified weekly 5K) + 'race' (chip-timed official results,
        -- the most authoritative source) are valid runs.source values (#378).
        and source in ('app', 'watch', 'strava', 'garmin', 'healthkit', 'healthconnect', 'parkrun', 'race')
        -- Run family only: a bicycle covers a PR bracket at speeds no runner
        -- reaches. Mirrors the client's `isRunFamily` in recap.ts.
        and activity_type <> 'cycle'
        and distance_m is not null
        and duration_s is not null
        and duration_s > 0
        and private.run_duration_in_bound(duration_s)
        and is_dnf = false

      union all

      -- Embedded-best 5k from the promoted fastest_5k_s column.
      select
        id as run_id, fastest_5k_s,
        started_at as achieved_at, '5k' as distance
      from runs
      where user_id = p_user_id
        and source in ('app', 'watch', 'strava', 'garmin', 'healthkit', 'healthconnect', 'parkrun', 'race')
        and activity_type <> 'cycle'
        and fastest_5k_s is not null
        and fastest_5k_s > 0
        and is_dnf = false

      union all

      select
        id as run_id, fastest_10k_s,
        started_at as achieved_at, '10k' as distance
      from runs
      where user_id = p_user_id
        and source in ('app', 'watch', 'strava', 'garmin', 'healthkit', 'healthconnect', 'parkrun', 'race')
        and activity_type <> 'cycle'
        and fastest_10k_s is not null
        and fastest_10k_s > 0
        and is_dnf = false

      union all

      select
        id as run_id, fastest_half_marathon_s,
        started_at as achieved_at, 'half_marathon' as distance
      from runs
      where user_id = p_user_id
        and source in ('app', 'watch', 'strava', 'garmin', 'healthkit', 'healthconnect', 'parkrun', 'race')
        and activity_type <> 'cycle'
        and fastest_half_marathon_s is not null
        and fastest_half_marathon_s > 0
        and is_dnf = false

      union all

      select
        id as run_id, fastest_marathon_s,
        started_at as achieved_at, 'marathon' as distance
      from runs
      where user_id = p_user_id
        and source in ('app', 'watch', 'strava', 'garmin', 'healthkit', 'healthconnect', 'parkrun', 'race')
        and activity_type <> 'cycle'
        and fastest_marathon_s is not null
        and fastest_marathon_s > 0
        and is_dnf = false
    ) candidates
    where distance is not null
  ) ranked
  where rn = 1;

  perform private.record_personal_record_improvements(p_user_id, v_before);
end;
$function$;

-- A function rather than a bare statement so runs_duration_repair_test.sql can
-- drive the exact repair this migration applies.
create or replace function private.cap_out_of_bound_run_durations()
returns integer
language plpgsql
set search_path = public, pg_catalog
as $$
declare
  v_capped integer;
begin
  with repaired as (
    update runs
       set duration_s = 864000,
           metadata = coalesce(metadata, '{}'::jsonb)
             || jsonb_build_object('duration_repaired', true,
                                   'duration_s_original', duration_s)
     where duration_s > 864000
    returning id, user_id, track_url
  ), enqueued as (
    insert into jobs (kind, payload)
    select 'duration_repair', jsonb_build_object('run_id', r.id, 'user_id', r.user_id)
      from repaired r
     where r.track_url is not null
       and r.track_url <> ''
    returning 1
  )
  select count(*) into v_capped from repaired;
  return v_capped;
end;
$$;

revoke execute on function private.cap_out_of_bound_run_durations() from public, anon, authenticated;

comment on function private.cap_out_of_bound_run_durations() is
  'Caps every run above runs_duration_s_max_check at 864000, marks it '
  '(metadata.duration_repaired, metadata.duration_s_original) and enqueues a '
  'duration_repair job for each one with a track. Applied once by '
  '20271218000002; returns the number capped (decisions § 2464).';

select private.cap_out_of_bound_run_durations();

create or replace function private.runs_keep_duration_repair()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
declare
  v_old jsonb := coalesce(old.metadata, '{}'::jsonb);
begin
  new.metadata := coalesce(new.metadata, '{}'::jsonb);

  if v_old ? 'duration_s_original' and not (new.metadata ? 'duration_s_original') then
    new.metadata := new.metadata
      || jsonb_build_object('duration_s_original', v_old -> 'duration_s_original');
  end if;

  -- No writer produces 864000 (the forms refuse it, the job never writes it),
  -- so 864000 arriving over another duration is a copy loaded while the run
  -- was capped, written back after the job or the owner replaced the cap.
  if new.duration_s = 864000 and old.duration_s is distinct from 864000 then
    new.duration_s := old.duration_s;
  end if;

  if v_old ? 'duration_repaired' and new.duration_s is not distinct from old.duration_s then
    new.metadata := new.metadata || jsonb_build_object('duration_repaired', true);
  else
    new.metadata := new.metadata - 'duration_repaired';
  end if;

  return new;
end;
$$;

revoke execute on function private.runs_keep_duration_repair() from public, anon, authenticated;

comment on function private.runs_keep_duration_repair() is
  'Keeps metadata.duration_repaired while runs.duration_s still holds the cap '
  '20271218000002 stored, drops it on the write that changes the duration, '
  'keeps the stored duration when a stale copy writes the cap back over it, '
  'and keeps metadata.duration_s_original on every write (decisions § 2464).';

create trigger runs_keep_duration_repair
  before update on runs
  for each row
  when (old.metadata ?| array['duration_repaired', 'duration_s_original'])
  execute function private.runs_keep_duration_repair();
