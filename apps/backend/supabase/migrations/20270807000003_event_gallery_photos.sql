-- The event gallery read applies the soft hide itself (decisions § 1906).
--
-- 20270807000001 hid a moderated photo by narrowing the "event photos
-- readable when event is readable" policy. Policies are OR'd, so an
-- attendee photo on a PUBLIC run still reached every viewer through "photos
-- readable when run is readable", and the gallery query — a plain table read
-- by event + occurrence — showed it with a Hidden badge to people who are not
-- stewards. Narrowing the run-path policy instead would pull the photo off the
-- runner's own public run, which § 1905 rules out: a steward's authority is
-- over the event page, not over a runner's run.
--
-- So "the gallery" is defined once, here. Security invoker on purpose: every
-- row still has to pass the table's RLS for the caller, and this adds the one
-- rule RLS cannot express per surface — a hidden photo is in the gallery only
-- for its owner and the event's stewards. `run_id` and `hidden_by` are not
-- returned: the gallery never needs a private run's id or the moderator's.

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
     and (
       rp.hidden_at is null
       or rp.owner_id = (select auth.uid())
       or private.is_event_photo_steward(rp.event_id, (select auth.uid()))
     )
   order by rp.created_at asc, rp.id asc
   limit least(greatest(coalesce(p_limit, 100), 1), 200);
$$;

revoke execute on function public.event_gallery_photos(uuid, timestamptz, int) from public;
grant execute on function public.event_gallery_photos(uuid, timestamptz, int)
  to anon, authenticated, service_role;
