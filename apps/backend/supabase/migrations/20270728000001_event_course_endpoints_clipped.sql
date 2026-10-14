-- A course's published start and finish points are the route OWNER's
-- privacy-clipped geometry, kept current with the route (decisions § 1848).
--
-- 20270727000001 copied the raw last waypoint of the course's route onto
-- event_courses.finish_lat / finish_lng. event_courses is readable by everyone
-- who can see the event, anon included, and an organiser may attach any route
-- they can see — including someone else's public route. Its raw finish could
-- sit inside that owner's privacy zone, which no other non-owner surface ever
-- serves (decisions § 33). And the copy ran only when route_id changed, so an
-- edit to the route's waypoints left a stale finish behind.
--
-- Now:
--   * Both endpoints come from clip_track_for_user(route owner, waypoints) —
--     the zone walk clip_route_for_viewer delegates to for a non-owner. An
--     endpoint is published only if it survives the clip unchanged; one the
--     clip trimmed is NULL, never the nearest surviving point, which would
--     move the line. The rule does not depend on who saved the course: the
--     row is a non-owner surface whoever wrote it.
--   * start_lat / start_lng are new, from the first waypoint by the same rule,
--     so the late-start far-from-start check (decisions § 1845) has a start
--     point that is not the clipped route.
--   * The endpoints are recomputed on every course write, when the route's
--     waypoints change, and when the owner's privacy zones change. A client
--     can no longer write them directly: whatever it sends is recomputed.
--   * Every existing course with a route is recomputed here.
--
-- Locks: event_courses is a bounded config table (one row per course), so the
-- two inline CHECKs and the backfill are cheap. CREATE TRIGGER on routes and
-- user_settings takes SHARE ROW EXCLUSIVE for a catalogue-only change
-- (docs/backend/migration_locks.md § Lock reference).

set search_path = public;

alter table public.event_courses
  add column start_lat double precision
    constraint event_courses_start_lat_check
      check (start_lat is null or start_lat between -90 and 90),
  add column start_lng double precision
    constraint event_courses_start_lng_check
      check (start_lng is null or start_lng between -180 and 180),
  add constraint event_courses_start_pair_check
    check ((start_lat is null) = (start_lng is null));

create or replace function private.event_course_endpoints(p_route_id uuid)
returns table (
  start_lat double precision,
  start_lng double precision,
  finish_lat double precision,
  finish_lng double precision
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_owner uuid;
  v_raw jsonb;
  v_clipped jsonb;
  v_n int;
  v_first jsonb;
  v_last jsonb;
begin
  select r.user_id, r.waypoints into v_owner, v_raw
  from routes r
  where r.id = p_route_id;

  if v_owner is null
     or jsonb_typeof(v_raw) is distinct from 'array'
     or jsonb_array_length(v_raw) = 0
  then
    return query select null::float8, null::float8, null::float8, null::float8;
    return;
  end if;

  v_clipped := clip_track_for_user(v_owner, v_raw);
  v_n := jsonb_array_length(v_clipped);

  if v_n > 0 and v_clipped -> 0 = v_raw -> 0 then
    v_first := v_raw -> 0;
  end if;
  if v_n > 0 and v_clipped -> (v_n - 1) = v_raw -> (jsonb_array_length(v_raw) - 1) then
    v_last := v_raw -> (jsonb_array_length(v_raw) - 1);
  end if;

  v_first := case
    when jsonb_typeof(v_first -> 'lat') = 'number' and jsonb_typeof(v_first -> 'lng') = 'number'
      then v_first
  end;
  v_last := case
    when jsonb_typeof(v_last -> 'lat') = 'number' and jsonb_typeof(v_last -> 'lng') = 'number'
      then v_last
  end;
  if v_first is not null
     and not ((v_first ->> 'lat')::float8 between -90 and 90
              and (v_first ->> 'lng')::float8 between -180 and 180)
  then
    v_first := null;
  end if;
  if v_last is not null
     and not ((v_last ->> 'lat')::float8 between -90 and 90
              and (v_last ->> 'lng')::float8 between -180 and 180)
  then
    v_last := null;
  end if;

  return query select
    (v_first ->> 'lat')::float8,
    (v_first ->> 'lng')::float8,
    (v_last ->> 'lat')::float8,
    (v_last ->> 'lng')::float8;
end;
$$;

revoke execute on function private.event_course_endpoints(uuid)
  from public, anon, authenticated;

-- Attaching a route publishes its endpoints to everyone who can see the event,
-- so a client may still attach only a route it can see itself. The check runs
-- only when the route changes: a rename of a course whose route has since gone
-- private must not be refused for a choice made earlier.
create or replace function public.event_courses_set_endpoints()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ends record;
begin
  if new.route_id is not null
     and auth.uid() is not null
     and (tg_op = 'INSERT' or new.route_id is distinct from old.route_id)
     and not private.is_route_visible_to(new.route_id, auth.uid())
  then
    raise exception 'event_course_route_not_visible: route % is not visible to you', new.route_id
      using errcode = 'insufficient_privilege';
  end if;

  if new.route_id is null then
    new.start_lat := null;
    new.start_lng := null;
    new.finish_lat := null;
    new.finish_lng := null;
    return new;
  end if;

  select * into v_ends from private.event_course_endpoints(new.route_id);
  new.start_lat := v_ends.start_lat;
  new.start_lng := v_ends.start_lng;
  new.finish_lat := v_ends.finish_lat;
  new.finish_lng := v_ends.finish_lng;
  return new;
end;
$$;

drop trigger event_courses_set_finish_trg on public.event_courses;
drop function public.event_courses_set_finish();

create trigger event_courses_set_endpoints_trg
  before insert or update on public.event_courses
  for each row execute function public.event_courses_set_endpoints();

-- The refresh writes the computed values itself rather than a no-op
-- `set route_id = route_id`, so it reads as what it does; the BEFORE trigger
-- above recomputes the same values on the way in.
create or replace function private.refresh_event_course_endpoints(p_route_ids uuid[])
returns void
language sql
security definer
set search_path = public
as $$
  update event_courses c
     set (start_lat, start_lng, finish_lat, finish_lng) = (
       select e.start_lat, e.start_lng, e.finish_lat, e.finish_lng
       from private.event_course_endpoints(c.route_id) e
     )
   where c.route_id = any (p_route_ids);
$$;

revoke execute on function private.refresh_event_course_endpoints(uuid[])
  from public, anon, authenticated;

create or replace function public.routes_refresh_event_course_endpoints()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform private.refresh_event_course_endpoints(array[new.id]);
  return null;
end;
$$;

create trigger routes_refresh_event_course_endpoints_trg
  after update of waypoints on public.routes
  for each row
  when (old.waypoints is distinct from new.waypoints)
  execute function public.routes_refresh_event_course_endpoints();

create or replace function public.user_settings_refresh_event_course_endpoints()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform private.refresh_event_course_endpoints(array(
    select r.id from routes r
    where r.user_id = new.user_id
      and exists (select 1 from event_courses c where c.route_id = r.id)
  ));
  return null;
end;
$$;

create trigger user_settings_refresh_event_course_endpoints_ins
  after insert on public.user_settings
  for each row
  when (new.prefs ? 'privacy_zones')
  execute function public.user_settings_refresh_event_course_endpoints();

create trigger user_settings_refresh_event_course_endpoints_upd
  after update of prefs on public.user_settings
  for each row
  when (old.prefs -> 'privacy_zones' is distinct from new.prefs -> 'privacy_zones')
  execute function public.user_settings_refresh_event_course_endpoints();

-- Backfill: every course published under the raw-copy rule.
select private.refresh_event_course_endpoints(array(
  select distinct c.route_id from public.event_courses c where c.route_id is not null
));
