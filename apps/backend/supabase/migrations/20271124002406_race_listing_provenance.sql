-- A race listing's organiser badge follows the club's verification at read
-- time (issue #1190 provenance labels; decisions § 2406).
--
-- claim_race_listing (20271114002381) stores organiser_club_id and sets
-- is_verified = true on the listing. Both are stored, so revoking the club's
-- badge, or the club going private or being auto-hidden by the report flow,
-- left the listing reading as verified and organiser-backed for ever. The
-- issue's trust model is that revoking a club removes the badge from
-- everything at once, and content rows already derive it
-- (private.is_official_publisher, 20271021000030). This view does the same
-- for listings:
--
--   * organiser_is_official (new, trailing): the claiming club is verified,
--     public and not shadow-hidden right now. It is what the provenance label
--     "Official organiser" reads, never a stored flag, and no client can
--     write either input (clubs.is_verified is service-role only; the claim
--     columns are frozen by force_unverified_listing).
--   * is_verified: a hand-added (`manual`) listing that a club claimed got its
--     verification FROM the claim, so it now reads the club's current
--     standing. A provider-synced listing keeps its stored flag (the sync, a
--     service-role write, is what verified it), and so does a manual listing
--     nobody claimed.
--
-- Bodies re-emitted from 20271114002381 with the one expression changed and
-- one column appended; names, types and order of existing columns are kept.
-- Locks: view DDL only, a brief ACCESS EXCLUSIVE on the view, no table lock.

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
  case
    when l.provider = 'manual' and l.organiser_club_id is not null
      then coalesce(oc.is_verified, false)
    else l.is_verified
  end as is_verified,
  l.created_at,
  l.updated_at,
  coalesce(c.official_distance_m, c.distance_m)::numeric(10, 2) as course_distance_m,
  c.elevation_m as course_elevation_m,
  c.surface as course_surface,
  c.id as course_route_id,
  oc.id as organiser_club_id,
  oc.name as organiser_club_name,
  oc.slug as organiser_club_slug,
  case when c.id is not null then l.course_source end as course_source,
  case when c.id is not null then l.course_checked_at end as course_checked_at,
  case when c.id is not null then l.course_updated_at end as course_updated_at,
  coalesce(oc.is_verified, false) as organiser_is_official
from race_listings l
left join public_routes c on c.id = l.route_id
left join clubs oc
  on oc.id = l.organiser_club_id
 and oc.is_public = true
 and oc.shadow_hidden = false;

revoke all on public.public_race_listings from public, anon, authenticated;
grant select on public.public_race_listings to anon, authenticated;
