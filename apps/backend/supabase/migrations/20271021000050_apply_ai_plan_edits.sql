-- AI plan edits apply in one transaction, from the plan page or the Coach
-- chat, and may carry an intensity change into the blocks queued after the
-- plan (issue #1213, decisions § 2230, superseding part of § 1979).
--
-- The web apply used to write a reviewed AI edit row by row: the dates through
-- reschedule_plan_workouts, then each workout through an UPDATE, each skip and
-- each week target separately. A failure half-way left the plan half-edited.
-- apply_ai_plan_edits writes every change, in one plan or across the plan and
-- the active plans chained after it, or none of them.
--
-- The client computes the changes (plan_edit/apply.ts) and grades them, and the
-- runner reviews a diff before pressing Apply. This function does not trust
-- that payload: it re-checks every change against the rows as they are now,
-- and raises on the first one outside the bounds an AI plan edit may reach,
-- which rolls back everything already written. The bounds are the ones
-- validatePlanEditOps / applyPlanEditOps enforce:
--
--   - the plan is the caller's, active, not a template, and not already over
--     (end_date >= p_today); a plan in the past or completed is never edited
--     (§ 2052). p_today is the runner's local date and must fall within a day
--     of the server's, the window resolveToday already uses;
--   - with p_include_following, the active plans that start after this one
--     ends may also change, the same set shift_training_plan's
--     p_shift_following moves; without it, no other plan may;
--   - a workout must be dated today or later and be neither done nor a race;
--     a rest day or a skipped workout may only change its date (a move onto
--     an occupied day trades the two), anything else may also be scaled,
--     eased to recovery or skipped;
--   - a date stays inside the workout's own plan week, on or after today and
--     on or before the plan's end;
--   - a distance, duration or week target scales by 0.5 to 1.1 of its current
--     value (rounding allowed), and a workout never above 1.0 in a taper or
--     race week, on a workout a B/C race taper already eased
--     (race_taper_applied_at), or on one whose current or new day falls in a
--     B or C race's taper or recovery window, in the edit's plans or the
--     block just before them (private.in_bc_race_window, the windows of
--     race_taper.ts, decisions § 2051);
--   - the only kind change is a tempo, interval or marathon-pace session
--     becoming recovery, and only that change may clear its pace targets and
--     structure;
--   - a following block is only scaled: its changes carry a distance, a
--     duration or a week target and nothing else;
--   - a workout or a week appears once.
--
-- The ACWR grade (planEditLoadCheck) stays on the client, where the runner's
-- recent runs are; the 1.1 ceiling bounds what any one apply can add. The
-- week target is checked only against the 0.5-1.1 band and the taper cap: a
-- week holding a B/C window rises by less than the factor on the client.
--
-- When an edited plan was assigned by a coach the runner still has an active
-- link with, that coach gets one in-app 'plan_ai_edit' notification per plan,
-- refreshed rather than repeated while an earlier one is unread. The athlete
-- owns the plan and may apply; the coach approval flow is #1215 Phase 2.
--
-- Locks: the CHECK swap takes a brief ACCESS EXCLUSIVE on notifications with
-- no scan (NOT VALID); 20271021000051 validates it in its own transaction.
-- The functions are catalogue-only.

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
      'plan_ai_edit'
    )
  )
  not valid;

-- Whether p_day falls in the taper or recovery window of a B or C race in any
-- of p_plan_ids. This is the third copy of the race_taper.ts windows
-- (windowFor / recoveryDays; the Dart twin is race_taper.dart), registered
-- with that pair in docs/architecture/parity_pairs.md: a change to a window
-- there changes it here, and apply_ai_plan_edits_test.sql pins every branch.
-- Every race counts, ahead or already run, since a race behind today still
-- has its recovery window ahead. A race reads as planRaces reads it: an unset
-- priority is A on its plan's end date and C anywhere else, and an end-date
-- race with no distance of its own takes the plan's goal distance. B: 6 days
-- before (8 for a race beyond the marathon), and after it round(km / 3) days
-- held to 4..7, 5 with no distance, or for an ultra min(21, round(7 +
-- (km - 42.195) / 2)). C: 3 before, 2 after. round() on numeric rounds half
-- away from zero, as Math.round does for these positive values.
-- Invoker: it reads only the caller's own plan rows, under their RLS.
create or replace function private.in_bc_race_window(p_plan_ids uuid[], p_day date)
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select exists (
    select 1
    from plan_workouts rw
    join plan_weeks rwk on rwk.id = rw.week_id
    join training_plans tp on tp.id = rwk.plan_id
    cross join lateral (
      select coalesce(rw.race_priority,
                      case when rw.scheduled_date = tp.end_date then 'A' else 'C' end) as priority,
             coalesce(rw.target_distance_m,
                      case when rw.scheduled_date = tp.end_date then tp.goal_distance_m end) as metres
    ) race
    where rwk.plan_id = any (p_plan_ids)
      and rw.kind = 'race'
      and race.priority in ('B', 'C')
      and (
        (p_day < rw.scheduled_date
         and rw.scheduled_date - p_day <= case
           when race.priority = 'C' then 3
           when race.metres > 42195 then 8
           else 6
         end)
        or
        (p_day > rw.scheduled_date
         and p_day - rw.scheduled_date <= case
           when race.priority = 'C' then 2
           when race.metres is null or race.metres <= 0 then 5
           when race.metres > 42195 then
             least(21, round(7 + (race.metres - 42195) / 1000.0 / 2))
           else least(7, greatest(4, round(race.metres / 1000.0 / 3)))
         end)
      )
  );
$$;

revoke execute on function private.in_bc_race_window(uuid[], date) from public, anon;
grant execute on function private.in_bc_race_window(uuid[], date) to authenticated;

-- SECURITY DEFINER because clients cannot insert notifications. It acts only
-- for the caller's own plan and only toward the coach that plan names, and
-- only while that coach's link with the caller is active.
create or replace function private.notify_coach_of_ai_plan_edit(p_plan_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid;
  v_coach uuid;
begin
  select tp.user_id, tp.assigned_by_coach_id into v_owner, v_coach
  from training_plans tp
  where tp.id = p_plan_id;
  if v_owner is null or v_owner is distinct from auth.uid()
     or v_coach is null or v_coach = v_owner then
    return;
  end if;
  if not exists (
    select 1 from coach_athletes ca
    where ca.coach_id = v_coach and ca.athlete_id = v_owner and ca.status = 'active'
  ) then
    return;
  end if;

  update notifications
  set created_at = now()
  where user_id = v_coach
    and actor_id = v_owner
    and kind = 'plan_ai_edit'
    and plan_id = p_plan_id
    and read_at is null;
  if not found then
    insert into notifications (user_id, actor_id, kind, plan_id)
    values (v_coach, v_owner, 'plan_ai_edit', p_plan_id);
  end if;
end;
$$;

revoke execute on function private.notify_coach_of_ai_plan_edit(uuid) from public, anon;
grant execute on function private.notify_coach_of_ai_plan_edit(uuid) to authenticated;

create or replace function public.apply_ai_plan_edits(
  p_plan_id uuid,
  p_today date,
  p_include_following boolean,
  p_workouts jsonb,
  p_weeks jsonb
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  plan_row training_plans%rowtype;
  following record;
  allowed uuid[];
  race_plans uuid[];
  touched uuid[] := '{}';
  seen uuid[] := '{}';
  ch jsonb;
  r record;
  v_id uuid;
  v_keys text[];
  v_date_only boolean;
  v_following boolean;
  v_to_recovery boolean;
  v_new_date date;
  v_week_start date;
  v_ceiling numeric;
  v_old numeric;
  v_new numeric;
  v_col text;
  v_rows integer;
  v_plan uuid;
  workout_keys constant text[] := array[
    'id', 'scheduled_date', 'kind', 'target_distance_m', 'target_duration_seconds',
    'target_pace_sec_per_km', 'target_pace_tolerance_sec', 'structure', 'skip'
  ];
  following_keys constant text[] := array['id', 'target_distance_m', 'target_duration_seconds'];
  quality_kinds constant text[] := array['tempo', 'interval', 'marathon_pace'];
begin
  if caller is null then
    raise exception using
      errcode = 'insufficient_privilege',
      message = 'apply_ai_plan_edits: not authenticated';
  end if;
  if p_today is null or p_today < current_date - 1 or p_today > current_date + 1 then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = 'apply_ai_plan_edits: today must be within a day of the server date';
  end if;
  if p_workouts is null or jsonb_typeof(p_workouts) <> 'array'
     or p_weeks is null or jsonb_typeof(p_weeks) <> 'array' then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = 'apply_ai_plan_edits: workouts and weeks must be lists';
  end if;
  -- A season of three 24-week blocks at seven days a week is 504 workouts.
  if jsonb_array_length(p_workouts) > 1000 or jsonb_array_length(p_weeks) > 200 then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = 'apply_ai_plan_edits: too many changes';
  end if;

  select * into plan_row
  from training_plans
  where id = p_plan_id and user_id = caller
  for update;
  if not found then
    raise exception using
      errcode = 'no_data_found',
      message = format('apply_ai_plan_edits: plan %s not found', p_plan_id);
  end if;
  if plan_row.is_template or plan_row.status <> 'active' or plan_row.end_date < p_today then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = 'apply_ai_plan_edits: only an active plan that has not ended';
  end if;

  allowed := array[p_plan_id];
  if coalesce(p_include_following, false) then
    for following in
      select tp.id
      from training_plans tp
      where tp.user_id = caller
        and tp.status = 'active'
        and not tp.is_template
        and tp.start_date > plan_row.end_date
      order by tp.start_date
      for update
    loop
      allowed := allowed || following.id;
    end loop;
  end if;

  -- Whose B/C race windows hold a scale-up: the plans the edit may change and
  -- the block just before this one (the caller's latest non-template active
  -- or completed plan ending before it starts, ties to the lowest id), whose
  -- race at its end can have a recovery window running into this plan. The
  -- client reads the same block (fetchPrecedingPlan) and these plans' races;
  -- in 'plan' scope it also counts the following blocks' races, which only
  -- holds more back than this requires.
  race_plans := allowed || array(
    select tp.id
    from training_plans tp
    where tp.user_id = caller
      and not tp.is_template
      and tp.status in ('active', 'completed')
      and tp.end_date < plan_row.start_date
    order by tp.end_date desc, tp.id
    limit 1
  );

  set constraints plan_workouts_one_per_day deferred;

  for ch in select value from jsonb_array_elements(p_workouts) loop
    if jsonb_typeof(ch) <> 'object' or ch->>'id' is null then
      raise exception using
        errcode = 'invalid_parameter_value',
        message = 'apply_ai_plan_edits: every workout change needs an id';
    end if;
    select array_agg(k) into v_keys from jsonb_object_keys(ch) k;
    if not (v_keys <@ workout_keys) then
      raise exception using
        errcode = 'invalid_parameter_value',
        message = 'apply_ai_plan_edits: a change names a field an AI edit cannot write';
    end if;
    v_id := (ch->>'id')::uuid;
    if v_id = any (seen) then
      raise exception using
        errcode = 'invalid_parameter_value',
        message = format('apply_ai_plan_edits: workout %s is changed twice', v_id);
    end if;
    seen := seen || v_id;

    select wo.scheduled_date, wo.kind::text as kind, wo.target_distance_m,
           wo.target_duration_seconds, wo.skipped_at, wo.race_taper_applied_at,
           (wo.completed_run_id is not null or wo.manually_completed) as done,
           w.week_index, w.phase::text as phase, w.plan_id,
           tp.start_date as plan_start, tp.end_date as plan_end
      into r
    from plan_workouts wo
    join plan_weeks w on w.id = wo.week_id
    join training_plans tp on tp.id = w.plan_id
    where wo.id = v_id and w.plan_id = any (allowed);
    if not found then
      raise exception using
        errcode = 'invalid_parameter_value',
        message = format('apply_ai_plan_edits: workout %s is not in a plan this edit may change', v_id);
    end if;
    if r.done or r.kind = 'race' or r.scheduled_date < p_today then
      raise exception using
        errcode = 'invalid_parameter_value',
        message = format('apply_ai_plan_edits: workout %s is done, a race or in the past', v_id);
    end if;

    v_following := r.plan_id <> p_plan_id;
    if v_following and not (v_keys <@ following_keys) then
      raise exception using
        errcode = 'invalid_parameter_value',
        message = 'apply_ai_plan_edits: a following block can only be scaled';
    end if;
    v_date_only := v_keys <@ array['id', 'scheduled_date'];
    if not v_date_only and (r.skipped_at is not null or r.kind = 'rest') then
      raise exception using
        errcode = 'invalid_parameter_value',
        message = format('apply_ai_plan_edits: workout %s can only change its day', v_id);
    end if;

    if ch ? 'scheduled_date' then
      v_new_date := (ch->>'scheduled_date')::date;
      v_week_start := r.plan_start + r.week_index * 7;
      if v_new_date is null
         or v_new_date < greatest(v_week_start, p_today)
         or v_new_date > least(v_week_start + 6, r.plan_end) then
        raise exception using
          errcode = 'invalid_parameter_value',
          message = format('apply_ai_plan_edits: %s is outside the week of workout %s', v_new_date, v_id);
      end if;
    end if;

    v_to_recovery := false;
    if ch ? 'kind' then
      if ch->>'kind' is distinct from 'recovery' or not (r.kind = any (quality_kinds)) then
        raise exception using
          errcode = 'invalid_parameter_value',
          message = 'apply_ai_plan_edits: the only kind change is a quality session eased to recovery';
      end if;
      v_to_recovery := true;
    end if;
    if (ch ? 'target_pace_sec_per_km' or ch ? 'target_pace_tolerance_sec' or ch ? 'structure')
       and (not v_to_recovery
            or coalesce(ch->'target_pace_sec_per_km', 'null'::jsonb) <> 'null'::jsonb
            or coalesce(ch->'target_pace_tolerance_sec', 'null'::jsonb) <> 'null'::jsonb
            or coalesce(ch->'structure', 'null'::jsonb) <> 'null'::jsonb) then
      raise exception using
        errcode = 'invalid_parameter_value',
        message = 'apply_ai_plan_edits: pace targets and structure are only cleared by easing to recovery';
    end if;

    v_ceiling := case
      when r.phase in ('taper', 'race') or r.race_taper_applied_at is not null then 1.0
      when (ch ? 'target_distance_m' or ch ? 'target_duration_seconds')
           and (private.in_bc_race_window(race_plans, r.scheduled_date)
                or private.in_bc_race_window(race_plans,
                     coalesce((ch->>'scheduled_date')::date, r.scheduled_date))) then 1.0
      else 1.1
    end;
    foreach v_col in array array['target_distance_m', 'target_duration_seconds'] loop
      if ch ? v_col then
        v_old := case v_col when 'target_distance_m' then r.target_distance_m
                            else r.target_duration_seconds end;
        v_new := (ch->>v_col)::numeric;
        if v_old is null or v_new is null
           or v_new < floor(v_old * 0.5) or v_new > ceil(v_old * v_ceiling) then
          raise exception using
            errcode = 'invalid_parameter_value',
            message = format('apply_ai_plan_edits: %s of workout %s moves outside the scaling an AI edit allows', v_col, v_id);
        end if;
      end if;
    end loop;

    if ch ? 'skip' and ch->'skip' <> 'true'::jsonb then
      raise exception using
        errcode = 'invalid_parameter_value',
        message = 'apply_ai_plan_edits: skip can only be true';
    end if;

    update plan_workouts set
      scheduled_date = case when ch ? 'scheduled_date'
        then (ch->>'scheduled_date')::date else scheduled_date end,
      kind = case when v_to_recovery then 'recovery'::workout_kind else kind end,
      target_distance_m = case when ch ? 'target_distance_m'
        then (ch->>'target_distance_m')::numeric else target_distance_m end,
      target_duration_seconds = case when ch ? 'target_duration_seconds'
        then round((ch->>'target_duration_seconds')::numeric)::int else target_duration_seconds end,
      target_pace_sec_per_km = case when ch ? 'target_pace_sec_per_km'
        then null else target_pace_sec_per_km end,
      target_pace_tolerance_sec = case when ch ? 'target_pace_tolerance_sec'
        then null else target_pace_tolerance_sec end,
      structure = case when ch ? 'structure' then null else structure end,
      skipped_at = case when ch ? 'skip' then now() else skipped_at end
    where id = v_id;
    get diagnostics v_rows = row_count;
    if v_rows <> 1 then
      raise exception using
        errcode = 'insufficient_privilege',
        message = format('apply_ai_plan_edits: not authorised to edit workout %s', v_id);
    end if;
    if not (r.plan_id = any (touched)) then
      touched := touched || r.plan_id;
    end if;
  end loop;

  seen := '{}';
  for ch in select value from jsonb_array_elements(p_weeks) loop
    if jsonb_typeof(ch) <> 'object' or ch->>'id' is null
       or not (ch ? 'target_volume_m') then
      raise exception using
        errcode = 'invalid_parameter_value',
        message = 'apply_ai_plan_edits: every week change needs an id and a target volume';
    end if;
    select array_agg(k) into v_keys from jsonb_object_keys(ch) k;
    if not (v_keys <@ array['id', 'target_volume_m']) then
      raise exception using
        errcode = 'invalid_parameter_value',
        message = 'apply_ai_plan_edits: a week change names a field an AI edit cannot write';
    end if;
    v_id := (ch->>'id')::uuid;
    if v_id = any (seen) then
      raise exception using
        errcode = 'invalid_parameter_value',
        message = format('apply_ai_plan_edits: week %s is changed twice', v_id);
    end if;
    seen := seen || v_id;

    select w.week_index, w.phase::text as phase, w.target_volume_m, w.plan_id,
           tp.start_date as plan_start
      into r
    from plan_weeks w
    join training_plans tp on tp.id = w.plan_id
    where w.id = v_id and w.plan_id = any (allowed);
    if not found then
      raise exception using
        errcode = 'invalid_parameter_value',
        message = format('apply_ai_plan_edits: week %s is not in a plan this edit may change', v_id);
    end if;
    if r.plan_start + r.week_index * 7 + 6 < p_today then
      raise exception using
        errcode = 'invalid_parameter_value',
        message = format('apply_ai_plan_edits: week %s is already over', v_id);
    end if;

    v_ceiling := case when r.phase in ('taper', 'race') then 1.0 else 1.1 end;
    v_old := r.target_volume_m;
    v_new := (ch->>'target_volume_m')::numeric;
    if v_old is null or v_new is null
       or v_new < floor(v_old * 0.5) or v_new > ceil(v_old * v_ceiling) then
      raise exception using
        errcode = 'invalid_parameter_value',
        message = format('apply_ai_plan_edits: the target of week %s moves outside the scaling an AI edit allows', v_id);
    end if;

    update plan_weeks set target_volume_m = v_new where id = v_id;
    get diagnostics v_rows = row_count;
    if v_rows <> 1 then
      raise exception using
        errcode = 'insufficient_privilege',
        message = format('apply_ai_plan_edits: not authorised to edit week %s', v_id);
    end if;
    if not (r.plan_id = any (touched)) then
      touched := touched || r.plan_id;
    end if;
  end loop;

  set constraints plan_workouts_one_per_day immediate;

  foreach v_plan in array touched loop
    perform private.notify_coach_of_ai_plan_edit(v_plan);
  end loop;
end;
$$;

revoke execute on function public.apply_ai_plan_edits(uuid, date, boolean, jsonb, jsonb) from public, anon;
grant execute on function public.apply_ai_plan_edits(uuid, date, boolean, jsonb, jsonb) to authenticated;
