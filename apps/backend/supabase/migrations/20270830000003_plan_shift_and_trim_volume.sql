-- Plan chaining follow-ups (decisions § 2042).
--
-- shift_training_plan moves a plan's workouts and dates in ONE transaction.
-- The web "Shift dates" action used to update every workout row and then the
-- plan row from the client; once plans can be queued back to back, that last
-- update can fail on training_plans_active_no_overlap after every workout has
-- already moved, leaving the plan's rows and its dates disagreeing. With
-- p_shift_following the active plans queued after it move by the same number
-- of days, processed latest-first on a forward shift so no intermediate state
-- overlaps. A shift that would still overlap fails whole (23P01), nothing moved.
--
-- trim_training_plan is re-emitted whole for three fixes. The week it cuts
-- through keeps a target volume matching the workouts it still holds (it kept
-- the full week's figure, which the adherence banner then graded against). It
-- refuses to delete a workout the runner already completed, which a cut in the
-- past would otherwise do. And it stamps training_plans.trimmed_at: a trimmed
-- plan's goal race no longer happens inside it, so planRaces must not invent
-- an implicit A race on the new end date.

alter table training_plans add column trimmed_at timestamptz;

create or replace function public.shift_training_plan(
  p_plan_id uuid,
  p_days integer,
  p_shift_following boolean default false
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  plan_row training_plans%rowtype;
  target record;
begin
  if auth.uid() is null then
    raise exception 'shift_training_plan: not authenticated';
  end if;
  if p_days is null or abs(p_days) > 366 then
    raise exception 'shift_training_plan: shift must be between -366 and 366 days';
  end if;

  select * into plan_row
  from training_plans
  where id = p_plan_id and user_id = auth.uid()
  for update;
  if not found then
    raise exception 'shift_training_plan: plan % not found', p_plan_id;
  end if;
  if p_days = 0 then
    return;
  end if;

  for target in
    select tp.id
    from training_plans tp
    where tp.id = p_plan_id
       or (p_shift_following
           and tp.user_id = auth.uid()
           and tp.status = 'active'
           and not tp.is_template
           and tp.start_date > plan_row.end_date)
    order by
      case when p_days > 0 then tp.start_date end desc,
      case when p_days < 0 then tp.start_date end asc
  loop
    update plan_workouts wo
    set scheduled_date = wo.scheduled_date + p_days
    from plan_weeks w
    where wo.week_id = w.id and w.plan_id = target.id;

    update training_plans
    set start_date = start_date + p_days,
        end_date = end_date + p_days,
        updated_at = now()
    where id = target.id;
  end loop;
end;
$$;

revoke execute on function public.shift_training_plan(uuid, integer, boolean) from public, anon;
grant execute on function public.shift_training_plan(uuid, integer, boolean) to authenticated;

create or replace function public.trim_training_plan(p_plan_id uuid, p_new_end_date date)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  plan_row training_plans%rowtype;
begin
  if auth.uid() is null then
    raise exception 'trim_training_plan: not authenticated';
  end if;

  select * into plan_row
  from training_plans
  where id = p_plan_id and user_id = auth.uid()
  for update;
  if not found then
    raise exception 'trim_training_plan: plan % not found', p_plan_id;
  end if;

  if p_new_end_date < plan_row.start_date then
    raise exception 'trim_training_plan: new end date % is before the plan starts', p_new_end_date;
  end if;
  if p_new_end_date >= plan_row.end_date then
    return;
  end if;

  if exists (
    select 1 from plan_workouts wo
    join plan_weeks w on w.id = wo.week_id
    where w.plan_id = p_plan_id
      and wo.scheduled_date > p_new_end_date
      and (wo.completed_run_id is not null or wo.manually_completed)
  ) then
    raise exception 'trim_training_plan: completed workouts fall after %', p_new_end_date;
  end if;

  delete from plan_workouts wo
  using plan_weeks w
  where wo.week_id = w.id
    and w.plan_id = p_plan_id
    and wo.scheduled_date > p_new_end_date;

  delete from plan_weeks w
  where w.plan_id = p_plan_id
    and plan_row.start_date + w.week_index * 7 > p_new_end_date
    and not exists (select 1 from plan_workouts wo where wo.week_id = w.id);

  update plan_weeks w
  set target_volume_m = coalesce((
    select sum(wo.target_distance_m) from plan_workouts wo where wo.week_id = w.id
  ), 0)
  where w.plan_id = p_plan_id
    and p_new_end_date between plan_row.start_date + w.week_index * 7
                           and plan_row.start_date + w.week_index * 7 + 6
    and p_new_end_date < plan_row.start_date + w.week_index * 7 + 6;

  update training_plans
  set end_date = p_new_end_date, trimmed_at = now(), updated_at = now()
  where id = p_plan_id;
end;
$$;
