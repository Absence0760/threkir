-- The event gallery is empty to a viewer who cannot see the event.
--
-- 20270807000003 defined the gallery as "the caller's RLS on run_photos, plus
-- the soft hide". But run_photos' SELECT policies are OR'd, and a photo on a
-- PUBLIC run passes "photos readable when run is readable" whatever event it
-- is tagged to. So an outsider (or anon) calling event_gallery_photos with a
-- members-only event's id, or the id of an event in a private club, got back
-- every attendee photo on a public run there: the gallery of an event the
-- viewer cannot open, with its owner ids and occurrence instants.
--
-- The event path already carries this gate ("event photos readable when event
-- is readable" and the Storage byte policy both require the event row to be
-- readable); the run path rightly does not, because the photo belongs on the
-- runner's own public run. The gallery is the event's surface, so it takes
-- the event's gate: the same `exists (… from events …)` subquery, which runs
-- under the caller's events RLS (security invoker), so a members-only event
-- and a private club's event both read empty to a non-member.
--
-- Same signature and return type, so CREATE OR REPLACE keeps the grants.

create or replace function public.event_gallery_photos(
  p_event_id uuid,
  p_instance timestamptz,
  p_limit int default 100
)
returns table (
  id uuid,
  owner_id uuid,
  storage_path text,
  thumb_512_path text,
  caption text,
  position_idx smallint,
  created_at timestamptz,
  event_id uuid,
  event_instance_start timestamptz,
  hidden_at timestamptz
)
language sql
stable
security invoker
set search_path = public
as $$
  select rp.id, rp.owner_id, rp.storage_path, rp.thumb_512_path, rp.caption,
         rp.position_idx, rp.created_at, rp.event_id, rp.event_instance_start,
         rp.hidden_at
    from run_photos rp
   where rp.event_id = p_event_id
     and rp.event_instance_start = p_instance
     and exists (select 1 from events e where e.id = p_event_id)
     and (
       rp.hidden_at is null
       or rp.owner_id = (select auth.uid())
       or private.is_event_photo_steward(rp.event_id, (select auth.uid()))
     )
   order by rp.created_at asc, rp.id asc
   limit least(greatest(coalesce(p_limit, 100), 1), 200);
$$;
