-- Strip the race division-award keys from the non-owner run reads.
--
-- race-results-import now records the award division a runner placed in
-- (`division_award`, e.g. "M Masters" or "F Top 3 Overall") and their place in
-- it (`division_award_place`). A RunSignUp award division lifts a runner out of
-- their age group, so until now the runner who won one got neither field
-- (decisions § 1913). Masters and weight-class labels name an age band, so both
-- keys are owner-only exactly like `age_group` / `age_group_place`.
--
-- Both views keep their live bodies (public_runs 20270822000001, shared_runs
-- 20270802000003) with the two keys appended to the denylist;
-- check_shared_constants.mjs holds the two denylists equal.
set search_path = public, extensions;

create or replace view public_runs as
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
    - 'division_award'
    - 'division_award_place'
    - 'perceived_effort'
    - 'run_number'
    as metadata,
  r.concluded_at
from runs r
where r.is_public = true
  and (
    not exists (
      select 1 from user_profiles p
       where p.id = r.user_id and p.profile_private
    )
    or r.user_id = (select auth.uid())
    or exists (
      select 1 from user_follows f
       where f.followee_id = r.user_id and f.follower_id = (select auth.uid())
    )
    or (r.concluded_at is null and r.metadata->>'in_progress' = 'true')
  );

revoke all on public.public_runs from public, anon, authenticated;
grant select on public_runs to anon, authenticated;

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
    - 'division_award'
    - 'division_award_place'
    - 'perceived_effort'
    - 'run_number'
    as metadata,
  r.concluded_at
from runs r
where r.is_public = false
  and private.run_audience_admits(r.id, r.user_id, r.followers_only, (select auth.uid()));

revoke all on public.shared_runs from public, anon, authenticated;
grant select on public.shared_runs to authenticated;
