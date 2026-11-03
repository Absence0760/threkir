-- A `personal_record` notification when a run sets a new best, and the log of
-- improvements the PR share card reads (issue #1273 item 7, decisions § 2266).
--
-- ── Where the event is detected ─────────────────────────────────────────────
-- `personal_records` is a trigger-maintained cache rebuilt by DELETE + INSERT
-- (`refresh_personal_records_for_user`, docs/backend/derived_state.md), so a
-- trigger on the cache itself sees every refresh as a fresh row and cannot
-- tell a new best from a no-op recompute. The refresher is the one place that
-- holds both sides: it now reads the user's bests before the rebuild and hands
-- them to `private.record_personal_record_improvements` after it. A bracket
-- counts as improved only when the rebuilt time is strictly faster than the
-- one it replaced, or the bracket had no entry. So:
--   * a recompute that changes nothing (the manual rebuild, an edit to an
--     unrelated column, a re-run backfill) records and notifies nothing;
--   * a deleted or DNF-flagged PR run makes the cache slower, which is not an
--     improvement; the next run that beats the new value is.
-- Comparing against the cache as it stood, not against the best ever
-- announced, is deliberate: a GPS-glitch 5k that is deleted must not keep every
-- genuine 5k after it from counting.
--
-- ── Never twice ─────────────────────────────────────────────────────────────
-- `personal_record_improvements` is unique on (run_id, distance), so a run that
-- leaves the cache and comes back (its beater deleted) is not recorded again,
-- and one notification is raised per run, not per bracket: a 10 km run usually
-- improves the mile, 5k, 8k and 10k at once, and five bell rows for one run is
-- noise. The card reads every bracket the run improved; the notification only
-- points at the run. It is raised only for a run none of whose improvements was
-- recorded before this statement.
--
-- ── Only for a recent run ───────────────────────────────────────────────────
-- A history import (Strava backfill, a GPX upload of last year) can improve the
-- cache with runs from years ago, in whatever order the chunks arrive. Those
-- improvements are logged, because they are true, but a notification is raised
-- only when the run started within the last 7 days: "you just set a PR" about a
-- 2019 run is not news, and an import of five years would raise dozens.
--
-- ── Preferences ─────────────────────────────────────────────────────────────
-- Same as `achievement`: a bell row always; email and push follow the channel
-- modes in the Go worker (`personal_record` is in neither important set, so it
-- leaves the inbox only for a runner on `all`).
--
-- ── Privacy ─────────────────────────────────────────────────────────────────
-- PR times are owner-only (`personal_records` has only a self-select policy),
-- and so is this table. Nothing here becomes readable by anyone else; the card
-- is an image the owner chooses to export.
--
-- ── Locks ───────────────────────────────────────────────────────────────────
-- A new table (no scan), a `create or replace` on two SECURITY DEFINER
-- functions (ACLs kept), and the `notifications_kind_check` re-emitted
-- NOT VALID; 20271104235902 validates it in its own transaction
-- (docs/backend/migration_locks.md § CHECK constraints). No backfill: the
-- first refresh after this migration compares against the cache as it stands,
-- so nobody is told about a record they already hold.

create table personal_record_improvements (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references auth.users(id) on delete cascade,
  run_id           uuid not null references runs(id) on delete cascade,
  distance         text not null
                     check (distance in ('1_mile', '5k', '8k', '10k', '12k', 'half_marathon', 'marathon')),
  best_time_s      integer not null check (best_time_s > 0),
  previous_time_s  integer check (previous_time_s is null or previous_time_s > best_time_s),
  achieved_at      timestamptz not null,
  created_at       timestamptz not null default now(),
  constraint personal_record_improvements_run_distance_uk unique (run_id, distance)
);

create index personal_record_improvements_user_achieved
  on personal_record_improvements (user_id, achieved_at desc);

alter table personal_record_improvements enable row level security;

create policy personal_record_improvements_self_select
  on personal_record_improvements for select
  using (user_id = (select auth.uid()));

-- Written only by the refresher below; no client verb but SELECT.
revoke all on personal_record_improvements from anon, authenticated;
grant select on personal_record_improvements to authenticated;

create or replace function private.record_personal_record_improvements(p_user uuid, p_before jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  with improved as (
    insert into personal_record_improvements
      (user_id, run_id, distance, best_time_s, previous_time_s, achieved_at)
    select
      pr.user_id, pr.run_id, pr.distance, pr.best_time_s,
      (p_before ->> pr.distance)::integer, pr.achieved_at
    from personal_records pr
    where pr.user_id = p_user
      and pr.run_id is not null
      and (
        not (p_before ? pr.distance)
        or pr.best_time_s < (p_before ->> pr.distance)::integer
      )
    on conflict (run_id, distance) do nothing
    returning run_id, achieved_at
  )
  insert into notifications (user_id, kind, run_id, activity_kind, activity_id)
  select p_user, 'personal_record', i.run_id, 'run', i.run_id
  from (select distinct run_id from improved where achieved_at >= now() - interval '7 days') i
  -- The CTE's rows are not visible to this scan, so it sees only what was
  -- recorded before this statement.
  where not exists (
    select 1 from personal_record_improvements prior where prior.run_id = i.run_id
  );
end;
$$;

revoke all on function private.record_personal_record_improvements(uuid, jsonb)
  from public, anon, authenticated;

-- The live body (20270706000003) with the before-read and the hand-off added;
-- nothing else moves.
CREATE OR REPLACE FUNCTION public.refresh_personal_records_for_user(p_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_role text := coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'),
    ''
  );
  v_before jsonb;
begin
  if v_role <> 'service_role' and v_role <> '' then
    if auth.uid() is null or auth.uid() is distinct from p_user_id then
      raise exception 'refresh_personal_records_for_user: not authorized'
        using errcode = '42501';
    end if;
  end if;

  perform pg_advisory_xact_lock(
    hashtext('personal_records:' || p_user_id::text)
  );

  select coalesce(jsonb_object_agg(distance, best_time_s), '{}'::jsonb)
    into v_before
    from personal_records
   where user_id = p_user_id;

  delete from personal_records where user_id = p_user_id;

  insert into personal_records (user_id, distance, best_time_s, run_id, achieved_at)
  select
    p_user_id, distance, duration_s, run_id, achieved_at
  from (
    select
      run_id, duration_s, achieved_at, distance,
      row_number() over (
        partition by distance
        order by duration_s asc, achieved_at asc, run_id asc
      ) as rn
    from (
      -- Whole-run candidates, widened brackets, DNFs excluded.
      select
        id as run_id,
        duration_s,
        started_at as achieved_at,
        case
          when distance_m between 1559  and 1659   then '1_mile'
          when distance_m between 4900  and 5100   then '5k'
          when distance_m between 7840  and 8160   then '8k'
          when distance_m between 9800  and 10200  then '10k'
          when distance_m between 11760 and 12240  then '12k'
          when distance_m between 20675 and 21519  then 'half_marathon'
          when distance_m between 41351 and 43039  then 'marathon'
        end as distance
      from runs
      where user_id = p_user_id
        -- 'parkrun' (certified weekly 5K) + 'race' (chip-timed official results,
        -- the most authoritative source) are valid runs.source values (#378).
        and source in ('app', 'watch', 'strava', 'garmin', 'healthkit', 'healthconnect', 'parkrun', 'race')
        -- Run family only: a bicycle covers a PR bracket at speeds no runner
        -- reaches. Mirrors the client's `isRunFamily` in recap.ts.
        and activity_type <> 'cycle'
        and distance_m is not null
        and duration_s is not null
        and duration_s > 0
        and is_dnf = false

      union all

      -- Embedded-best 5k from the promoted fastest_5k_s column.
      select
        id as run_id, fastest_5k_s,
        started_at as achieved_at, '5k' as distance
      from runs
      where user_id = p_user_id
        and source in ('app', 'watch', 'strava', 'garmin', 'healthkit', 'healthconnect', 'parkrun', 'race')
        and activity_type <> 'cycle'
        and fastest_5k_s is not null
        and fastest_5k_s > 0
        and is_dnf = false

      union all

      select
        id as run_id, fastest_10k_s,
        started_at as achieved_at, '10k' as distance
      from runs
      where user_id = p_user_id
        and source in ('app', 'watch', 'strava', 'garmin', 'healthkit', 'healthconnect', 'parkrun', 'race')
        and activity_type <> 'cycle'
        and fastest_10k_s is not null
        and fastest_10k_s > 0
        and is_dnf = false

      union all

      select
        id as run_id, fastest_half_marathon_s,
        started_at as achieved_at, 'half_marathon' as distance
      from runs
      where user_id = p_user_id
        and source in ('app', 'watch', 'strava', 'garmin', 'healthkit', 'healthconnect', 'parkrun', 'race')
        and activity_type <> 'cycle'
        and fastest_half_marathon_s is not null
        and fastest_half_marathon_s > 0
        and is_dnf = false

      union all

      select
        id as run_id, fastest_marathon_s,
        started_at as achieved_at, 'marathon' as distance
      from runs
      where user_id = p_user_id
        and source in ('app', 'watch', 'strava', 'garmin', 'healthkit', 'healthconnect', 'parkrun', 'race')
        and activity_type <> 'cycle'
        and fastest_marathon_s is not null
        and fastest_marathon_s > 0
        and is_dnf = false
    ) candidates
    where distance is not null
  ) ranked
  where rn = 1;

  perform private.record_personal_record_improvements(p_user_id, v_before);
end;
$function$;

alter table notifications drop constraint notifications_kind_check;
alter table notifications
  add constraint notifications_kind_check
  check (
    kind in (
      'kudos', 'comment', 'comment_reply', 'follow',
      'event_rsvp', 'event_cancel', 'plan_update', 'message',
      'club_post', 'run_completed', 'event_reminder', 'plan_assigned',
      'achievement', 'challenge_complete', 'content_hidden',
      'data_export_ready', 'refund_failed', 'event_waitlist_slot',
      'follow_request',
      'reaction', 'comment_like', 'mention',
      'workout_reminder',
      'plan_ai_edit',
      'personal_record'
    )
  )
  not valid;
