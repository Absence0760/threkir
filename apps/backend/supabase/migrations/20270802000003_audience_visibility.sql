-- Audience sharing, part 3: who the followers level and a grant let read.
--
-- Two oracles answer "does this run's / route's narrower audience admit this
-- viewer", and every read path that already asks "may this viewer see it"
-- gains them as one more OR'd branch. All of it is gated on
-- private.audience_sharing_enabled() (20270802000001), so until the flag row
-- is written the four helpers below answer exactly what they did before.
--
-- What changes for an admitted viewer (a follower of a followers_only entity,
-- or a named recipient of a live grant), none of them the owner:
--
--   * private.is_run_visible_to — kudos, comments, segment efforts, live
--     pings, run gear: the social rows that already follow the run (§ 32).
--   * private.is_run_photo_visible_to — the run's photos (table + Storage
--     bytes). The coach tier stays excluded (§ 98 amendment): a coaching link
--     was never consent to photos, while a share is the owner choosing THIS
--     run for THIS audience (§ R7SHARE-4).
--   * private.is_route_visible_to — markers, conditions, route photos,
--     reviews, segments, DM route attachments.
--   * clip_route_for_viewer — the route polyline, CLIPPED to the owner's
--     privacy zones exactly as for any non-owner (§ 33 unchanged).
--   * shared_runs / shared_routes — the redacted non-owner ROW read for a
--     non-public entity, the counterpart of public_runs / public_routes.
--     Same projection, so a recipient sees no column a stranger reading a
--     public run would not; `check_shared_constants.mjs` holds the two
--     metadata denylists equal and shared_audience_test.sql the column sets.
--     They contain no public row and no row of the caller's own, so no
--     existing reader of the public views changes.
--
-- What does NOT change: public_runs / public_routes, the feed, run_completed
-- notifications (§ 96), profile lists, the sitemap, heatmap and challenges.
-- They key on is_public, which neither level touches, so a shared run is
-- never broadcast. The raw track stays owner-only in Storage; the recipient's
-- track comes from clip-public-track, which this change teaches to read
-- shared_runs (§ R7SHARE-5).
--
-- A block either way silences both levels (a block already deletes the
-- follow edge, 20261012_001; this also covers a grant made before it), and a
-- shadow-hidden route is withheld from the audience branch the way it is from
-- the public one (20270329_001).
--
-- Bare-body rule: each function below is re-emitted from its LIVE body —
-- is_run_visible_to 20261103_001, is_run_photo_visible_to 20261125_001,
-- is_route_visible_to + clip_route_for_viewer 20270329_001 (made STABLE by
-- 20270722000001, which a create-or-replace would silently undo, so STABLE is
-- restated) — plus the one new branch.
--
-- Locks: function and view replacement is catalogue-only.

create or replace function private.run_audience_admits(
  p_run_id uuid,
  p_owner uuid,
  p_followers_only boolean,
  p_viewer uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, private
as $$
  select p_viewer is not null
     and p_owner is not null
     and p_viewer <> p_owner
     and private.audience_sharing_enabled()
     and (
       (p_followers_only and exists (
         select 1 from user_follows f
          where f.follower_id = p_viewer and f.followee_id = p_owner
       ))
       or exists (
         select 1 from run_shares s
          where s.run_id = p_run_id and s.recipient_id = p_viewer
       )
     )
     and not exists (
       select 1 from user_blocks b
        where (b.blocker_id = p_owner and b.blocked_id = p_viewer)
           or (b.blocker_id = p_viewer and b.blocked_id = p_owner)
     );
$$;

revoke execute on function private.run_audience_admits(uuid, uuid, boolean, uuid) from public, anon;
grant execute on function private.run_audience_admits(uuid, uuid, boolean, uuid)
  to authenticated, service_role;

create or replace function private.route_audience_admits(
  p_route_id uuid,
  p_owner uuid,
  p_followers_only boolean,
  p_viewer uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, private
as $$
  select p_viewer is not null
     and p_owner is not null
     and p_viewer <> p_owner
     and private.audience_sharing_enabled()
     and (
       (p_followers_only and exists (
         select 1 from user_follows f
          where f.follower_id = p_viewer and f.followee_id = p_owner
       ))
       or exists (
         select 1 from route_shares s
          where s.route_id = p_route_id and s.recipient_id = p_viewer
       )
     )
     and not exists (
       select 1 from user_blocks b
        where (b.blocker_id = p_owner and b.blocked_id = p_viewer)
           or (b.blocker_id = p_viewer and b.blocked_id = p_owner)
     );
$$;

revoke execute on function private.route_audience_admits(uuid, uuid, boolean, uuid) from public, anon;
grant execute on function private.route_audience_admits(uuid, uuid, boolean, uuid)
  to authenticated, service_role;

-- ── private.is_run_visible_to ── live body 20261103_001 + the audience branch.
create or replace function private.is_run_visible_to(p_run_id uuid, p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from runs r
    where r.id = p_run_id
      and (
        r.user_id = p_user_id
        or r.is_public = true
        or private.is_active_coach_of(p_user_id, r.user_id)
        or private.run_audience_admits(r.id, r.user_id, r.followers_only, p_user_id)
      )
  );
$$;

-- ── private.is_run_photo_visible_to ── live body 20261125_001 + the audience
-- branch. Still no coach branch.
create or replace function private.is_run_photo_visible_to(p_run_id uuid, p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from runs r
    where r.id = p_run_id
      and (
        r.user_id = p_user_id
        or r.is_public = true
        or private.run_audience_admits(r.id, r.user_id, r.followers_only, p_user_id)
      )
  );
$$;

-- ── private.is_route_visible_to ── live body 20270329_001 + the audience
-- branch, which honours shadow_hidden like the public branch does.
create or replace function private.is_route_visible_to(p_route_id uuid, p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from routes r
    where r.id = p_route_id
      and (
        r.user_id = p_user_id
        or (r.is_public = true and r.shadow_hidden = false)
        or (
          r.club_id is not null
          and exists (
            select 1 from club_members
            where club_id = r.club_id
              and user_id = p_user_id
              and status = 'active'
          )
        )
        or (
          r.shadow_hidden = false
          and private.route_audience_admits(r.id, r.user_id, r.followers_only, p_user_id)
        )
      )
  );
$$;

-- ── clip_route_for_viewer ── live body 20270329_001 (STABLE since
-- 20270722000001) + the audience branch. An admitted viewer is a non-owner,
-- so they fall through to the clip like every other non-owner.
create or replace function clip_route_for_viewer(p_route_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, extensions, private
as $$
declare
  v_caller uuid := auth.uid();
  v_owner uuid;
  v_is_public boolean;
  v_shadow_hidden boolean;
  v_followers_only boolean;
  v_club_id uuid;
  v_waypoints jsonb;
  v_visible boolean;
begin
  select user_id, is_public, shadow_hidden, followers_only, club_id, waypoints
    into v_owner, v_is_public, v_shadow_hidden, v_followers_only, v_club_id, v_waypoints
    from routes where id = p_route_id;

  if v_owner is null then
    raise exception 'route not found' using errcode = 'P0002';
  end if;

  -- Visibility gate, mirroring private.is_route_visible_to:
  --   - users own their routes (auth.uid() = user_id), hidden or not
  --   - public routes are readable by anyone UNLESS shadow-hidden
  --   - active club members read club routes, hidden or not
  --   - a follower of a followers_only route, or a named recipient of a
  --     route_shares grant, unless shadow-hidden (audience sharing gate)
  v_visible := (v_caller is not null and v_caller = v_owner)
            or (v_is_public = true and v_shadow_hidden = false);
  if not v_visible and v_club_id is not null and v_caller is not null then
    if private.is_club_member(v_club_id) then
      v_visible := true;
    end if;
  end if;
  if not v_visible and v_caller is not null and v_shadow_hidden = false then
    if private.route_audience_admits(p_route_id, v_owner, v_followers_only, v_caller) then
      v_visible := true;
    end if;
  end if;

  if not v_visible then
    raise exception 'route not visible' using errcode = '42501';
  end if;

  -- Owner gets unclipped waypoints.
  if v_caller is not null and v_caller = v_owner then
    return coalesce(v_waypoints, '[]'::jsonb);
  end if;

  -- Non-owner: delegate the zone walk to clip_track_for_user so the
  -- runs and routes paths share one implementation. clip_track_for_user
  -- handles the empty / non-array / oversize cases internally.
  return clip_track_for_user(v_owner, coalesce(v_waypoints, '[]'::jsonb));
end;
$$;

grant execute on function clip_route_for_viewer(uuid) to anon, authenticated;

-- ── shared_runs ── public_runs' projection (live body 20270628000001),
-- column for column and key for key, over the non-public runs whose audience
-- admits the caller. Keep the metadata denylist identical to public_runs';
-- check_shared_constants.mjs fails the PR when the two differ.
create or replace view shared_runs as
select
  r.id,
  r.user_id,
  r.started_at,
  r.duration_s,
  r.distance_m,
  r.elevation_gain_m,
  r.source,
  r.activity_type,
  r.is_dnf,
  r.is_public,
  r.created_at,
  case when is_public_route_by_id(r.route_id) then r.route_id else null end as route_id,
  case when is_public_event_by_id(r.event_id) then r.event_id else null end as event_id,
  r.race_listing_id,
  (r.track_url is not null) as has_track,
  r.fastest_5k_s,
  r.fastest_10k_s,
  r.fastest_half_marathon_s,
  r.fastest_marathon_s,
  coalesce(r.metadata, '{}'::jsonb)
    - 'strava_id'
    - 'garmin_id'
    - 'imported_from'
    - 'imported_at'
    - 'health_connect_type'
    - 'strava_activity_type'
    - 'source_file'
    - 'max_bpm'
    - 'plan_workout_id'
    - 'workout_step_results'
    - 'workout_adherence'
    - 'watch_workout'
    - 'guided_run_id'
    - 'indoor_source'
    - 'last_modified_at'
    - 'recovered_from_crash'
    - 'in_progress_saved_at'
    - 'in_progress'
    - 'safety_escalated_at'
    - 'expected_return_at'
    - 'manual_entry'
    - 'indoor_estimated'
    - 'distance_source'
    - 'race_name'
    - 'bib'
    - 'overall_place'
    - 'chip_time'
    - 'gun_time'
    - 'age_group_place'
    - 'age_group'
    - 'perceived_effort'
    - 'run_number'
    as metadata,
  r.concluded_at
from runs r
where r.is_public = false
  and private.run_audience_admits(r.id, r.user_id, r.followers_only, (select auth.uid()));

revoke all on public.shared_runs from public, anon, authenticated;
grant select on public.shared_runs to authenticated;

-- ── shared_routes ── public_routes' projection (live body 20270218_001) over
-- the non-public, non-hidden routes whose audience admits the caller.
create or replace view shared_routes as
select
  r.id,
  r.user_id,
  r.name,
  r.distance_m,
  r.elevation_m,
  r.surface,
  r.is_public,
  r.slug,
  r.created_at,
  r.updated_at,
  r.tags,
  r.is_featured,
  r.featured_at,
  r.run_count,
  case when is_public_club_by_id(r.club_id) then r.club_id else null end as club_id
from routes r
where r.is_public = false
  and r.shadow_hidden = false
  and private.route_audience_admits(r.id, r.user_id, r.followers_only, (select auth.uid()));

revoke all on public.shared_routes from public, anon, authenticated;
grant select on public.shared_routes to authenticated;
