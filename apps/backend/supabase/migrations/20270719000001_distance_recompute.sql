-- Route `distance_recompute`: the CHECK that lets it be enqueued, the dedupe
-- that makes a double tap free, and the owner-only RPC the run detail page's
-- "Recalculate distance" action calls.
--
-- Every recorder used to sum raw fix-to-fix haversine hops, which inflates a
-- run by 15-45% at running pace (docs/features/gps_distance.md § Why it
-- exists). The recorders now run GPS distance estimator spec v1; this job lets
-- the Go worker re-derive an EXISTING run's distance from its stored track
-- with the same estimator, keeping the recorder's original figure in
-- `runs.metadata.distance_recorded_m` (docs/backend/metadata.md).
--
-- `apps/job_worker/internal/worker_dispatch_coverage_test.go` fails a kind
-- this CHECK admits with no dispatch `case`, so this migration and the
-- worker's handler land in the same change.

-- ─────────────────── 1. jobs_kind_chk ───────────────────

-- `drop` + `add ... not valid` with no `validate`, for the reason
-- 20270708000010 records at length (decisions § 1148): `jobs` is on
-- migration_locks.md's guarded list, a same-file VALIDATE scans under the
-- drop's ACCESS EXCLUSIVE anyway, and for a strict WIDEN there is nothing for
-- the scan to find — every existing row was admitted by the narrower CHECK
-- this replaces. A NOT VALID CHECK still binds every new write.
alter table public.jobs
  drop constraint jobs_kind_chk;
alter table public.jobs
  add constraint jobs_kind_chk
  check (
    kind in (
      'map_match', 'token_refresh', 'strava_event', 'photo_process',
      'notification_email', 'lifecycle_email', 'safety_email', 'web_push',
      'weekly_digest', 'native_push', 'lifecycle_drip', 'route_photo_process',
      'club_photo_process', 'safety_sms', 'data_export', 'export_blob_reap',
      'distance_recompute'
    )
  )
  not valid;

-- ─────────────────── 2. jobs_dedupe_distance_recompute ───────────────────

-- Same shape as jobs_dedupe_map_match (20260609_001): while a recompute for a
-- run is queued or running, a second request is a no-op via ON CONFLICT; once
-- it finishes, a fresh one may land. Plain (non-CONCURRENT) build for the
-- reason 20270423000001 gives: the CLI wraps a migration in a transaction, and
-- the predicate matches no existing row, so the build reads the small live
-- set and the write pause is negligible.
create unique index jobs_dedupe_distance_recompute
  on jobs (kind, ((payload->>'run_id')::uuid))
  where kind = 'distance_recompute' and status in ('queued', 'running');

-- ─────────────────── 3. request_distance_recompute ───────────────────

-- SECURITY DEFINER because `jobs` is writable only by the worker's service
-- role. Authorization is the body's job: the caller must be signed in and own
-- the run. A missing run and someone else's run raise the same 42501, so the
-- RPC is not an existence oracle for run ids. A run with no stored track has
-- nothing to recompute from and raises 22000, which the UI renders as its own
-- message. Scheduling is tier-aware like the manual re-match.
create or replace function public.request_distance_recompute(p_run_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
  v_track_url text;
begin
  if auth.uid() is null then
    raise exception 'request_distance_recompute: not authorized' using errcode = '42501';
  end if;

  select user_id, track_url
    into v_user_id, v_track_url
  from runs
  where id = p_run_id;

  if v_user_id is null or v_user_id <> auth.uid() then
    raise exception 'request_distance_recompute: not authorized' using errcode = '42501';
  end if;

  if v_track_url is null or v_track_url = '' then
    raise exception 'request_distance_recompute: run has no track' using errcode = '22000';
  end if;

  insert into jobs (kind, payload, scheduled_at)
  values (
    'distance_recompute',
    jsonb_build_object('run_id', p_run_id, 'user_id', v_user_id),
    job_scheduled_at_for_user(v_user_id)
  )
  on conflict do nothing;
end;
$$;

-- `from public, anon` because neither single-grantee revoke is portable
-- across the images this schema runs on (20270625000001).
revoke execute on function public.request_distance_recompute(uuid) from public, anon;
grant execute on function public.request_distance_recompute(uuid) to authenticated;
