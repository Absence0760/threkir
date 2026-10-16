-- duplicate_plan_week no longer copies a week's race workouts (decisions
-- § 2009 follow-up). The copy dropped race_name / race_priority so a
-- duplicated race week would not name a second race, but it still copied the
-- workout as kind 'race', and planRaces reads every race workout as a race:
-- the nameless copy became a C race seven days later (or the A race, when it
-- landed on the new end date), with its own countdown and a B/C taper window.
-- A duplicated week is training, so its race day stays free, and the copy's
-- target volume drops the race distance it no longer holds.
--
-- Re-emitted whole from its latest body (20270830000007); CREATE OR REPLACE
-- keeps the signature and grants, restated below all the same.

CREATE OR REPLACE FUNCTION public.duplicate_plan_week(p_plan_id uuid, p_week_index integer)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  caller        uuid := auth.uid();
  v_plan        training_plans%rowtype;
  v_src         plan_weeks%rowtype;
  v_new_week_id uuid;
  workout_record record;
begin
  if caller is null then
    raise exception 'duplicate_plan_week: not authenticated';
  end if;

  select * into v_plan from training_plans where id = p_plan_id;
  if not found then
    raise exception 'duplicate_plan_week: plan % not found', p_plan_id;
  end if;

  -- Owner-only. Club members can read a template's weeks but only the
  -- owner restructures it.
  if v_plan.user_id <> caller then
    raise exception 'duplicate_plan_week: not authorised to edit plan %', p_plan_id;
  end if;

  select * into v_src from plan_weeks
    where plan_id = p_plan_id and week_index = p_week_index;
  if not found then
    raise exception 'duplicate_plan_week: week % not found in plan %',
      p_week_index, p_plan_id;
  end if;

  -- Push the workouts of every later week back by 7 days. Done BEFORE
  -- the re-index (while the tail is still the only thing past
  -- p_week_index) and BEFORE the copy exists, so the new week's
  -- workouts aren't caught by this shift.
  update plan_workouts
    set scheduled_date = scheduled_date + 7
    where week_id in (
      select id from plan_weeks
      where plan_id = p_plan_id and week_index > p_week_index
    );

  -- Make room at p_week_index + 1 by bumping every later week up one. The
  -- unique constraint is checked per row, so a single statement transiently
  -- collides; it is DEFERRABLE INITIALLY IMMEDIATE as of this migration and is
  -- deferred for the span of the renumber, then set back to immediate so a
  -- duplicate raises HERE rather than at COMMIT. This replaces a hop through
  -- negative index space, which worked but made `week_index >= 0` unstatable.
  set constraints plan_weeks_plan_id_week_index_key deferred;
  update plan_weeks set week_index = week_index + 1
    where plan_id = p_plan_id and week_index > p_week_index;
  set constraints plan_weeks_plan_id_week_index_key immediate;

  insert into plan_weeks (plan_id, week_index, phase, target_volume_m, notes)
    values (
      p_plan_id, p_week_index + 1, v_src.phase,
      -- The race workouts stay behind, so their distance leaves the copy's
      -- volume with them.
      case when v_src.target_volume_m is null then null
           else greatest(0, v_src.target_volume_m - coalesce((
             select sum(wo.target_distance_m) from plan_workouts wo
             where wo.week_id = v_src.id and wo.kind = 'race'
           ), 0))
      end,
      v_src.notes
    )
    returning id into v_new_week_id;

  for workout_record in
    select * from plan_workouts where week_id = v_src.id and kind <> 'race'
  loop
    insert into plan_workouts (
      week_id, scheduled_date, kind, target_distance_m, target_duration_seconds,
      target_pace_sec_per_km, target_pace_end_sec_per_km, target_pace_tolerance_sec,
      pace_zone, structure, notes, race_taper_applied_at
    )
    values (
      v_new_week_id,
      workout_record.scheduled_date + 7,
      workout_record.kind,
      workout_record.target_distance_m,
      workout_record.target_duration_seconds,
      workout_record.target_pace_sec_per_km,
      workout_record.target_pace_end_sec_per_km,
      workout_record.target_pace_tolerance_sec,
      workout_record.pace_zone,
      workout_record.structure,
      workout_record.notes,
      workout_record.race_taper_applied_at
    );
  end loop;

  update training_plans
    set end_date = end_date + 7, updated_at = now()
    where id = p_plan_id;

  return v_new_week_id;
end;
$function$;

revoke execute on function public.duplicate_plan_week(uuid, integer) from public, anon;
grant execute on function public.duplicate_plan_week(uuid, integer) to authenticated;
grant execute on function public.duplicate_plan_week(uuid, integer) to service_role;
