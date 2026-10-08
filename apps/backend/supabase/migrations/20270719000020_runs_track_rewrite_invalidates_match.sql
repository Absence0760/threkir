-- A run's track re-uploaded in place invalidates everything matched on it.
--
-- runs_track_url_path_shape (20260621_001) allows exactly one non-null
-- track_url per run, `{user_id}/{run_id}.json.gz`, so a client that rewrites
-- the track (web save, mobile sync, a backup restore) overwrites the same
-- Storage object and the row does not change. runs_enqueue_match_job only
-- fires on a track_url change, and the worker's source_track_url CAS
-- (20260611_001) compares two equal paths, so nothing noticed: the road
-- distance (metadata.distance_map_matched_m) and the matched track
-- (run_matched_tracks) kept describing the bytes that were replaced, and a
-- map_match job running across the rewrite could write the old bytes'
-- result after it.
--
-- What does change is the object's version. storage-api stamps a fresh
-- random UUID on every upload (Uploader.prepareUpload) and writes the row in
-- one upsert, ON CONFLICT (name, bucket_id) DO UPDATE SET version, metadata
-- (measured in storage-api v1.44.11's dist/storage/database/knex.js), so
-- runs_track_object_version() below is the identity of the bytes behind a
-- track_url. An object written before storage-api versioned objects has a
-- null version; its id stands in, and the next upload replaces it with a
-- version, so the token still changes. Five pieces use it:
--
--   1. runs_track_object_rewritten, AFTER INSERT OR UPDATE on storage.objects
--      for the canonical track path of an existing run whose token changed:
--      drops the road distance, resets run_matched_tracks to pending exactly
--      as runs_enqueue_match_job does for a new track_url, and queues a
--      map_match job. The invalidation and the enqueue each sit in their own
--      exception block, so a failure in either is logged and never fails the
--      user's upload or the other — the track is L1, the match is auxiliary;
--      runs_road_distance_matches_track below still refuses the stale figure
--      on every later write.
--   2. runs_road_distance_matches_track, BEFORE INSERT OR UPDATE on runs:
--      keeps distance_map_matched_m only beside a
--      distance_map_matched_track_version equal to the stored object's
--      token. A bag carrying any other pair (a client copy loaded before the
--      rewrite, a backup's metadata, a worker job that downloaded the old
--      bytes) gets the stored pair back if that is still current, else none.
--      Named to sort after runs_keep_distance_recompute, whose carry-forward
--      it validates.
--   3. map_match_track_source(run) — track_url and its token in one read,
--      for the worker before it downloads.
--   4. record_map_match_result(...) — the worker's run_matched_tracks write,
--      replacing a PATCH filtered on source_track_url. It locks the row,
--      then compares track_url and the token, so it serialises against (1)'s
--      reset of the same row: whichever commits second sees the other.
--   5. finish_job re-queues a map_match job that ends 'done' while its run's
--      row is still pending — a result refused by (4), or a reset by (1)
--      after the job wrote. jobs_dedupe_map_match keeps one queued-or-running
--      map_match per run, so (1)'s enqueue is a no-op while a job runs and
--      the rewrite would otherwise never be matched. Bounded by max_attempts
--      (claim_next_job bumps attempts); this also closes the same hole for a
--      track_url change racing a running job.
--
-- The reset in (1) updates the runs row unconditionally (not filtered on the
-- key being present): a worker write that has added the key and not yet
-- committed is invisible to a filtered UPDATE's snapshot and would be
-- skipped, whereas an UPDATE by id waits for it and re-applies the strip.
--
-- Hosted Supabase: storage.objects is owned by supabase_storage_admin, but
-- `postgres` holds TRIGGER on it (and on the local image, measured via
-- information_schema.role_table_grants), and CREATE TRIGGER needs only the
-- TRIGGER privilege, not ownership. export_surface_contract_test already
-- creates a row trigger on storage.objects as this role.
--
-- Locks (docs/backend/migration_locks.md): CREATE TRIGGER takes SHARE ROW
-- EXCLUSIVE on storage.objects and on runs — catalogue-only, O(1), blocks
-- concurrent writes to those tables only for the instant of the change.
-- CREATE OR REPLACE FUNCTION takes none. No scan, no rewrite, no backfill:
-- distance_map_matched_m has not shipped to prod (it arrives in the same
-- release as this migration), so there is no unversioned figure to
-- grandfather; a pre-release row carrying one loses it on its next write and
-- regains it, versioned, on its next match.

create or replace function public.runs_track_object_version(p_track_url text)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(o.version, o.id::text)
    from storage.objects o
   where o.bucket_id = 'runs'
     and o.name = p_track_url;
$$;

revoke execute on function public.runs_track_object_version(text) from public, anon, authenticated;
grant execute on function public.runs_track_object_version(text) to service_role;

comment on function public.runs_track_object_version(text) is
  'Identity of the bytes behind a runs track_url: the Storage object''s '
  'version (a fresh UUID per upload), or its id for an object written before '
  'storage-api versioned objects. Null when no object exists. 20270719000020.';

-- ── 1. the rewrite trigger on storage.objects ─────────────────────────────

create or replace function public.runs_track_object_rewritten()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_run_id uuid;
  v_user_id uuid;
begin
  if tg_op = 'UPDATE'
     and new.name is not distinct from old.name
     and coalesce(new.version, new.id::text) is not distinct from coalesce(old.version, old.id::text) then
    return null;
  end if;

  v_run_id := substring(new.name from
    '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.json\.gz$')::uuid;
  if v_run_id is null then
    return null;
  end if;

  select r.user_id into v_user_id
    from runs r
   where r.id = v_run_id
     and r.track_url = new.name;
  if not found then
    return null;
  end if;

  begin
    update runs
       set metadata = coalesce(metadata, '{}'::jsonb)
                      - 'distance_map_matched_m'
                      - 'distance_map_matched_track_version'
     where id = v_run_id;

    insert into run_matched_tracks (run_id, status, source_track_url)
    values (v_run_id, 'pending', new.name)
    on conflict (run_id) do update
    set status = 'pending',
        source_track_url = excluded.source_track_url,
        matched_track_url = null,
        attempts = 0,
        matched_at = null,
        error_message = null,
        algorithm = null,
        algorithm_version = null;
  exception when others then
    raise warning 'runs_track_object_rewritten: run % not invalidated: % (%)',
      v_run_id, sqlerrm, sqlstate;
  end;

  begin
    insert into jobs (kind, payload, scheduled_at)
    values (
      'map_match',
      jsonb_build_object('run_id', v_run_id, 'user_id', v_user_id),
      job_scheduled_at_for_user(v_user_id)
    )
    on conflict do nothing;
  exception when others then
    raise warning 'runs_track_object_rewritten: run % re-match not queued: % (%)',
      v_run_id, sqlerrm, sqlstate;
  end;

  return null;
end;
$$;

revoke execute on function public.runs_track_object_rewritten() from public, anon, authenticated;

drop trigger if exists runs_track_object_rewritten on storage.objects;
create trigger runs_track_object_rewritten
  after insert or update on storage.objects
  for each row
  when (new.bucket_id = 'runs')
  execute function public.runs_track_object_rewritten();

-- ── 2. the road distance only ever describes the stored bytes ─────────────

create or replace function public.runs_road_distance_matches_track()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_new jsonb := coalesce(new.metadata, '{}'::jsonb);
  v_old jsonb;
  v_current text;
begin
  if not (v_new ? 'distance_map_matched_m' or v_new ? 'distance_map_matched_track_version') then
    return new;
  end if;

  if new.track_url is not null then
    v_current := public.runs_track_object_version(new.track_url);
  end if;

  if v_current is not null
     and v_new ? 'distance_map_matched_m'
     and v_new ->> 'distance_map_matched_track_version' = v_current then
    return new;
  end if;

  new.metadata := v_new - 'distance_map_matched_m' - 'distance_map_matched_track_version';

  if tg_op = 'UPDATE' and v_current is not null
     and new.track_url is not distinct from old.track_url then
    v_old := coalesce(old.metadata, '{}'::jsonb);
    if v_old ? 'distance_map_matched_m'
       and v_old ->> 'distance_map_matched_track_version' = v_current then
      new.metadata := new.metadata || jsonb_build_object(
        'distance_map_matched_m', v_old -> 'distance_map_matched_m',
        'distance_map_matched_track_version', v_old -> 'distance_map_matched_track_version'
      );
    end if;
  end if;

  return new;
end;
$$;

revoke execute on function public.runs_road_distance_matches_track() from public, anon, authenticated;

drop trigger if exists runs_road_distance_matches_track on public.runs;
create trigger runs_road_distance_matches_track
  before insert or update on public.runs
  for each row execute function public.runs_road_distance_matches_track();

-- runs_keep_distance_recompute carries the version with the figure, so a
-- client bag that omits both keeps a current pair rather than a bare figure
-- (2) would then drop. Body otherwise as 20270719000006.
create or replace function public.runs_keep_distance_recompute()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_recorded numeric;
  v_old jsonb := coalesce(old.metadata, '{}'::jsonb);
begin
  if v_old ? 'distance_map_matched_m'
     and not (coalesce(new.metadata, '{}'::jsonb) ? 'distance_map_matched_m')
     and auth.uid() is not null
     and new.track_url is not distinct from old.track_url then
    new.metadata := coalesce(new.metadata, '{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object(
      'distance_map_matched_m', v_old -> 'distance_map_matched_m',
      'distance_map_matched_track_version', v_old -> 'distance_map_matched_track_version'
    ));
  end if;

  if not (v_old ? 'distance_recomputed_at')
     or coalesce(new.metadata, '{}'::jsonb) ? 'distance_recomputed_at' then
    return new;
  end if;

  new.metadata := coalesce(new.metadata, '{}'::jsonb) || jsonb_strip_nulls(jsonb_build_object(
    'distance_recomputed_at', v_old -> 'distance_recomputed_at',
    'distance_recorded_m', v_old -> 'distance_recorded_m',
    'distance_estimator', v_old -> 'distance_estimator',
    'distance_estimator_pass', v_old -> 'distance_estimator_pass',
    'distance_map_matched_m', v_old -> 'distance_map_matched_m',
    'distance_map_matched_track_version', v_old -> 'distance_map_matched_track_version'
  ));

  new.fastest_5k_s := old.fastest_5k_s;
  new.fastest_10k_s := old.fastest_10k_s;
  new.fastest_half_marathon_s := old.fastest_half_marathon_s;
  new.fastest_marathon_s := old.fastest_marathon_s;

  if jsonb_typeof(v_old -> 'distance_recorded_m') = 'number' then
    v_recorded := (v_old ->> 'distance_recorded_m')::numeric;
    if new.distance_m is distinct from old.distance_m
       and abs(new.distance_m - v_recorded) < 0.5 then
      new.distance_m := old.distance_m;
    end if;
  end if;

  return new;
end;
$$;

revoke execute on function public.runs_keep_distance_recompute() from public, anon, authenticated;

-- ── 3. the worker's read: path and token together ─────────────────────────

create or replace function public.map_match_track_source(p_run_id uuid)
returns table (track_url text, track_version text)
language sql
stable
security definer
set search_path = public
as $$
  select r.track_url, public.runs_track_object_version(r.track_url)
    from runs r
   where r.id = p_run_id;
$$;

revoke execute on function public.map_match_track_source(uuid) from public, anon, authenticated;
grant execute on function public.map_match_track_source(uuid) to service_role;

-- ── 4. the worker's write: refused for any bytes but the stored ones ──────

create or replace function public.record_map_match_result(
  p_run_id uuid,
  p_source_track_url text,
  p_track_version text,
  p_status text,
  p_matched_track_url text,
  p_matched_at timestamptz,
  p_algorithm text,
  p_algorithm_version text,
  p_error_message text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_track_url text;
begin
  -- Lock first: the statements after it read with a fresh snapshot, so a
  -- rewrite whose reset held this row has committed by the time the token
  -- is compared.
  perform 1 from run_matched_tracks where run_id = p_run_id for update;
  if not found then
    return false;
  end if;

  select r.track_url into v_track_url from runs r where r.id = p_run_id;
  if v_track_url is null
     or v_track_url is distinct from p_source_track_url
     or p_track_version is null
     or public.runs_track_object_version(v_track_url) is distinct from p_track_version then
    return false;
  end if;

  update run_matched_tracks
     set status = p_status,
         matched_track_url = p_matched_track_url,
         matched_at = p_matched_at,
         algorithm = p_algorithm,
         algorithm_version = p_algorithm_version,
         error_message = p_error_message
   where run_id = p_run_id
     and source_track_url = p_source_track_url;
  return found;
end;
$$;

revoke execute on function public.record_map_match_result(uuid, text, text, text, text, timestamptz, text, text, text)
  from public, anon, authenticated;
grant execute on function public.record_map_match_result(uuid, text, text, text, text, timestamptz, text, text, text)
  to service_role;

-- ── 5. a map_match job that leaves its run pending runs again ─────────────

create or replace function finish_job(
  job_id bigint,
  result_status text,
  err text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if result_status not in ('done', 'failed', 'cancelled') then
    raise exception 'finish_job: bad result_status %', result_status
      using errcode = '22023';
  end if;

  if result_status = 'done' then
    update jobs j
       set status = 'queued',
           scheduled_at = now(),
           locked_at = null,
           locked_by = null,
           last_error = 'requeued: the run''s track changed while the job ran'
     where j.id = job_id
       and j.kind = 'map_match'
       and j.status = 'running'
       and j.attempts < j.max_attempts
       and exists (
         select 1 from run_matched_tracks m
          where m.run_id = (j.payload ->> 'run_id')::uuid
            and m.status = 'pending'
       );
    if found then
      return;
    end if;
  end if;

  update jobs
  set status = result_status,
      finished_at = now(),
      last_error = err
  where id = job_id;
end;
$$;

revoke execute on function finish_job(bigint, text, text) from public, anon, authenticated;
grant execute on function finish_job(bigint, text, text) to service_role;
