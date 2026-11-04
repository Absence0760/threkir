-- Server-side sweep of route-photo BYTES that no `route_photos` row references
-- (decisions § 2293 amendment). Deleting a route is row-then-client-sweep: the
-- cascade takes the `route_photos` rows and the client then removes the
-- Storage objects. Two cases left the bytes behind with nothing pointing at
-- them, personal data kept invisibly until account deletion:
--   (A) the client sweep never ran or failed (tab closed, offline, crash);
--   (B) a club admin deleted a club route someone else uploaded photos to, and
--       the uploader's folder is not theirs to remove from.
-- The same residue comes from a web upload whose row insert failed and whose
-- cleanup remove also failed, and from a thumbnail the `route_photo_process`
-- worker wrote for a photo deleted while its job was queued.
--
-- Shape, following the export reap (20270708000010, decisions § 1144):
-- SQL decides WHAT is orphaned, the Go worker erases through the Storage API,
-- because a `storage.objects` row delete leaves the bytes on the backend
-- (decisions § 1049). One job kind, two payloads:
--   * `{}` — the nightly backstop: every object in the bucket last written
--     more than 24 hours ago that no row references.
--   * `{"paths": [...]}` — enqueued by the route_photos AFTER DELETE trigger
--     below, so the normal case (a route or photo deleted, client sweep or
--     not) is erased within the worker's poll interval, not the next night.
--
-- Fail-closed gate: nothing is enqueued and the worklist is empty until
-- `private.feature_flags` has `route_photo_orphan_sweep` enabled (absent =
-- off). Enabling it is a pre-deploy checklist item for the CISO / Security
-- Analyst, recorded in docs/compliance/retention.md: this job deletes user
-- bytes, and a predicate bug would delete live photos.

-- ─────────────────── 1. jobs_kind_chk ───────────────────

-- `drop` + `add ... not valid` and deliberately no `validate`: `jobs` is on
-- migration_locks.md's guarded list, a same-file VALIDATE would scan under the
-- ACCESS EXCLUSIVE the drop still holds, and a strict-superset widen can only
-- confirm what the narrower CHECK already enforced (decisions § 1148, the
-- reasoning 20270708000010's header spells out).
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
      'distance_recompute', 'security_email', 'route_photo_orphan_sweep'
    )
  )
  not valid;

-- ─────────────────── 2. lookup index ───────────────────

-- The worklist anti-joins every object in the bucket against
-- `route_photos.storage_path`, and the placeholder probe below looks rows up
-- by `storage_path = ''`. `thumb_512_path` already has its partial index
-- (20270114_001). route_photos is a small, bounded table and is not on the
-- guarded list, so a plain build is a brief write pause, not downtime.
create index if not exists route_photos_storage_path
  on public.route_photos (storage_path);

-- ─────────────────── 3. route_photo_orphan_paths ───────────────────

-- The worklist. An object is referenced, and never returned, when a row names
-- it as `storage_path` or `thumb_512_path`, OR when it is the upload behind a
-- mobile placeholder row: the mobile client inserts the row with
-- `storage_path = ''`, uploads `{owner}/{id}.{ext}`, then PATCHes the path.
-- An upload whose PATCH failed belongs to a row the owner still sees, so it
-- is theirs to delete, not this sweep's; deleting that row orphans it.
--
-- The 24-hour grace (backstop mode only) is measured from the object's LAST
-- write, so a worker outage that delays a thumbnail does not shorten it: the
-- thumb is written seconds before its row is PATCHed whenever it is written.
-- The windows it has to cover are the web upload-then-insert (seconds) and
-- the worker's thumb-upload-then-PATCH (seconds), with the mobile window
-- covered by the placeholder probe instead. A day is orders of magnitude past
-- both and past any clock skew, costs at most one extra day of retention on
-- bytes that would otherwise be kept forever, and lines up with the nightly
-- cadence. An object whose age is unknown (both timestamps null) compares as
-- null and is never returned.
--
-- The grace is a constant, not a parameter, on purpose: a payload or an
-- operator call cannot ask for zero and race an in-flight upload. The paths
-- mode takes none because each path it is handed was referenced by a row that
-- has just been deleted, so it is not an upload awaiting its row.
--
-- `p_limit` is clamped to 1..500 so one call is one bounded batch; the worker
-- loops. Returns nothing while the gate is off, so a job enqueued by hand
-- still erases nothing.
create or replace function public.route_photo_orphan_paths(
  p_paths text[] default null,
  p_limit integer default 100
)
returns setof text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_limit integer := least(greatest(coalesce(p_limit, 100), 1), 500);
begin
  if not coalesce(
    (select f.enabled from private.feature_flags f
      where f.name = 'route_photo_orphan_sweep'),
    false
  ) then
    return;
  end if;

  if p_paths is null then
    return query
    select o.name
      from storage.objects o
     where o.bucket_id = 'route-photos'
       and greatest(o.created_at, o.updated_at) < now() - interval '24 hours'
       and not exists (select 1 from public.route_photos rp where rp.storage_path = o.name)
       and not exists (select 1 from public.route_photos rp where rp.thumb_512_path = o.name)
       and not exists (
         select 1 from public.route_photos rp
          where rp.storage_path = ''
            and o.name like rp.owner_id::text || '/' || rp.id::text || '.%'
       )
     order by o.name
     limit v_limit;
  else
    return query
    select o.name
      from storage.objects o
     where o.bucket_id = 'route-photos'
       and o.name = any (p_paths)
       and not exists (select 1 from public.route_photos rp where rp.storage_path = o.name)
       and not exists (select 1 from public.route_photos rp where rp.thumb_512_path = o.name)
       and not exists (
         select 1 from public.route_photos rp
          where rp.storage_path = ''
            and o.name like rp.owner_id::text || '/' || rp.id::text || '.%'
       )
     order by o.name
     limit v_limit;
  end if;
end;
$$;

revoke execute on function public.route_photo_orphan_paths(text[], integer) from public, anon, authenticated;
grant execute on function public.route_photo_orphan_paths(text[], integer) to service_role;

comment on function public.route_photo_orphan_paths(text[], integer) is
  'Worklist for the route_photo_orphan_sweep job: route-photos objects no '
  'route_photos row references (storage_path, thumb_512_path, or the upload '
  'behind a mobile placeholder row). With p_paths null, only objects last '
  'written over 24 hours ago; with p_paths, those paths. At most 500 per '
  'call. Empty unless private.feature_flags route_photo_orphan_sweep is '
  'enabled. Service role only; decisions 2293.';

-- ─────────────────── 4. nightly enqueue ───────────────────

-- A singleton, for the reason enqueue_export_blob_reap is one: a second queued
-- backstop re-reads the same worklist and erases nothing extra. Only the
-- backstop is deduplicated; a paths job from the trigger is a different
-- worklist and must not be swallowed by a queued backstop, nor block one.
create or replace function public.enqueue_route_photo_orphan_sweep()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not coalesce(
    (select f.enabled from private.feature_flags f
      where f.name = 'route_photo_orphan_sweep'),
    false
  ) then
    return;
  end if;

  insert into public.jobs (kind, payload, max_attempts)
  select 'route_photo_orphan_sweep', '{}'::jsonb, 3
  where not exists (
    select 1 from public.jobs j
     where j.kind = 'route_photo_orphan_sweep'
       and j.payload = '{}'::jsonb
       and j.status in ('queued', 'running')
  );
end;
$$;

revoke execute on function public.enqueue_route_photo_orphan_sweep() from public, anon, authenticated;
grant execute on function public.enqueue_route_photo_orphan_sweep() to service_role;

comment on function public.enqueue_route_photo_orphan_sweep() is
  'Queues the nightly backstop route_photo_orphan_sweep job (empty payload) '
  'when private.feature_flags route_photo_orphan_sweep is enabled. '
  'Singleton per queued/running backstop. Scheduled by pg_cron '
  'enqueue-route-photo-orphan-sweep; service_role may call it by hand. '
  'decisions 2293.';

-- ─────────────────── 5. prompt enqueue on delete ───────────────────

-- Statement-level with a transition table, so a route delete that cascades
-- fifty photos queues ONE job, not fifty. The paths are capped at 1000 per
-- statement (an account deletion cascades every photo the user owns in one
-- statement); anything past the cap is still unreferenced and the backstop
-- erases it. The payload holds `{owner}/{photo}` paths, the same identifiers
-- route_photo_process payloads already carry, and `purge-stale-jobs` drops
-- the row 30 days after it finishes.
create or replace function public.enqueue_route_photo_orphan_sweep_on_delete()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_paths text[];
begin
  if not coalesce(
    (select f.enabled from private.feature_flags f
      where f.name = 'route_photo_orphan_sweep'),
    false
  ) then
    return null;
  end if;

  select array_agg(p order by p)
    into v_paths
    from (
      select g.storage_path as p from gone g where g.storage_path <> ''
      union
      select g.thumb_512_path from gone g
       where g.thumb_512_path is not null and g.thumb_512_path <> ''
    ) s;

  if v_paths is null then
    return null;
  end if;

  insert into public.jobs (kind, payload, max_attempts)
  values (
    'route_photo_orphan_sweep',
    jsonb_build_object('paths', to_jsonb(v_paths[1:1000])),
    3
  );
  return null;
end;
$$;

revoke execute on function public.enqueue_route_photo_orphan_sweep_on_delete() from public, anon, authenticated;

create trigger route_photos_enqueue_orphan_sweep
  after delete on public.route_photos
  referencing old table as gone
  for each statement execute function public.enqueue_route_photo_orphan_sweep_on_delete();

-- ─────────────────── 6. schedule ───────────────────

-- Daily, in the quiet window the other retention jobs use. `cron.schedule`
-- is idempotent on name. The job is enqueued only while the gate is on, so
-- the schedule is safe to create before the sign-off.
select cron.schedule(
  'enqueue-route-photo-orphan-sweep',
  '43 4 * * *',
  $$select public.enqueue_route_photo_orphan_sweep()$$
);
