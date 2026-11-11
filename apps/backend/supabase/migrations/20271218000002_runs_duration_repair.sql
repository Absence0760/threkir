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
-- the original value. The column still admits 864000 (the cap must satisfy the
-- CHECK); the manual forms now refuse it too, so no writer produces it.
--
-- The flag follows the duration. `runs_keep_duration_repair` keeps
-- `duration_repaired` while `duration_s` is unchanged and drops it on the
-- write that changes it, whoever writes: the owner's edit and the job alike.
-- `duration_s_original` is kept on every later write. A client holding a copy
-- from before this migration writes a duration over the bound, which the
-- constraint refuses and api_client parks as `durationOutOfRange`.
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

  if v_old ? 'duration_repaired' then
    if new.duration_s is distinct from old.duration_s then
      new.metadata := new.metadata - 'duration_repaired';
    else
      new.metadata := new.metadata || jsonb_build_object('duration_repaired', true);
    end if;
  end if;

  return new;
end;
$$;

revoke execute on function private.runs_keep_duration_repair() from public, anon, authenticated;

comment on function private.runs_keep_duration_repair() is
  'Keeps metadata.duration_repaired while runs.duration_s still holds the cap '
  '20271218000002 stored, drops it on the write that changes the duration, '
  'and keeps metadata.duration_s_original on every write (decisions § 2464).';

create trigger runs_keep_duration_repair
  before update on runs
  for each row
  when (old.metadata ?| array['duration_repaired', 'duration_s_original'])
  execute function private.runs_keep_duration_repair();
