-- A plan points at its own library copy, and the copy carries the design only
-- (decisions § 2340, reversing the direction § 2289 rejected).
--
-- ── A. The link moves to the source plan ───────────────────────────────────
--
-- 20271105120001 linked a public-library copy to the plan it came from with
-- training_plans.published_from_plan_id ON THE COPY. A copy is a public row,
-- and RLS has no column dimension (20270508_001), so every signed-in reader
-- of the library could read the uuid of the publisher's private plan. The link
-- now lives on the SOURCE plan as library_copy_id:
--   * owner-only in practice: a non-template plan is readable by its owner
--     and by the owner's active coaches (20261116_001), never by a library or
--     club reader. A template never carries one (strip_template_private_fields
--     nulls it), so a public or club row cannot expose it either.
--   * on delete set null: unpublishing deletes the copy, and the source goes
--     back to showing Publish. § 2289 rejected this direction because a copy
--     deleted from the library page would leave the source pointing at
--     nothing; the FK action is what answers that.
--   * unique where not null: one copy per plan, and the FK's covering index.
--   * written by publish_plan_to_library only, and frozen against anon /
--     authenticated writes in freeze_training_plan_managed_columns, so a
--     client cannot point its plan at somebody else's library entry.
-- Backfilled from every existing published_from_plan_id, then that column and
-- its backfill function are dropped.
--
-- ── B. A library copy keeps the plan's design, not the publisher's data ────
--
-- § 2262 kept a logged-out reader to a redacted projection; a signed-in
-- library reader still read whole rows: the publisher's real calendar dates,
-- every absolute pace (derived from their own VDOT or goal), their goal time,
-- and every note they wrote. A library copy now holds:
--   kept     name, goal event + distance, days per week, source, rules (the
--            structured plan-wide design the adaptive re-plan reads), every
--            week's index / phase / volume, every workout's kind, distance,
--            pace ZONE, RPE range, race priority, its day within the plan,
--            and its structure (reps, rep and recovery distances, recovery
--            effort labels).
--   dropped  goal_time_seconds; target_pace_sec_per_km / _end_ / _tolerance_;
--            every pace_sec_per_km inside structure; notes on the plan, week
--            and workout; race_name; a duration set beside a distance (the
--            two together are a pace), and a race workout's duration (it is
--            the goal time); the real dates — the copy is moved onto the
--            reference week of 2001-01-01 (a Monday), keeping the weekday
--            each day falls on, so a cloner's plan lays out the same way and
--            clone_public_plan's start-date shift works unchanged.
-- The field rules are triggers on all three tables, so they hold for every
-- writer, service_role included. The date move needs the source's start date,
-- so it happens in publish_plan_to_library, and a client role may no longer
-- create a public template (or flip a plan public) any other way: an old
-- client build's direct insert is refused rather than publishing real dates.
-- Existing copies are redacted and moved in place below.
--
-- Locks: training_plans / plan_weeks / plan_workouts are per-runner tables,
-- not among the high-volume tables check_migration_online_safety.mjs guards.
-- ADD COLUMN of a nullable column with no default is a catalogue change; the
-- FK's validation reads training_plans once against a column null in every
-- row. The unique index is partial on non-null rows. The backfills touch only
-- public templates and their children (one plan per publish action) under
-- per-row locks. DROP COLUMN is a catalogue change.

-- Keep `extensions` on the path so the seed step that follows still sees PostGIS.
set search_path = public, extensions;

-- ── A. library_copy_id ──────────────────────────────────────────────────────

alter table training_plans
  add column library_copy_id uuid references training_plans (id) on delete set null;

create unique index training_plans_library_copy_id_key
  on training_plans (library_copy_id)
  where library_copy_id is not null;

comment on column training_plans.library_copy_id is
  'The owner''s public-library copy of this plan. Written by '
  'publish_plan_to_library only; null on every template. decisions § 2340.';

-- The newest copy wins when one source was published twice.
update training_plans src
   set library_copy_id = c.id
  from (
    select distinct on (published_from_plan_id) id, published_from_plan_id, user_id
      from training_plans
     where published_from_plan_id is not null
       and is_public_template = true
     order by published_from_plan_id, created_at desc, id
  ) c
 where src.id = c.published_from_plan_id
   and src.user_id = c.user_id
   and coalesce(src.is_template, false) = false;

drop function if exists private.backfill_training_plan_published_from();
alter table training_plans drop column published_from_plan_id;

create or replace function private.strip_template_private_fields()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if NEW.is_template = true then
    NEW.vdot := null;
    NEW.current_5k_seconds := null;
    NEW.notes := null;
    NEW.race_listing_id := null;
    NEW.library_copy_id := null;
  end if;
  if NEW.is_public_template = true then
    NEW.goal_time_seconds := null;
  end if;
  return NEW;
end;
$$;

create or replace function freeze_training_plan_managed_columns()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user not in ('anon', 'authenticated') then
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.source_author_id := null;
    new.library_copy_id := null;
    if new.is_public_template then
      raise exception using
        errcode = 'insufficient_privilege',
        message = 'training_plans: publish to the library with publish_plan_to_library';
    end if;
  else
    new.source_author_id := old.source_author_id;
    new.library_copy_id := old.library_copy_id;
    if new.is_public_template and not coalesce(old.is_public_template, false) then
      raise exception using
        errcode = 'insufficient_privilege',
        message = 'training_plans: publish to the library with publish_plan_to_library';
    end if;
  end if;
  return new;
end;
$$;

-- ── B. The redaction ────────────────────────────────────────────────────────

-- `structure` without its absolute paces: every pace_sec_per_km key goes, and
-- a duration beside a distance in the same block goes with it.
create or replace function private.redact_plan_structure(p jsonb)
returns jsonb
language plpgsql
immutable
set search_path = public, pg_catalog
as $$
declare
  v_out jsonb;
begin
  if p is null then
    return null;
  end if;
  if jsonb_typeof(p) = 'object' then
    select coalesce(jsonb_object_agg(e.key, private.redact_plan_structure(e.value)), '{}'::jsonb)
      into v_out
      from jsonb_each(p) e
     where e.key <> 'pace_sec_per_km'
       and not (e.key = 'duration_s' and p ? 'distance_m')
       and not (e.key = 'recovery_duration_s' and p ? 'recovery_distance_m');
    return v_out;
  end if;
  if jsonb_typeof(p) = 'array' then
    select coalesce(jsonb_agg(private.redact_plan_structure(a.value) order by a.ord), '[]'::jsonb)
      into v_out
      from jsonb_array_elements(p) with ordinality a(value, ord);
    return v_out;
  end if;
  return p;
end;
$$;

revoke execute on function private.redact_plan_structure(jsonb) from public, anon, authenticated;

create or replace function private.redact_public_template_workout()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
begin
  if not exists (
    select 1 from plan_weeks w
      join training_plans p on p.id = w.plan_id
     where w.id = new.week_id
       and p.is_public_template = true
  ) then
    return new;
  end if;
  new.target_pace_sec_per_km := null;
  new.target_pace_end_sec_per_km := null;
  new.target_pace_tolerance_sec := null;
  new.notes := null;
  new.race_name := null;
  if new.target_distance_m is not null or new.kind = 'race' then
    new.target_duration_seconds := null;
  end if;
  new.structure := private.redact_plan_structure(new.structure);
  return new;
end;
$$;

revoke execute on function private.redact_public_template_workout() from public, anon, authenticated;

create trigger plan_workouts_redact_public_template
  before insert or update on plan_workouts
  for each row execute function private.redact_public_template_workout();

create or replace function private.redact_public_template_week()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
begin
  if new.notes is not null and exists (
    select 1 from training_plans p
     where p.id = new.plan_id
       and p.is_public_template = true
  ) then
    new.notes := null;
  end if;
  return new;
end;
$$;

revoke execute on function private.redact_public_template_week() from public, anon, authenticated;

create trigger plan_weeks_redact_public_template
  before insert or update on plan_weeks
  for each row execute function private.redact_public_template_week();

-- A plan made public by a non-client writer (a restore) redacts what it
-- already holds; the two triggers above take it from there. Touching a row
-- is enough to run them.
create or replace function private.redact_public_template_children()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
begin
  update plan_weeks set notes = null where plan_id = new.id and notes is not null;
  update plan_workouts pw
     set structure = pw.structure
    from plan_weeks w
   where pw.week_id = w.id
     and w.plan_id = new.id;
  return null;
end;
$$;

revoke execute on function private.redact_public_template_children() from public, anon, authenticated;

create trigger training_plans_redact_public_template_children
  after update of is_public_template on training_plans
  for each row
  when (new.is_public_template and not coalesce(old.is_public_template, false))
  execute function private.redact_public_template_children();

-- The day a copy's dates are moved onto: the reference week's day with the
-- same ISO weekday as the source's start.
create or replace function private.library_copy_start(p_start date)
returns date
language sql
immutable
set search_path = public, pg_catalog
as $$
  select date '2001-01-01' + (extract(isodow from p_start)::int - 1);
$$;

revoke execute on function private.library_copy_start(date) from public, anon, authenticated;

-- ── Publish ─────────────────────────────────────────────────────────────────

create or replace function public.publish_plan_to_library(p_plan_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public, private, pg_catalog
as $$
declare
  caller uuid := auth.uid();
  src training_plans%rowtype;
  v_copy_id uuid;
  v_shift int;
  v_week record;
  v_new_week uuid;
begin
  if caller is null then
    raise exception using errcode = '28000', message = 'publish_plan_to_library: not authenticated';
  end if;

  select * into src
    from training_plans
   where id = p_plan_id
     and user_id = caller
     and coalesce(is_template, false) = false
   for update;
  if not found then
    raise exception using errcode = 'P0002', message = 'publish_plan_to_library: plan not found';
  end if;

  -- A second tap returns the copy the first one made.
  if src.library_copy_id is not null then
    return src.library_copy_id;
  end if;

  v_shift := private.library_copy_start(src.start_date) - src.start_date;

  insert into training_plans (
    user_id, name, goal_event, goal_distance_m, goal_time_seconds,
    start_date, end_date, days_per_week, vdot, current_5k_seconds,
    status, notes, is_template, is_public_template, club_id,
    parent_template_id, source, rules
  )
  values (
    caller, src.name, src.goal_event, src.goal_distance_m, null,
    src.start_date + v_shift, src.end_date + v_shift, src.days_per_week, null, null,
    'completed', null, true, true, null,
    null, coalesce(src.source, 'manual'), src.rules
  )
  returning id into v_copy_id;

  for v_week in
    select * from plan_weeks where plan_id = src.id order by week_index
  loop
    insert into plan_weeks (plan_id, week_index, phase, target_volume_m, notes)
    values (v_copy_id, v_week.week_index, v_week.phase, v_week.target_volume_m, null)
    returning id into v_new_week;

    -- The redaction trigger drops paces, notes, race names and paired
    -- durations; only the design columns are named here at all.
    insert into plan_workouts (
      week_id, scheduled_date, kind, target_distance_m, target_duration_seconds,
      pace_zone, structure, race_priority, race_taper_applied_at,
      target_rpe_min, target_rpe_max
    )
    select v_new_week, wo.scheduled_date + v_shift, wo.kind, wo.target_distance_m,
           wo.target_duration_seconds, wo.pace_zone, wo.structure, wo.race_priority,
           wo.race_taper_applied_at + make_interval(days => v_shift),
           wo.target_rpe_min, wo.target_rpe_max
      from plan_workouts wo
     where wo.week_id = v_week.id;
  end loop;

  update training_plans set library_copy_id = v_copy_id where id = src.id;

  return v_copy_id;
end;
$$;

revoke execute on function public.publish_plan_to_library(uuid) from public, anon;
grant execute on function public.publish_plan_to_library(uuid) to authenticated, service_role;

comment on function public.publish_plan_to_library(uuid) is
  'Publish the caller''s own plan to the public library: a redacted copy (no '
  'dates, paces, goal time or notes) linked from the source''s '
  'library_copy_id, in one transaction. decisions § 2340.';

-- ── Existing copies ─────────────────────────────────────────────────────────

-- Redact first (a no-op update runs the triggers), then move the dates.
update plan_weeks w
   set notes = null
  from training_plans p
 where p.id = w.plan_id
   and p.is_public_template = true
   and w.notes is not null;

update plan_workouts pw
   set structure = pw.structure
  from plan_weeks w
  join training_plans p on p.id = w.plan_id
 where pw.week_id = w.id
   and p.is_public_template = true;

update plan_workouts pw
   set scheduled_date = pw.scheduled_date + (private.library_copy_start(p.start_date) - p.start_date),
       race_taper_applied_at = pw.race_taper_applied_at
         + make_interval(days => private.library_copy_start(p.start_date) - p.start_date)
  from plan_weeks w
  join training_plans p on p.id = w.plan_id
 where pw.week_id = w.id
   and p.is_public_template = true
   and p.start_date <> private.library_copy_start(p.start_date);

update training_plans p
   set start_date = private.library_copy_start(p.start_date),
       end_date = p.end_date + (private.library_copy_start(p.start_date) - p.start_date),
       goal_time_seconds = null
 where p.is_public_template = true
   and (p.start_date <> private.library_copy_start(p.start_date) or p.goal_time_seconds is not null);
