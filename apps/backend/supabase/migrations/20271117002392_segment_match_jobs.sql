-- Server-side catalogue segment matching (issue #1313 Phase 1, decisions
-- § 2392).
--
-- Until now a catalogue effort (global_segment_efforts) was written only by
-- the web run-detail page, on the owner's view, after a 500-row fetch of the
-- whole catalogue. A run recorded on a phone and never opened on the web was
-- never scored, so a park course board missed every phone-only runner. This
-- moves the scoring to the server:
--
--   1. `segment_match` on the jobs queue. Two payloads:
--        * `{run_id}` — score one run against every catalogue segment near its
--          track. Enqueued by a trigger on runs when track_url is set (a
--          recording, an import), and by a trigger on storage.objects when the
--          bytes behind a track_url are uploaded or rewritten (a backup
--          restore, a re-save, an upload that lands after its row).
--        * `{segment_id, after_run_id?}` — one batch of the backfill that
--          scores existing runs when a segment or course launches. Each batch
--          enqueues the next, keyset by run id, so no single job or statement
--          walks the whole runs table (migration_locks.md § Large backfills).
--   2. The Go job_worker claims the job and hands the payload to the
--      `segment-match` Edge Function, which runs the canonical TS matcher
--      (apps/web/src/lib/segments/segments.ts, bundled into the function by
--      scripts/gen_edge_segment_matcher.mjs) and writes through
--      record_segment_match below. No third language port.
--   3. `global_segments_in_bbox` — the candidate lookup, a GiST expression
--      index over each segment's extent. It replaces the 500-row catalogue
--      fetch on the server and on the web fallback alike.
--   4. `run_track_extents` — the extent of each scored track, service-role
--      only, so a backfill downloads only the tracks that can reach the new
--      segment once a run has been scored once.
--
-- The web owner-on-view scorer stays as a fallback for now and keeps its own
-- owner-insert RLS (20270411_001); removing it, and with it the client write
-- path, is the follow-up once the job has run in prod.
--
-- Privacy: an effort row holds a time and a start instant, never geometry.
-- The server reads the owner's stored track (plus the smoothed sidecar when
-- the run names it), which is exactly the line the owner-on-view path scores,
-- and the efforts it writes are read through the unchanged visibility rule
-- (`private.is_run_visible_to` on the table, plus the block graph in the
-- board RPCs). run_track_extents is location-derived and no client role holds
-- any grant on it.
--
-- Locks (docs/backend/migration_locks.md): the jobs_kind_chk widen is `drop` +
-- `add ... not valid` with no same-file validate (§ 1148, as 20271106000020).
-- jobs_dedupe_segment_match is a plain partial build for the reason
-- 20270719000001 gives: its predicate matches no existing row. The GiST index
-- is on global_segments, a small curated table. CREATE TRIGGER takes SHARE ROW
-- EXCLUSIVE on runs and storage.objects for the instant of the change. No
-- backfill runs here: existing runs are scored by enqueue_segment_backfill,
-- one bounded batch per job.

-- ─────────────────── 1. jobs_kind_chk ───────────────────

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
      'distance_recompute', 'security_email', 'route_photo_orphan_sweep',
      'segment_match'
    )
  )
  not valid;

-- ─────────────────── 2. jobs_dedupe_segment_match ───────────────────

-- One QUEUED per-run job at a time, not one queued-or-running: a track
-- rewritten while its job runs must still get a job of its own, or the
-- dedupe would swallow the enqueue and leave the efforts describing the old
-- bytes. Two jobs for one run can then overlap; record_segment_match refuses
-- the one whose bytes are no longer stored, and the write is idempotent.
create unique index jobs_dedupe_segment_match
  on jobs (kind, ((payload->>'run_id')::uuid))
  where kind = 'segment_match' and status = 'queued' and payload ? 'run_id';

-- ─────────────────── 3. extents and the candidate lookup ───────────────────

-- The lat/lng extent of a stored polyline as a box (x = lng, y = lat). Lat and
-- lng are read as JSON numbers or numeric strings, the two shapes the web
-- reader's `Number(w.lat)` accepts. An element that is not an object with
-- numeric, in-range lat and lng is skipped
-- rather than raised, so one malformed catalogue row can never fail an index
-- build or a write; null when no element qualifies. A polyline crossing the
-- antimeridian gets a box spanning the globe, which over-admits (the matcher
-- rejects it) and never under-admits.
create or replace function private.waypoints_box(p_waypoints jsonb)
returns box
language sql
immutable
parallel safe
set search_path = pg_catalog
as $$
  select case
           when count(*) = 0 then null
           else box(point(min(p.lng), min(p.lat)), point(max(p.lng), max(p.lat)))
         end
    from (
      select
        case
          when jsonb_typeof(w -> 'lat') = 'number'
            or (w ->> 'lat') ~ '^\s*-?[0-9]+(\.[0-9]+)?\s*$'
            then (w ->> 'lat')::double precision
        end as lat,
        case
          when jsonb_typeof(w -> 'lng') = 'number'
            or (w ->> 'lng') ~ '^\s*-?[0-9]+(\.[0-9]+)?\s*$'
            then (w ->> 'lng')::double precision
        end as lng
        from jsonb_array_elements(
               case when jsonb_typeof(p_waypoints) = 'array' then p_waypoints else '[]'::jsonb end
             ) w
       where jsonb_typeof(w) = 'object'
    ) p
   where p.lat between -90 and 90
     and p.lng between -180 and 180;
$$;

-- The extent index below evaluates this on every write to global_segments, and
-- Postgres checks EXECUTE on an index expression as the writing role, so the
-- roles that may write the catalogue (an admin's `authenticated` session, the
-- service role) hold it. A pure function of its argument; nothing to protect.
revoke execute on function private.waypoints_box(jsonb) from public, anon;
grant execute on function private.waypoints_box(jsonb) to authenticated, service_role;

-- `box` grown by `p_metres` on every side, with the degree conversions taken
-- on the safe side: 110 574 m per degree (below the 111 195 the matcher's
-- haversine sphere uses) and the longitude pad divided by the cosine of the
-- box's most poleward latitude. Past a degree of longitude pad, or at a pole,
-- the box spans every longitude. Mirrors CONSERVATIVE_METRES_PER_DEG in
-- segments.ts, which pads the same way for the same reason.
create or replace function private.pad_box(p_box box, p_metres double precision)
returns box
language sql
immutable
parallel safe
set search_path = pg_catalog
as $$
  with b as (
    select (p_box[0])[0] as x1, (p_box[0])[1] as y1,
           (p_box[1])[0] as x2, (p_box[1])[1] as y2,
           greatest(p_metres, 0) / 110574.0 as pad_lat
  ), c as (
    select b.*,
           least(b.x1, b.x2) as min_lng, greatest(b.x1, b.x2) as max_lng,
           greatest(least(b.y1, b.y2) - b.pad_lat, -90) as min_lat,
           least(greatest(b.y1, b.y2) + b.pad_lat, 90) as max_lat
      from b
  ), d as (
    select c.*,
           cos(radians(greatest(abs(c.min_lat), abs(c.max_lat)))) as cos_lat
      from c
  )
  select case
           when d.cos_lat <= 1e-9 or d.pad_lat / d.cos_lat >= 1 then
             box(point(-180, d.min_lat), point(180, d.max_lat))
           else
             box(point(greatest(d.min_lng - d.pad_lat / d.cos_lat, -180), d.min_lat),
                 point(least(d.max_lng + d.pad_lat / d.cos_lat, 180), d.max_lat))
         end
    from d;
$$;

revoke execute on function private.pad_box(box, double precision) from public, anon, authenticated;

create index if not exists global_segments_extent
  on public.global_segments using gist (private.waypoints_box(waypoints))
  where is_active = true;

-- Active catalogue segments whose extent overlaps the given lat/lng box grown
-- by `p_pad_m`. The candidate set for scoring one track: any segment the
-- matcher could time has its start and end within the match tolerance of the
-- track, so its extent overlaps the track's extent padded by that tolerance;
-- the default pad (50 m) is above the matcher's 35 m. SECURITY DEFINER only so
-- the expression index can be used without granting the private helpers; the
-- body applies the same `is_active` rule as the table's world-readable policy.
-- `p_limit` is clamped to 1..2000 and the order is stable (id), so a caller
-- that hits the cap reads the same set every time.
create or replace function public.global_segments_in_bbox(
  p_min_lat double precision,
  p_min_lng double precision,
  p_max_lat double precision,
  p_max_lng double precision,
  p_pad_m double precision default 50,
  p_limit integer default 1000
)
returns setof public.global_segments
language plpgsql
stable
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_box box;
begin
  if p_min_lat is null or p_min_lng is null or p_max_lat is null or p_max_lng is null
     or p_min_lat = 'NaN'::double precision or p_max_lat = 'NaN'::double precision
     or p_min_lng = 'NaN'::double precision or p_max_lng = 'NaN'::double precision
     or p_min_lat < -90 or p_max_lat > 90 or p_min_lng < -180 or p_max_lng > 180
     or p_min_lat > p_max_lat or p_min_lng > p_max_lng then
    raise exception 'global_segments_in_bbox: invalid bounds' using errcode = '22023';
  end if;
  if p_pad_m is null or p_pad_m = 'NaN'::double precision or p_pad_m < 0 or p_pad_m > 5000 then
    raise exception 'global_segments_in_bbox: p_pad_m must be 0..5000' using errcode = '22023';
  end if;

  v_box := private.pad_box(box(point(p_min_lng, p_min_lat), point(p_max_lng, p_max_lat)), p_pad_m);

  return query
  select gs.*
    from public.global_segments gs
   where gs.is_active = true
     and private.waypoints_box(gs.waypoints) && v_box
   order by gs.id
   limit least(greatest(coalesce(p_limit, 1000), 1), 2000);
end;
$$;

revoke execute on function public.global_segments_in_bbox(double precision, double precision, double precision, double precision, double precision, integer)
  from public, anon;
grant execute on function public.global_segments_in_bbox(double precision, double precision, double precision, double precision, double precision, integer)
  to authenticated, service_role;

-- ─────────────────── 4. run_track_extents ───────────────────

-- The extent of a run's stored track (its line positions, the smoothed fix
-- where the track carries one) as of the bytes `track_version` names. Written
-- by record_segment_match each time a run is scored; read only by
-- segment_backfill_runs. Location-derived, so service-role only: RLS on, no
-- policy, no client grant. It cascades away with the run, and so with the
-- account. Not exported: it is derived from the track, which the export
-- carries in full.
create table public.run_track_extents (
  run_id        uuid primary key references public.runs(id) on delete cascade,
  track_version text not null check (length(track_version) between 1 and 200),
  min_lat       double precision not null check (min_lat between -90 and 90),
  min_lng       double precision not null check (min_lng between -180 and 180),
  max_lat       double precision not null check (max_lat between -90 and 90),
  max_lng       double precision not null check (max_lng between -180 and 180),
  scored_at     timestamptz not null default now(),
  check (min_lat <= max_lat and min_lng <= max_lng)
);

alter table public.run_track_extents enable row level security;
revoke all on public.run_track_extents from anon, authenticated;
grant select, insert, update, delete on public.run_track_extents to service_role;

create index run_track_extents_box
  on public.run_track_extents
  using gist (box(point(min_lng, min_lat), point(max_lng, max_lat)));

-- ─────────────────── 5. the processor's read and write ───────────────────

-- What the processor needs to fetch a run's track: the owner, the path, the
-- token of the bytes behind it (runs_track_object_version, 20270719000020) and
-- the metadata that names a smoothed sidecar. No row for a deleted run.
create or replace function public.segment_match_run_source(p_run_id uuid)
returns table (user_id uuid, track_url text, track_version text, metadata jsonb)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select r.user_id, r.track_url, public.runs_track_object_version(r.track_url), r.metadata
    from public.runs r
   where r.id = p_run_id;
$$;

revoke execute on function public.segment_match_run_source(uuid) from public, anon, authenticated;
grant execute on function public.segment_match_run_source(uuid) to service_role;

-- Record one scoring pass. `p_candidates` is every segment the pass actually
-- scored (a course whose checkpoints could not be read is not among them);
-- `p_efforts` is `[{global_segment_id, time_seconds, started_at}]`, a subset
-- of the candidates. For each candidate the stored effort then says what the
-- matcher said about these bytes: a match is inserted or corrected, and an
-- effort the run no longer earns (its track was rewritten) is removed. A
-- segment outside the candidates is never touched.
--
-- Refused, returning 'stale', when the bytes behind the run's track_url are no
-- longer the ones `p_track_version` names: the processor then reports a
-- transient failure and the job runs again against the stored bytes. The run
-- row is locked FOR SHARE for the statement's length so a track_url change
-- cannot commit between the comparison and the write. 'missing' when the run
-- is gone. The owner is always read from the run, never taken from the caller.
create or replace function public.record_segment_match(
  p_run_id uuid,
  p_track_version text,
  p_min_lat double precision,
  p_min_lng double precision,
  p_max_lat double precision,
  p_max_lng double precision,
  p_candidates uuid[],
  p_efforts jsonb
)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid;
  v_track_url text;
begin
  if p_efforts is null or jsonb_typeof(p_efforts) <> 'array' then
    raise exception 'record_segment_match: p_efforts must be an array' using errcode = '22023';
  end if;

  select r.user_id, r.track_url into v_user_id, v_track_url
    from public.runs r
   where r.id = p_run_id
   for share;
  if not found then
    return 'missing';
  end if;

  if v_track_url is null
     or p_track_version is null
     or public.runs_track_object_version(v_track_url) is distinct from p_track_version then
    return 'stale';
  end if;

  insert into public.run_track_extents (run_id, track_version, min_lat, min_lng, max_lat, max_lng, scored_at)
  values (p_run_id, p_track_version, p_min_lat, p_min_lng, p_max_lat, p_max_lng, now())
  on conflict (run_id) do update
     set track_version = excluded.track_version,
         min_lat = excluded.min_lat,
         min_lng = excluded.min_lng,
         max_lat = excluded.max_lat,
         max_lng = excluded.max_lng,
         scored_at = excluded.scored_at;

  delete from public.global_segment_efforts e
   where e.run_id = p_run_id
     and e.global_segment_id = any (coalesce(p_candidates, '{}'::uuid[]))
     and not exists (
       select 1 from jsonb_array_elements(p_efforts) m
        where m ->> 'global_segment_id' = e.global_segment_id::text
     );

  insert into public.global_segment_efforts (global_segment_id, run_id, user_id, time_seconds, started_at)
  select gs.id, p_run_id, v_user_id, (m ->> 'time_seconds')::numeric, (m ->> 'started_at')::timestamptz
    from jsonb_array_elements(p_efforts) m
    join public.global_segments gs
      on gs.id = (m ->> 'global_segment_id')::uuid
     and gs.is_active = true
   where gs.id = any (coalesce(p_candidates, '{}'::uuid[]))
  on conflict (global_segment_id, run_id) do update
     set time_seconds = excluded.time_seconds,
         started_at = excluded.started_at;

  return 'recorded';
end;
$$;

revoke execute on function public.record_segment_match(uuid, text, double precision, double precision, double precision, double precision, uuid[], jsonb)
  from public, anon, authenticated;
grant execute on function public.record_segment_match(uuid, text, double precision, double precision, double precision, double precision, uuid[], jsonb)
  to service_role;

-- ─────────────────── 6. enqueue on a new track ───────────────────

-- A run row that gains a track. The enqueue is auxiliary to the run write, so
-- a failure here is logged and never fails the user's save.
create or replace function public.runs_enqueue_segment_match()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.track_url is null or new.track_url = '' then
    return null;
  end if;
  if tg_op = 'UPDATE' and new.track_url is not distinct from old.track_url then
    return null;
  end if;

  begin
    insert into jobs (kind, payload, scheduled_at)
    values (
      'segment_match',
      jsonb_build_object('run_id', new.id),
      job_scheduled_at_for_user(new.user_id)
    )
    on conflict do nothing;
  exception when others then
    raise warning 'runs_enqueue_segment_match: run % not queued: % (%)', new.id, sqlerrm, sqlstate;
  end;
  return null;
end;
$$;

revoke execute on function public.runs_enqueue_segment_match() from public, anon, authenticated;

drop trigger if exists runs_enqueue_segment_match on public.runs;
create trigger runs_enqueue_segment_match
  after insert or update of track_url on public.runs
  for each row execute function public.runs_enqueue_segment_match();

-- The bytes behind a run's track_url uploaded or replaced: the first upload
-- of a run whose row was written first, or a rewrite in place (the path never
-- changes, 20260621_001). Same path parse and version comparison as
-- runs_track_object_rewritten (20270719000020), which stays as it is.
create or replace function public.runs_track_object_enqueue_segment_match()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
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

  begin
    select r.user_id into v_user_id
      from runs r
     where r.id = v_run_id
       and r.track_url = new.name;
    if not found then
      return null;
    end if;

    insert into jobs (kind, payload, scheduled_at)
    values (
      'segment_match',
      jsonb_build_object('run_id', v_run_id),
      job_scheduled_at_for_user(v_user_id)
    )
    on conflict do nothing;
  exception when others then
    raise warning 'runs_track_object_enqueue_segment_match: run % not queued: % (%)',
      v_run_id, sqlerrm, sqlstate;
  end;
  return null;
end;
$$;

revoke execute on function public.runs_track_object_enqueue_segment_match() from public, anon, authenticated;

drop trigger if exists runs_track_object_enqueue_segment_match on storage.objects;
create trigger runs_track_object_enqueue_segment_match
  after insert or update on storage.objects
  for each row
  when (new.bucket_id = 'runs')
  execute function public.runs_track_object_enqueue_segment_match();

-- ─────────────────── 7. the launch backfill ───────────────────

-- Start (or continue) scoring existing runs against one catalogue segment. An
-- admin or the service role only: a signed-in non-admin gets 42501, anon has
-- no EXECUTE. Without `p_after_run_id` it is a start, and a start while a
-- backfill for the segment is already queued or running returns that job's id
-- rather than queueing a second walk. With it, it is the continuation the
-- processor queues after each batch. An unknown or pulled segment is 22023.
create or replace function public.enqueue_segment_backfill(
  p_segment_id uuid,
  p_after_run_id uuid default null
)
returns bigint
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_caller uuid := auth.uid();
  v_job bigint;
begin
  if v_caller is not null and not private.is_admin(v_caller) then
    raise exception 'enqueue_segment_backfill: admins only' using errcode = '42501';
  end if;
  if not exists (select 1 from global_segments gs where gs.id = p_segment_id and gs.is_active) then
    raise exception 'enqueue_segment_backfill: no active segment %', p_segment_id using errcode = '22023';
  end if;

  if p_after_run_id is null then
    select j.id into v_job
      from jobs j
     where j.kind = 'segment_match'
       and j.status in ('queued', 'running')
       and j.payload ->> 'segment_id' = p_segment_id::text
     order by j.id
     limit 1;
    if found then
      return v_job;
    end if;
  end if;

  insert into jobs (kind, payload)
  values (
    'segment_match',
    jsonb_strip_nulls(jsonb_build_object('segment_id', p_segment_id, 'after_run_id', p_after_run_id))
  )
  returning id into v_job;
  return v_job;
end;
$$;

revoke execute on function public.enqueue_segment_backfill(uuid, uuid) from public, anon;
grant execute on function public.enqueue_segment_backfill(uuid, uuid) to authenticated, service_role;

-- The next batch of a backfill: runs with a stored track, after
-- `p_after_run_id` in id order, that could hold the segment. A run already
-- scored once is admitted only when its stored extent overlaps the segment's
-- extent padded by 50 m; a run never scored has no extent yet and is admitted
-- so its track is read once. A run whose recorded distance is under half the
-- segment's length is skipped: the matcher needs the covered distance within
-- 25 % of the segment's, and no estimator in the tree halves a distance.
-- `p_limit` is clamped to 1..100.
create or replace function public.segment_backfill_runs(
  p_segment_id uuid,
  p_after_run_id uuid default null,
  p_limit integer default 25
)
returns table (run_id uuid)
language plpgsql
stable
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_box box;
  v_distance numeric;
begin
  select private.pad_box(private.waypoints_box(gs.waypoints), 50), gs.distance_m
    into v_box, v_distance
    from global_segments gs
   where gs.id = p_segment_id and gs.is_active;
  if v_box is null then
    return;
  end if;

  return query
  select r.id
    from runs r
    left join run_track_extents x on x.run_id = r.id
   where r.track_url is not null
     and r.track_url <> ''
     and r.id > coalesce(p_after_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
     and r.distance_m >= v_distance * 0.5
     and (x.run_id is null
          or box(point(x.min_lng, x.min_lat), point(x.max_lng, x.max_lat)) && v_box)
   order by r.id
   limit least(greatest(coalesce(p_limit, 25), 1), 100);
end;
$$;

revoke execute on function public.segment_backfill_runs(uuid, uuid, integer) from public, anon, authenticated;
grant execute on function public.segment_backfill_runs(uuid, uuid, integer) to service_role;
