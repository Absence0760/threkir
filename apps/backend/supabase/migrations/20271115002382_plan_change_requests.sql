-- Changes to a coach-assigned plan go to the coach for approval (issue #1215
-- Phase 2, decisions § 2382).
--
-- An athlete owns a plan a coach assigned with assign_plan_to_athlete, and
-- until now an AI-proposed edit to it (#1213, apply_ai_plan_edits) was applied
-- by the athlete with the coach told afterwards ('plan_ai_edit'). This adds the
-- path the issue asks for: the athlete can send the same reviewed edit to the
-- coach as a suggested change, and the coach approves it (all of it or some of
-- its lines) or declines it with a note. An approval is applied atomically by
-- the same checks apply_ai_plan_edits runs. The athlete keeps the right to
-- apply it themselves; the coach is told when they do.
--
-- No new data flow: a request holds the structured change set (the
-- apply_ai_plan_edits payload: workout ids with new dates, distances,
-- durations, a recovery kind or a skip, and week targets) and no AI text, so
-- nothing model-written crosses between users (decisions § 110) and nothing is
-- sent to Anthropic. The coach already reads an active athlete's plan rows
-- (20261116_001), which is how both clients show the diff: "before" is the
-- row as it is now, "after" is the payload over it.
--
-- ── What changes ─────────────────────────────────────────────────────────
--
--   * private.apply_plan_edit_changes(owner, ...) is apply_ai_plan_edits'
--     body, unchanged apart from taking the plan owner as an argument and
--     returning the plans it touched instead of notifying. It is SECURITY
--     DEFINER and reachable by no client role: every read and write in it is
--     already filtered on the owner (the plan by user_id, the following plans
--     by user_id, each workout and week by membership of those plans), which
--     is what kept the invoker version inside the caller's rows as well as
--     RLS did.
--   * apply_ai_plan_edits becomes a SECURITY DEFINER wrapper that passes
--     auth.uid() and notifies the assigning coach as before. Its signature,
--     bounds and errors are the same.
--   * plan_change_requests: one row per suggested change, readable by its
--     athlete and its coach and written only by the four RPCs below.
--   * propose_plan_change: the athlete, on a plan an active coach assigned
--     them. The change set is applied inside a subtransaction and rolled back,
--     so a request the checks would refuse is refused now rather than when the
--     coach approves it. A newer request for the same plan withdraws the
--     older pending one. The coach gets a 'plan_change_request' notification.
--   * decide_plan_change: the coach, while the link is active. Approve applies
--     the chosen lines (all by default) to the athlete's plan; decline applies
--     nothing. The athlete gets a 'plan_change_decision' notification.
--   * withdraw_plan_change / apply_plan_change_myself: the athlete. The
--     second applies the request without the coach and tells the coach
--     ('plan_ai_edit', as a direct apply does).
--
-- ── Locks ────────────────────────────────────────────────────────────────
--
-- The CHECK swap takes a brief ACCESS EXCLUSIVE on notifications with no scan
-- (NOT VALID); 20271115002383 validates it in its own transaction. The table
-- is new and empty. The functions are catalogue-only.

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
      'personal_record',
      'club_join_request', 'club_join_approved', 'event_updated',
      'plan_change_request', 'plan_change_decision'
    )
  )
  not valid;

create table plan_change_requests (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references training_plans(id) on delete cascade,
  athlete_id uuid not null references auth.users(id) on delete cascade,
  coach_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'declined', 'withdrawn', 'overridden')),
  include_following boolean not null default false,
  workouts jsonb not null default '[]'::jsonb check (jsonb_typeof(workouts) = 'array'),
  weeks jsonb not null default '[]'::jsonb check (jsonb_typeof(weeks) = 'array'),
  -- Set when the coach approved some of the lines: workouts and weeks then
  -- hold only what was applied.
  edited_by_coach boolean not null default false,
  coach_note text check (coach_note is null or char_length(coach_note) between 1 and 500),
  created_at timestamptz not null default now(),
  decided_at timestamptz,
  check (athlete_id <> coach_id),
  check ((status = 'pending') = (decided_at is null))
);

create unique index plan_change_requests_one_pending
  on plan_change_requests (plan_id) where status = 'pending';
create index plan_change_requests_plan_id on plan_change_requests (plan_id);
create index plan_change_requests_athlete_id on plan_change_requests (athlete_id, created_at desc);
create index plan_change_requests_coach_id on plan_change_requests (coach_id, created_at desc);

alter table plan_change_requests enable row level security;

create policy "athlete and coach read their plan change requests"
  on plan_change_requests for select
  to authenticated
  using ((select auth.uid()) = athlete_id or (select auth.uid()) = coach_id);

revoke all on public.plan_change_requests from anon, authenticated;
grant select on public.plan_change_requests to authenticated;
grant select, insert, update, delete on public.plan_change_requests to service_role;

-- apply_ai_plan_edits' body (20271021000050), taking the owner as an argument.
create or replace function private.apply_plan_edit_changes(
  p_owner uuid,
  p_plan_id uuid,
  p_today date,
  p_include_following boolean,
  p_workouts jsonb,
  p_weeks jsonb
)
returns uuid[]
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := p_owner;
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
      message = 'apply_ai_plan_edits: no plan owner';
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

  return touched;
end;
$$;
revoke execute on function private.apply_plan_edit_changes(uuid, uuid, date, boolean, jsonb, jsonb)
  from public, anon, authenticated;

create or replace function public.apply_ai_plan_edits(
  p_plan_id uuid,
  p_today date,
  p_include_following boolean,
  p_workouts jsonb,
  p_weeks jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  v_plan uuid;
begin
  if caller is null then
    raise exception using
      errcode = 'insufficient_privilege',
      message = 'apply_ai_plan_edits: not authenticated';
  end if;
  foreach v_plan in array private.apply_plan_edit_changes(
    caller, p_plan_id, p_today, p_include_following, p_workouts, p_weeks
  ) loop
    perform private.notify_coach_of_ai_plan_edit(v_plan);
  end loop;
end;
$$;

revoke execute on function public.apply_ai_plan_edits(uuid, date, boolean, jsonb, jsonb) from public, anon;
grant execute on function public.apply_ai_plan_edits(uuid, date, boolean, jsonb, jsonb) to authenticated;

create or replace function public.propose_plan_change(
  p_plan_id uuid,
  p_today date,
  p_include_following boolean,
  p_workouts jsonb,
  p_weeks jsonb
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  v_coach uuid;
  v_id uuid;
begin
  if caller is null then
    raise exception using
      errcode = 'insufficient_privilege',
      message = 'propose_plan_change: not authenticated';
  end if;

  select tp.assigned_by_coach_id into v_coach
  from training_plans tp
  where tp.id = p_plan_id and tp.user_id = caller
  for update;
  if not found then
    raise exception using
      errcode = 'no_data_found',
      message = format('propose_plan_change: plan %s not found', p_plan_id);
  end if;
  if v_coach is null or v_coach = caller
     or not private.is_active_coach_of(v_coach, caller) then
    raise exception using
      errcode = 'insufficient_privilege',
      message = 'propose_plan_change: the plan has no coach you are linked with';
  end if;
  if p_include_following is null
     or p_workouts is null or jsonb_typeof(p_workouts) <> 'array'
     or p_weeks is null or jsonb_typeof(p_weeks) <> 'array' then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = 'propose_plan_change: a scope and two lists of changes are required';
  end if;
  if jsonb_array_length(p_workouts) + jsonb_array_length(p_weeks) = 0 then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = 'propose_plan_change: nothing to change';
  end if;

  -- Run the change set and undo it, so whatever the apply would refuse is
  -- refused here with its own error. TK382 is this function's own signal.
  begin
    perform private.apply_plan_edit_changes(
      caller, p_plan_id, p_today, p_include_following, p_workouts, p_weeks);
    raise exception using errcode = 'TK382', message = 'propose_plan_change: dry run';
  exception when sqlstate 'TK382' then
    null;
  end;

  update plan_change_requests
  set status = 'withdrawn', decided_at = now()
  where plan_id = p_plan_id and status = 'pending';

  insert into plan_change_requests (plan_id, athlete_id, coach_id, include_following, workouts, weeks)
  values (p_plan_id, caller, v_coach, p_include_following, p_workouts, p_weeks)
  returning id into v_id;

  update notifications
  set created_at = now()
  where user_id = v_coach and actor_id = caller and kind = 'plan_change_request'
    and plan_id = p_plan_id and read_at is null;
  if not found then
    insert into notifications (user_id, actor_id, kind, plan_id)
    values (v_coach, caller, 'plan_change_request', p_plan_id);
  end if;

  return v_id;
end;
$$;

revoke execute on function public.propose_plan_change(uuid, date, boolean, jsonb, jsonb) from public, anon;
grant execute on function public.propose_plan_change(uuid, date, boolean, jsonb, jsonb) to authenticated;

-- The coach decides. p_workout_ids / p_week_ids pick the lines to approve
-- (null = every line); each must be a line of the request.
create or replace function public.decide_plan_change(
  p_request_id uuid,
  p_approve boolean,
  p_today date,
  p_workout_ids uuid[] default null,
  p_week_ids uuid[] default null,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  req plan_change_requests%rowtype;
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  v_workouts jsonb := '[]'::jsonb;
  v_weeks jsonb := '[]'::jsonb;
  v_edited boolean := false;
begin
  if caller is null then
    raise exception using
      errcode = 'insufficient_privilege',
      message = 'decide_plan_change: not authenticated';
  end if;
  if p_approve is null then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = 'decide_plan_change: approve or decline';
  end if;
  if v_note is not null and char_length(v_note) > 500 then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = 'decide_plan_change: the note is longer than 500 characters';
  end if;

  select * into req from plan_change_requests
  where id = p_request_id and coach_id = caller
  for update;
  if not found then
    raise exception using
      errcode = 'no_data_found',
      message = format('decide_plan_change: request %s not found', p_request_id);
  end if;
  if req.status <> 'pending' then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = 'decide_plan_change: the request is no longer pending';
  end if;
  if not private.is_active_coach_of(caller, req.athlete_id) then
    raise exception using
      errcode = 'insufficient_privilege',
      message = 'decide_plan_change: you no longer coach this athlete';
  end if;

  if p_approve then
    if p_workout_ids is null then
      v_workouts := req.workouts;
    else
      if exists (
        select 1 from unnest(p_workout_ids) i
        where not exists (
          select 1 from jsonb_array_elements(req.workouts) w where (w->>'id')::uuid = i)
      ) then
        raise exception using
          errcode = 'invalid_parameter_value',
          message = 'decide_plan_change: a chosen workout is not in the request';
      end if;
      select coalesce(jsonb_agg(t.w order by t.o), '[]'::jsonb) into v_workouts
      from jsonb_array_elements(req.workouts) with ordinality as t(w, o)
      where (t.w->>'id')::uuid = any (p_workout_ids);
    end if;
    if p_week_ids is null then
      v_weeks := req.weeks;
    else
      if exists (
        select 1 from unnest(p_week_ids) i
        where not exists (
          select 1 from jsonb_array_elements(req.weeks) w where (w->>'id')::uuid = i)
      ) then
        raise exception using
          errcode = 'invalid_parameter_value',
          message = 'decide_plan_change: a chosen week is not in the request';
      end if;
      select coalesce(jsonb_agg(t.w order by t.o), '[]'::jsonb) into v_weeks
      from jsonb_array_elements(req.weeks) with ordinality as t(w, o)
      where (t.w->>'id')::uuid = any (p_week_ids);
    end if;
    if jsonb_array_length(v_workouts) + jsonb_array_length(v_weeks) = 0 then
      raise exception using
        errcode = 'invalid_parameter_value',
        message = 'decide_plan_change: approve at least one change, or decline';
    end if;
    v_edited := jsonb_array_length(v_workouts) <> jsonb_array_length(req.workouts)
             or jsonb_array_length(v_weeks) <> jsonb_array_length(req.weeks);

    perform private.apply_plan_edit_changes(
      req.athlete_id, req.plan_id, p_today, req.include_following, v_workouts, v_weeks);

    update plan_change_requests
    set status = 'approved', decided_at = now(), coach_note = v_note,
        workouts = v_workouts, weeks = v_weeks, edited_by_coach = v_edited
    where id = req.id;
  else
    update plan_change_requests
    set status = 'declined', decided_at = now(), coach_note = v_note
    where id = req.id;
  end if;

  update notifications
  set read_at = now()
  where user_id = caller and actor_id = req.athlete_id and kind = 'plan_change_request'
    and plan_id = req.plan_id and read_at is null;

  insert into notifications (user_id, actor_id, kind, plan_id)
  values (req.athlete_id, caller, 'plan_change_decision', req.plan_id);
end;
$$;

revoke execute on function public.decide_plan_change(uuid, boolean, date, uuid[], uuid[], text) from public, anon;
grant execute on function public.decide_plan_change(uuid, boolean, date, uuid[], uuid[], text) to authenticated;

create or replace function public.withdraw_plan_change(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  req plan_change_requests%rowtype;
begin
  if caller is null then
    raise exception using
      errcode = 'insufficient_privilege',
      message = 'withdraw_plan_change: not authenticated';
  end if;
  select * into req from plan_change_requests
  where id = p_request_id and athlete_id = caller
  for update;
  if not found then
    raise exception using
      errcode = 'no_data_found',
      message = format('withdraw_plan_change: request %s not found', p_request_id);
  end if;
  if req.status <> 'pending' then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = 'withdraw_plan_change: the request is no longer pending';
  end if;

  update plan_change_requests
  set status = 'withdrawn', decided_at = now()
  where id = req.id;

  delete from notifications
  where user_id = req.coach_id and actor_id = caller and kind = 'plan_change_request'
    and plan_id = req.plan_id and read_at is null;
end;
$$;

revoke execute on function public.withdraw_plan_change(uuid) from public, anon;
grant execute on function public.withdraw_plan_change(uuid) to authenticated;

-- The athlete owns the plan, so they may apply their own request without the
-- coach. The coach is told through the same 'plan_ai_edit' notice a direct
-- apply sends.
create or replace function public.apply_plan_change_myself(p_request_id uuid, p_today date)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  req plan_change_requests%rowtype;
  v_plan uuid;
begin
  if caller is null then
    raise exception using
      errcode = 'insufficient_privilege',
      message = 'apply_plan_change_myself: not authenticated';
  end if;
  select * into req from plan_change_requests
  where id = p_request_id and athlete_id = caller
  for update;
  if not found then
    raise exception using
      errcode = 'no_data_found',
      message = format('apply_plan_change_myself: request %s not found', p_request_id);
  end if;
  if req.status <> 'pending' then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = 'apply_plan_change_myself: the request is no longer pending';
  end if;

  foreach v_plan in array private.apply_plan_edit_changes(
    caller, req.plan_id, p_today, req.include_following, req.workouts, req.weeks
  ) loop
    perform private.notify_coach_of_ai_plan_edit(v_plan);
  end loop;

  update plan_change_requests
  set status = 'overridden', decided_at = now()
  where id = req.id;

  delete from notifications
  where user_id = req.coach_id and actor_id = caller and kind = 'plan_change_request'
    and plan_id = req.plan_id and read_at is null;
end;
$$;

revoke execute on function public.apply_plan_change_myself(uuid, date) from public, anon;
grant execute on function public.apply_plan_change_myself(uuid, date) to authenticated;
