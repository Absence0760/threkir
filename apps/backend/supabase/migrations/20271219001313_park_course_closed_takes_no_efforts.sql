-- A closed park course takes no new effort (issue #1313, owner decision of
-- 2026-11-10, decisions § 2465). `seasonal` keeps timing, and the efforts a
-- course already holds stay on its boards.
--
-- One rule, `private.global_segment_course_closed` (the segment's park course
-- has `status = 'closed'`), applied at every path that writes an effort:
--
--   1. `global_segments_in_bbox`, the candidate lookup both scorers use (the
--      segment-match Edge Function and the web owner-on-view fallback), leaves
--      a closed course out. Neither scorer then matches it, and neither touches
--      the effort a run already holds on it: the server deletes only among the
--      candidates it was given, the web fallback only among those it scored.
--   2. `record_segment_match` (20271122002402's body) neither inserts, updates
--      nor deletes an effort on a closed course, whatever candidates and
--      efforts its caller sends, so a processor deployed before this migration
--      cannot write one either.
--   3. The run owner's insert policy (the RLS the web fallback writes through,
--      and the path a client skipping the rule would take) refuses a closed
--      course's segment. The helper is SECURITY DEFINER so the policy sees the
--      course even where park_courses' own read policy hides it (a course in
--      an inactive park). The owner's delete policy is unchanged: a runner can
--      still rescind their own effort, and a run delete still cascades.
--
-- The status is read when the effort would be written. Nothing records when a
-- course was closed, so a run recorded during a closure and re-scored after
-- the course reopens (a backfill for redrawn geometry, a matcher-version
-- re-match) is timed then.
--
-- Locks (docs/backend/migration_locks.md): one function created and two
-- replaced in place, no table lock. One ALTER POLICY on global_segment_efforts: catalogue-only, a
-- brief ACCESS EXCLUSIVE held to this file's commit, no scan, and the only
-- table lock in the file. No rows written.

-- ─── 0. the rule ──────────────────────────────────────────────────────────

create or replace function private.global_segment_course_closed(p_segment_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.park_courses pc
     where pc.global_segment_id = p_segment_id
       and pc.status = 'closed'
  );
$$;

revoke execute on function private.global_segment_course_closed(uuid) from public, anon;
grant execute on function private.global_segment_course_closed(uuid) to authenticated, service_role;

-- ─── 1. the candidate lookup ──────────────────────────────────────────────

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
     and not private.global_segment_course_closed(gs.id)
   order by gs.id
   limit least(greatest(coalesce(p_limit, 1000), 1), 2000);
end;
$$;

revoke execute on function public.global_segments_in_bbox(double precision, double precision, double precision, double precision, double precision, integer)
  from public, anon;
grant execute on function public.global_segments_in_bbox(double precision, double precision, double precision, double precision, double precision, integer)
  to authenticated, service_role;

-- ─── 2. record_segment_match ──────────────────────────────────────────────

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
     )
     and not private.global_segment_course_closed(e.global_segment_id);

  insert into public.global_segment_efforts
    (global_segment_id, run_id, user_id, time_seconds, started_at, matched_by)
  select gs.id, p_run_id, v_user_id, (m ->> 'time_seconds')::numeric, (m ->> 'started_at')::timestamptz,
         coalesce(m ->> 'matched_by', 'zone')
    from jsonb_array_elements(p_efforts) m
    join public.global_segments gs
      on gs.id = (m ->> 'global_segment_id')::uuid
     and gs.is_active = true
   where gs.id = any (coalesce(p_candidates, '{}'::uuid[]))
     and not private.global_segment_course_closed(gs.id)
  on conflict (global_segment_id, run_id) do update
     set time_seconds = excluded.time_seconds,
         started_at = excluded.started_at,
         matched_by = excluded.matched_by;

  return 'recorded';
end;
$$;

revoke execute on function public.record_segment_match(uuid, text, double precision, double precision, double precision, double precision, uuid[], jsonb)
  from public, anon, authenticated;
grant execute on function public.record_segment_match(uuid, text, double precision, double precision, double precision, double precision, uuid[], jsonb)
  to service_role;

-- ─── 3. the run owner's insert policy ─────────────────────────────────────

alter policy "run owner inserts catalogue efforts on their runs" on public.global_segment_efforts
  with check (
    (select auth.uid()) = user_id
    and exists (
      select 1 from public.runs
       where runs.id = global_segment_efforts.run_id
         and runs.user_id = (select auth.uid())
    )
    and exists (
      select 1 from public.global_segments gs
       where gs.id = global_segment_efforts.global_segment_id
         and gs.is_active = true
    )
    and not private.global_segment_course_closed(global_segment_efforts.global_segment_id)
  );
