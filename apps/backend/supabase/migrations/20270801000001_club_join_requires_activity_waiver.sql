-- Enforce a club's activity-risk acknowledgement in the database
-- (§ 1864).
--
-- `clubs.requires_activity_waiver` (20261023_001) was only ever checked by
-- the web club page, which disables its Join button until the box is
-- ticked and then writes `club_members.activity_waiver_ack_at`. Nothing
-- server-side looked at it, so two paths admitted a member with no
-- acknowledgement:
--
--   1. `join_club_by_token` (20260417_001) inserted an active membership
--      for anyone holding the invite link, whatever the club required.
--   2. The two self-join INSERT policies accepted a row with a null
--      `activity_waiver_ack_at`, so any client that skipped the checkbox
--      (the phone app never had one) joined a waiver club unacknowledged.
--
-- The RPC gains an `activity_waiver_ack` argument and refuses with
-- `activity_waiver_required` (P0001) when the club requires the waiver and
-- neither the call nor an earlier membership row carries it. Refusing
-- rather than parking the member as pending keeps the invite a one-step
-- join: the client shows the acknowledgement and calls again. The
-- timestamp is server-stamped, and an earlier acknowledgement is kept.
--
-- The argument defaults to false so a client still calling with `token`
-- alone resolves to the new function and is refused only for a waiver
-- club. The old one-argument signature is dropped: a second overload
-- would make PostgREST's resolution of `{token}` ambiguous.

drop function if exists public.join_club_by_token(text);

create function public.join_club_by_token(
  token text,
  activity_waiver_ack boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  target_club uuid;
  needs_waiver boolean;
  prior_ack timestamptz;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  select id, requires_activity_waiver
    into target_club, needs_waiver
    from clubs
   where invite_token = token;
  if target_club is null then
    raise exception 'invalid invite token';
  end if;

  select activity_waiver_ack_at into prior_ack
    from club_members
   where club_id = target_club and user_id = auth.uid();

  if needs_waiver and prior_ack is null and not coalesce(activity_waiver_ack, false) then
    raise exception 'activity_waiver_required'
      using errcode = 'P0001',
            hint = 'This club requires the activity-risk acknowledgement; '
                   'call again with activity_waiver_ack => true once the '
                   'member has accepted it.';
  end if;

  insert into club_members (club_id, user_id, role, status, activity_waiver_ack_at)
  values (
    target_club, auth.uid(), 'member', 'active',
    case when needs_waiver then coalesce(prior_ack, now()) end
  )
  on conflict (club_id, user_id) do update
    set status = 'active',
        activity_waiver_ack_at = coalesce(
          club_members.activity_waiver_ack_at,
          excluded.activity_waiver_ack_at
        );

  return target_club;
end;
$$;

revoke execute on function public.join_club_by_token(text, boolean) from public, anon;
grant execute on function public.join_club_by_token(text, boolean) to authenticated;

alter policy "self-join open clubs" on public.club_members
  with check ((((select auth.uid()) = user_id) AND (role = 'member'::text) AND (status = 'active'::text) AND (EXISTS ( SELECT 1
   FROM clubs
  WHERE ((clubs.id = club_members.club_id) AND (clubs.join_policy = 'open'::text)
    AND ((NOT clubs.requires_activity_waiver) OR (club_members.activity_waiver_ack_at IS NOT NULL)))))));

alter policy "self-request join request-policy clubs" on public.club_members
  with check ((((select auth.uid()) = user_id) AND (role = 'member'::text) AND (status = 'pending'::text) AND (EXISTS ( SELECT 1
   FROM clubs
  WHERE ((clubs.id = club_members.club_id) AND (clubs.join_policy = 'request'::text)
    AND ((NOT clubs.requires_activity_waiver) OR (club_members.activity_waiver_ack_at IS NOT NULL)))))));
