-- Club logos: let a club's owners and admins upload the picture behind
-- `clubs.avatar_url`, which until now nothing could set.
--
-- Bytes live in the existing public `avatars` bucket under
-- `clubs/{club_id}/logo.{jpg|png|webp}`. That bucket is already public (a
-- club logo renders on the logged-out share page and in Browse exactly like
-- a profile picture does), already capped at 2 MB and already restricted to
-- the three strippable image types, so a separate bucket would only add a
-- fifth image bucket to hold to the same rules. The user avatar policies key
-- on `foldername[1] = auth.uid()`; `clubs` is never a uid, so the two path
-- families cannot reach each other.
--
-- The four policies below gate on `private.is_club_admin` — the same oracle
-- the "club admins can update their club" policy uses for the
-- `clubs.avatar_url` write itself — so whoever can point the row at a logo
-- is exactly whoever can write the logo. A path that is not precisely
-- `clubs/<uuid>/logo.<ext>` resolves to no club and is refused, so no
-- sub-folder, other filename or non-uuid segment is writable. SELECT is
-- granted (to admins only) because Storage `.remove()` selects the rows it
-- deletes; public downloads go through the bucket's public flag.
--
-- Lock impact: CREATE POLICY on storage.objects takes a brief metadata lock
-- and scans nothing.

create or replace function private.club_logo_object_club(p_name text)
returns uuid
language sql
immutable
set search_path = ''
as $$
  select case
    when p_name ~ '^clubs/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/logo\.(jpg|png|webp)$'
      then split_part(p_name, '/', 2)::uuid
  end;
$$;

revoke execute on function private.club_logo_object_club(text) from public, anon;
grant execute on function private.club_logo_object_club(text)
  to authenticated, service_role;

create policy "club admins can upload the club logo"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'avatars'
    and private.is_club_admin(private.club_logo_object_club(name))
  );

create policy "club admins can update the club logo"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'avatars'
    and private.is_club_admin(private.club_logo_object_club(name))
  )
  with check (
    bucket_id = 'avatars'
    and private.is_club_admin(private.club_logo_object_club(name))
  );

create policy "club admins can delete the club logo"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'avatars'
    and private.is_club_admin(private.club_logo_object_club(name))
  );

create policy "club admins can read the club logo objects"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'avatars'
    and private.is_club_admin(private.club_logo_object_club(name))
  );
