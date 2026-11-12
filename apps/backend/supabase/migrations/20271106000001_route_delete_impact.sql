-- Deleting a route (issue #1286; decisions § 2293).
--
-- Every foreign key that references routes(id) already carries the outcome a
-- route delete should have, so none moves here:
--
--   CASCADE  (the route's own content, meaningless without its line)
--            route_photos, route_markers, route_conditions, route_reviews,
--            route_shares, saved_routes, segments (and, through them,
--            segment_efforts)
--   SET NULL (someone else's record that merely pointed at it)
--            runs.route_id, events.route_id, event_courses.route_id,
--            race_listings.route_id, direct_messages.route_id, and
--            event_checkpoints.route_marker_id through route_markers
--
-- A delete is not refused because others depend on the route. A course the
-- owner may never remove would let other people's references hold the owner's
-- data hostage, account deletion included. What the owner is owed instead is
-- to be told before confirming, and two of the things they would want to hear
-- about are rows their own session cannot read: other runners' bookmarks
-- (saved_routes is owner-read only) and the race listings using it as a course
-- (race_listings is submitter-read only). route_delete_impact counts them.
--
-- The second change is to Storage. A route photo's bytes sit in the
-- uploader's folder of the private route-photos bucket, and the only SELECT
-- policy on them joins through a live route_photos row. Storage's remove()
-- runs a DELETE whose WHERE reads the object's columns, so Postgres applies
-- the SELECT policies too, and once the route's cascade has taken the
-- route_photos rows the uploader can no longer remove their own bytes. The
-- clients therefore swept the bytes BEFORE deleting the route, and a route
-- delete that then failed left the route standing with its photos gone. A
-- folder owner may now read their own objects, so the clients delete the route
-- first and sweep after. Bytes a failed sweep leaves are erased by the
-- route-photo orphan sweep (20271106000020, behind its feature flag), and by
-- delete-account's folder sweep in any case.
--
-- No table DDL: one storage policy and one function.

set search_path = public;

create policy "Users read their own route photo objects"
  on storage.objects for select
  using (
    bucket_id = 'route-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create or replace function public.route_delete_impact(p_route_id uuid)
returns table (
  saved_by_others integer,
  reviews_by_others integer,
  conditions_by_others integer,
  segments_by_others integer,
  segment_efforts_by_others integer,
  shares integer,
  race_listings integer,
  events integer,
  linked_runs integer,
  photos integer,
  markers integer
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := (select auth.uid());
  v_audience boolean := private.audience_sharing_enabled();
begin
  -- The same principals the routes DELETE policies admit: the uploader, or an
  -- admin of the club that owns the route. A missing route answers the same
  -- refusal, so the function is no oracle for which route ids exist.
  if v_uid is null or not exists (
    select 1 from routes r
    where r.id = p_route_id
      and (r.user_id = v_uid
           or (r.club_id is not null and private.is_club_admin(r.club_id)))
  ) then
    raise exception 'not allowed to delete this route' using errcode = '42501';
  end if;

  return query
  select
    (select count(*)::int from saved_routes s
       where s.route_id = p_route_id and s.user_id <> v_uid),
    (select count(*)::int from route_reviews rr
       where rr.route_id = p_route_id and rr.user_id <> v_uid),
    (select count(*)::int from route_conditions rc
       where rc.route_id = p_route_id and rc.user_id <> v_uid),
    (select count(*)::int from segments sg
       where sg.route_id = p_route_id and sg.author_id is distinct from v_uid),
    (select count(*)::int from segment_efforts se
       join segments sg on sg.id = se.segment_id
       where sg.route_id = p_route_id and se.user_id <> v_uid),
    (select count(*)::int from route_shares sh where sh.route_id = p_route_id),
    (select count(*)::int from race_listings rl where rl.route_id = p_route_id),
    (select count(*)::int from events e
       where e.route_id = p_route_id
          or exists (select 1 from event_courses ec
                     where ec.event_id = e.id and ec.route_id = p_route_id)),
    -- Only runs the caller could open anyway. A club admin who is not the
    -- uploader must not learn that private runs follow the route. This is
    -- private.is_run_visible_to(run, v_uid) with its helpers
    -- (profile_visible_to, is_active_coach_of, run_audience_admits) inlined as
    -- joins, because a popular public route has thousands of runs and the
    -- per-run call re-reads the run and each helper's tables once per row.
    -- route_delete_test.sql compares the two over runs admitted by every arm,
    -- so a change to the shared rule that is not made here fails there.
    (select count(*)::int
       from runs ru
       left join user_profiles up on up.id = ru.user_id
       left join user_follows fo
              on fo.follower_id = v_uid and fo.followee_id = ru.user_id
      where ru.route_id = p_route_id
        and (
          ru.user_id = v_uid
          or (
            ru.is_public = true
            and (
              not coalesce(up.profile_private, false)
              or fo.follower_id is not null
              or (ru.concluded_at is null and ru.metadata ->> 'in_progress' = 'true')
            )
          )
          or exists (
            select 1 from coach_athletes ca
             where ca.coach_id = v_uid
               and ca.athlete_id = ru.user_id
               and ca.status = 'active'
          )
          or (
            v_audience
            and ru.user_id <> v_uid
            and (
              (ru.followers_only and fo.follower_id is not null)
              or exists (
                select 1 from run_shares rs
                 where rs.run_id = ru.id and rs.recipient_id = v_uid
              )
            )
            and not exists (
              select 1 from user_blocks b
               where (b.blocker_id = ru.user_id and b.blocked_id = v_uid)
                  or (b.blocker_id = v_uid and b.blocked_id = ru.user_id)
            )
          )
        )),
    (select count(*)::int from route_photos rp where rp.route_id = p_route_id),
    (select count(*)::int from route_markers rm where rm.route_id = p_route_id);
end;
$$;

comment on function public.route_delete_impact(uuid) is
  'What deleting a route takes or detaches, for the confirm the owner reads first: '
  'other runners'' bookmarks, reviews, condition reports, segments and efforts '
  '(cascade), shares (cascade), race listings and events using it as a course and '
  'the runs that followed it that the caller can see (link nulled), and its '
  'photos and markers (cascade). '
  'Owner or club admin only (42501 otherwise, including for a missing route).';

revoke all on function public.route_delete_impact(uuid) from public, anon;
grant execute on function public.route_delete_impact(uuid) to authenticated, service_role;
