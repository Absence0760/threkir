-- get_my_profile() returns zero rows, not an all-null row, for a caller
-- with no user_profiles row (issue #1065).
--
-- It was declared `returns user_profiles` — a single composite. With no
-- matching row the SQL function yields a NULL composite, and PostgREST
-- serialises that as an object whose every field is null rather than as
-- an empty result. Every reader then took "no row" for "a row":
--   * mobile `UserProfileRow.fromJson` threw on `id`, so Settings → Account
--     could never load for a new Apple / Google account;
--   * web `fetchUser` and mobile `ensureMyProfile` both test the result for
--     null before bootstrapping the row, so neither ever created it.
--
-- `setof` makes the empty case honest: PostgREST answers `[]`, and
-- `.maybeSingle()` (web) / the list branch of `fetchMyProfile` (Dart)
-- read that as null. The body, the SECURITY DEFINER self-read and the
-- caller set are unchanged.
--
-- A return-type change cannot go through `create or replace`, so the
-- function is dropped and recreated; that resets its ACL to the project
-- default privileges, which is why the grants are restated in full.

drop function public.get_my_profile();

create function public.get_my_profile()
returns setof public.user_profiles
language sql
stable
security definer
set search_path = public
as $$
  select * from public.user_profiles where id = auth.uid();
$$;

revoke execute on function public.get_my_profile() from public, anon;
grant execute on function public.get_my_profile() to authenticated;
