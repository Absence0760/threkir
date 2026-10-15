-- Runners' photos on a race-listing page (issue #1150 item 4, decisions § 1961).
--
-- /share/race/[id] is public, logged-out and crawler-indexed, so a photo
-- reaches it only by the owner's explicit, per-photo opt-in: making a run
-- public is consent to the run page, not to an indexed race page that lists
-- every runner of the race side by side. `race_gallery` is that opt-in. It
-- defaults false, can never be set at insert, and is written only through
-- `set_run_photo_race_gallery` by the photo's owner.
--
-- Everything else is derived at read time, so withdrawing needs no cleanup
-- job: `race_listing_photos` returns a photo only while its run is public and
-- still linked to the listing (`runs.race_listing_id`, the runner's own
-- confirmation of the race match), the photo_process worker has produced the
-- re-encoded, EXIF-free thumbnail, the photo is not hidden and its owner is
-- not shadow-hidden. A run-less (host) photo has no run to vouch for the race,
-- so `run_photos_race_gallery_needs_run` keeps it out.
--
-- The bytes need no new policy: the run-photos Storage SELECT policy already
-- admits a public run's photo (and its thumbnail) to anon through
-- `private.is_run_photo_visible_to`, which is every photo this read returns.
--
-- Locks: ADD COLUMN with a constant default is catalogue-only; the CHECK is
-- NOT VALID here and validated in 20270820000002; trigger and function DDL
-- take no table scan.

alter table public.run_photos
  add column race_gallery boolean not null default false;

alter table public.run_photos
  add constraint run_photos_race_gallery_needs_run
  check (not race_gallery or run_id is not null) not valid;

-- Invoker rights so `current_user` tells a direct client write (authenticated)
-- from the SECURITY DEFINER RPC (its owner) and the service role.
create or replace function public.run_photos_race_gallery_guard()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user in ('postgres', 'supabase_admin', 'service_role') then
    return new;
  end if;
  if tg_op = 'INSERT' and new.race_gallery then
    raise exception 'a photo is shared to its race page after upload, through set_run_photo_race_gallery'
      using errcode = '42501';
  end if;
  -- The read gate takes a set thumbnail as proof the worker re-encoded the
  -- bytes, and only an UPDATE of the column was locked (20260916_001), so a
  -- client could insert the raw original as its own thumbnail.
  if tg_op = 'INSERT' and new.thumb_512_path is not null then
    raise exception 'thumb_512_path is written by the photo worker only'
      using errcode = '42501';
  end if;
  if tg_op = 'UPDATE' and new.race_gallery is distinct from old.race_gallery then
    raise exception 'run_photos.race_gallery is set through set_run_photo_race_gallery only'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

revoke execute on function public.run_photos_race_gallery_guard() from public, anon, authenticated;

create trigger run_photos_race_gallery_guard_trigger
  before insert or update of race_gallery
  on public.run_photos
  for each row execute function public.run_photos_race_gallery_guard();

-- Share (p_shared = true) or withdraw one of the caller's own run photos.
create or replace function public.set_run_photo_race_gallery(p_photo_id uuid, p_shared boolean)
returns void
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_uid    uuid := auth.uid();
  v_owner  uuid;
  v_run_id uuid;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  if p_shared is null then
    raise exception 'p_shared is required' using errcode = '22004';
  end if;

  select owner_id, run_id into v_owner, v_run_id from run_photos where id = p_photo_id;
  if v_owner is distinct from v_uid or v_run_id is null then
    raise exception 'only the owner of a run photo can share it to the race page'
      using errcode = '42501';
  end if;

  update run_photos set race_gallery = p_shared where id = p_photo_id;
end;
$$;

revoke execute on function public.set_run_photo_race_gallery(uuid, boolean) from public, anon;
grant execute on function public.set_run_photo_race_gallery(uuid, boolean) to authenticated, service_role;

-- SECURITY DEFINER, unlike event_gallery_photos: run_photos' SELECT policies
-- are OR'd, and for a signed-in caller they also admit a followers-only or
-- shared run's photos, a coached athlete's, and any event-tagged photo — none
-- of which belongs on an indexed page. Anon cannot read user_profiles either.
-- So the function reads as its owner and states every rule itself.
create or replace function public.race_listing_photos(p_listing_id uuid, p_limit int default 24)
returns table (
  id uuid,
  thumb_512_path text,
  caption text,
  created_at timestamptz,
  display_name text
)
language sql
stable
security definer
set search_path = public
as $$
  select rp.id, rp.thumb_512_path, rp.caption, rp.created_at,
         up.display_name
    from public_race_listings l
    join runs r on r.race_listing_id = l.id
    join run_photos rp on rp.run_id = r.id
    left join user_profiles up on up.id = rp.owner_id
   where l.id = p_listing_id
     and r.is_public = true
     and rp.owner_id = r.user_id
     and rp.race_gallery = true
     and rp.thumb_512_path is not null
     and rp.thumb_512_path <> ''
     and rp.hidden_at is null
     and coalesce(up.shadow_hidden, false) = false
     and not exists (
       select 1 from user_blocks b
        where (b.blocker_id = rp.owner_id and b.blocked_id = (select auth.uid()))
           or (b.blocker_id = (select auth.uid()) and b.blocked_id = rp.owner_id)
     )
   order by rp.created_at desc, rp.id desc
   limit least(greatest(coalesce(p_limit, 24), 1), 60);
$$;

revoke execute on function public.race_listing_photos(uuid, int) from public;
grant execute on function public.race_listing_photos(uuid, int) to anon, authenticated, service_role;
