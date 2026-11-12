-- The race page draws its course (issue #1190's course-map slice, #1270's
-- "Preview in 3D" on /races/[id]; decisions § 2253).
--
-- 20270924000002 gave a listing a course and left the route's id out of
-- public_race_listings: the race page needed only the summary, and the course
-- was to be shown only while the route itself is public. Drawing the course
-- needs the id, to read the route's line through the same privacy-clipped path
-- every other public route page uses (public_routes + clip_route_for_viewer).
--
-- The id is read from the same public_routes join that already carries the
-- summary, so it is gated exactly as the summary is: a listing linked to a
-- private or shadow-hidden route returns a null course_route_id, to anon, to
-- other runners and to the route's owner alike, and a deleted route has
-- already nulled race_listings.route_id. An id exposed here names a route
-- anyone can already open at /routes/<id>, so nothing new is readable: the
-- line still comes only from clip_route_for_viewer, never from this view.
--
-- The column is appended, so the existing columns keep their names, types and
-- order, as create or replace view requires; search_race_listings and the
-- photo RPC name their columns and are unchanged. The view stays a definer
-- view (it reads public_routes as its owner, which is what applies the public
-- filter), and its grants are restated: select only, as 20270324_001 left it.
--
-- Locks: replacing a view's definition takes an ACCESS EXCLUSIVE lock on the
-- view alone, for the catalogue update; no table is read or rewritten.

set search_path = public, extensions;

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
  c.surface as course_surface,
  c.id as course_route_id
from race_listings l
left join public_routes c on c.id = l.route_id;

revoke all on public.public_race_listings from public, anon, authenticated;
grant select on public.public_race_listings to anon, authenticated;
