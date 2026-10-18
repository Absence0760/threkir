-- A race listing gets a course (issue #1190; decisions § 2157).
--
-- race_listings.route_id names the route the race is run on, one per edition,
-- since a listing is already one row per race date. The race page shows the
-- course's distance, climb and surface, and hands the climb and surface to
-- the race-to-plan AI description, which had no course to describe (§ 2154).
--
-- Who writes it: the service role only, for now. Listings are written by the
-- provider sweep and admin tooling as service_role, and a runner may edit the
-- listing they submitted while it is unverified. That edit path must not reach
-- route_id: a submitter could otherwise attach any route to a race every
-- visitor reads. force_unverified_listing already reverts is_verified on every
-- non-service-role write, BEFORE INSERT OR UPDATE (the shape
-- 20270704000003 names as the one that holds); it now also drops route_id on
-- such an insert and keeps the stored value on such an update, silently, like
-- the flag beside it. Only a direct write is held to this
-- (pg_trigger_depth() = 1, the guard event_attendees_course_guard uses for the
-- same reason): the ON DELETE SET NULL cascade from a route's owner deleting
-- the route reaches this trigger under the owner's claims, and reverting its
-- null would refuse the delete on the foreign key, while reverting is_verified
-- would unverify a race because someone deleted a route. The
-- verified-organiser claim flow in #1190 is where a client write path will be
-- opened, deliberately. Until then an operator links
-- a course from the SQL editor, in a transaction that sets the service-role
-- claim first: the editor sends no JWT, so a plain update is reverted by the
-- trigger (docs/features/race_calendar.md has the statement).
--
-- Who reads it: nobody reads route_id itself. The public calendar is read
-- through public_race_listings, and the view now carries the course's summary
-- from public_routes, the projection of routes that are public and not
-- moderated away. A listing pointed at a private route, by mistake or because
-- the route was made private after the link, returns no course at all, to
-- anon, to other runners and to the route's owner alike: the course is part of
-- the public race, so it is shown only while the route itself is public. The
-- route's id is not projected either; the summary is all the race page uses.
--
-- The view gains a join, so it is no longer auto-updatable. Nothing writes
-- through it (20270324_001 revoked every write privilege on it), so that only
-- removes a capability nobody holds. Its existing columns keep their names,
-- types and order, as create or replace view requires, and search_race_listings
-- and the photo RPC, which read it, are unchanged.
--
-- Locks: race_listings is a bounded calendar table, not one of the high-volume
-- tables check_migration_online_safety.mjs guards. The nullable column is a
-- catalogue change, the FK's validation reads a column that is null in every
-- row, and the partial covering index is built empty. Replacing the trigger
-- function takes no table lock.

set search_path = public, extensions;

alter table race_listings
  add column route_id uuid references routes (id) on delete set null;

create index race_listings_route_idx
  on race_listings (route_id)
  where route_id is not null;

create or replace function force_unverified_listing()
  returns trigger language plpgsql security invoker
  set search_path = public
as $$
begin
  if pg_trigger_depth() = 1
     and current_setting('role', true) is distinct from 'service_role'
     and (select auth.role()) is distinct from 'service_role' then
    new.is_verified := false;
    if tg_op = 'INSERT' then
      new.route_id := null;
    else
      new.route_id := old.route_id;
    end if;
  end if;
  return new;
end;
$$;

create or replace view public_race_listings as
select
  l.id,
  l.provider,
  l.provider_race_id,
  l.name,
  l.race_date,
  l.distance_m,
  l.location_label,
  l.location_point,
  l.entry_url,
  l.results_url,
  l.is_verified,
  l.created_at,
  l.updated_at,
  c.distance_m as course_distance_m,
  c.elevation_m as course_elevation_m,
  c.surface as course_surface
from race_listings l
left join public_routes c on c.id = l.route_id;

revoke all on public.public_race_listings from public, anon, authenticated;
grant select on public.public_race_listings to anon, authenticated;
