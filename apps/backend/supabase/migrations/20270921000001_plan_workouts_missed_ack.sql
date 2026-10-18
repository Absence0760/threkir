-- "Ask once" about a missed workout (issue #1186, decisions § 2122).
--
-- The Today card on Home and plan detail asks the runner about their most
-- recent missed workout: "Make it up" for a long run the engine would make up
-- (the stretched next long run, previewed and accepted like any re-plan),
-- "Let it go" for everything else. Either answer is asked once per miss and
-- must hold on every device, so it is stored on the workout, not in a
-- browser or on a phone.
--
-- `missed_ack_at` is when the runner answered. It is null on every copy:
-- create_training_plan, clone_plan_template, clone_public_plan,
-- assign_plan_to_athlete, duplicate_plan_week, restart_training_plan and
-- change_plan_race_date all insert with explicit column lists, so a new
-- column takes its default there and a restarted or cloned plan starts with
-- no answers. A workout moved to another date (resume, race-date change, a
-- move or swap, a hand edit) is a different session from the one that was
-- missed, so the move clears its answer; if the new date passes too, it is
-- asked about again.
--
-- answer_missed_workouts records an answer, and for "Make it up" applies the
-- previewed make-up in the same transaction through
-- apply_workout_adjustments, so the stretch and the answer land together or
-- not at all. It refuses a workout that is not missed: rest, done, skipped,
-- or dated after the UTC today. The client decides "missed" on the runner's
-- local day, which is never ahead of the UTC date by more than one, so a
-- workout the client calls missed is always on or before the UTC today; the
-- check is a sanity bound, not the missed rule. SECURITY INVOKER: RLS and the
-- owner check below keep it to the plan's owner, so a coach cannot answer for
-- an athlete.
--
-- Online-safe: a nullable column with no default is a catalog-only change,
-- and CREATE TRIGGER takes a brief SHARE ROW EXCLUSIVE lock and rewrites
-- nothing.

alter table plan_workouts add column missed_ack_at timestamptz;

comment on column plan_workouts.missed_ack_at is
  'When the runner answered the missed-workout prompt (make it up or let it '
  'go) for this workout. Null until answered, on every copy, and again when '
  'the workout moves to another date.';

create or replace function private.clear_missed_ack_on_reschedule()
returns trigger
language plpgsql
set search_path = public, pg_catalog
as $$
begin
  new.missed_ack_at := null;
  return new;
end;
$$;

revoke execute on function private.clear_missed_ack_on_reschedule() from public, anon, authenticated;

create trigger plan_workouts_clear_missed_ack
  before update of scheduled_date on plan_workouts
  for each row
  when (old.scheduled_date is distinct from new.scheduled_date
        and old.missed_ack_at is not null)
  execute function private.clear_missed_ack_on_reschedule();

create or replace function public.answer_missed_workouts(
  p_plan_id uuid,
  p_workout_ids uuid[],
  p_changes jsonb default '[]'::jsonb
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  caller uuid := auth.uid();
  v_status text;
  v_template boolean;
  v_found integer;
begin
  if caller is null then
    raise exception 'answer_missed_workouts: not authenticated';
  end if;
  if p_workout_ids is null or cardinality(p_workout_ids) = 0 then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = 'answer_missed_workouts: name at least one workout';
  end if;

  select tp.status, coalesce(tp.is_template, false)
    into v_status, v_template
  from training_plans tp
  where tp.id = p_plan_id and tp.user_id = caller
  for update;
  if not found then
    raise exception 'answer_missed_workouts: plan % not found', p_plan_id;
  end if;
  if v_template or v_status <> 'active' then
    raise exception using
      errcode = 'object_not_in_prerequisite_state',
      message = 'answer_missed_workouts: the plan is not active';
  end if;

  select count(*) into v_found
  from plan_workouts wo
  join plan_weeks w on w.id = wo.week_id
  where wo.id = any (p_workout_ids)
    and w.plan_id = p_plan_id
    and wo.kind <> 'rest'
    and wo.completed_run_id is null
    and not wo.manually_completed
    and wo.skipped_at is null
    and wo.scheduled_date <= current_date;
  if v_found <> (select count(distinct x) from unnest(p_workout_ids) x) then
    raise exception using
      errcode = 'object_not_in_prerequisite_state',
      message = 'answer_missed_workouts: a workout is not a missed workout of this plan';
  end if;

  if p_changes is not null
     and jsonb_typeof(p_changes) = 'array'
     and jsonb_array_length(p_changes) > 0 then
    perform public.apply_workout_adjustments(p_plan_id, p_changes);
  elsif p_changes is not null and jsonb_typeof(p_changes) <> 'array' then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = 'answer_missed_workouts: changes must be a list';
  end if;

  update plan_workouts
  set missed_ack_at = coalesce(missed_ack_at, now())
  where id = any (p_workout_ids);
end;
$$;

revoke execute on function public.answer_missed_workouts(uuid, uuid[], jsonb) from public, anon;
grant execute on function public.answer_missed_workouts(uuid, uuid[], jsonb) to authenticated;
