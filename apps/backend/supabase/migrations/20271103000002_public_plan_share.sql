-- "Train with me": a public plan anyone can open, and a copy that remembers
-- whose plan it started from (issue #1273 item 5, decisions § 2262).
--
-- A public-library plan (is_public_template, 20270126_001) is readable by
-- signed-in users only: its RLS policies are gated on auth.role() =
-- 'authenticated'. A creator who posts a link to their marathon block sends
-- followers to a page they cannot read. This adds a redacted anonymous view,
-- and keeps the author on the copy so the copy can say where it came from.
--
-- 1. private.public_plan_share_enabled() / public.public_plan_share_enabled():
--    a row in private.feature_flags that NO MIGRATION WRITES. Who can read a
--    published plan widens from signed-in users to anyone with the link, so
--    it waits on a CISO / Security Analyst review before it reaches real users
--    (§ 150); seed.sql opens it for local + CI. Enforced in SQL, so a client
--    cannot read past it, and the public reader is how both clients decide
--    whether to offer the share link.
--
-- 2. public.public_plan_share(p_id): SECURITY DEFINER, granted to anon. One
--    jsonb document: the plan's name, goal event and distance, days per week,
--    and every week with its workouts. It is built from a named column list,
--    so a column added to training_plans later is not published by default.
--    Withheld, and why:
--      * vdot, current_5k_seconds, every HR target: athlete physiology (a
--        template already holds none of them, 20270508_001 / 20270915000005;
--        withheld here too so the projection does not depend on that).
--      * goal_time_seconds and every absolute pace (target_pace_*, the
--        `structure` jsonb that repeats them): a pace on a published plan is
--        derived from the publisher's own VDOT, so it states their fitness.
--        The named pace_zone and the RPE range describe the session without it.
--      * notes on the plan, week and workout, and race_name: free text the
--        publisher wrote about their own training.
--      * Every calendar date. A workout is placed by its day offset from the
--        plan's start, so the page shows the block's shape and not the dates
--        the publisher ran it.
--      * user_id. The author is a display name and handle, and only when
--        private.profile_visible_to and the block check would show that
--        profile to this caller; otherwise null, and the plan still renders.
--    A shadow-hidden author's plans return null: moderation that hides the
--    account hides what it links to anonymously.
--
-- 3. training_plans.source_author_id: who wrote the public plan a copy
--    started from. clone_public_plan writes it; parent_template_id already
--    holds the plan itself, but that column is also written by a club clone
--    and a coach assignment, and is set null when the template is deleted, so
--    it cannot say "started from @creator" on its own. Set-null when the
--    author deletes their account. A copy of your own plan carries null.
--    Frozen against client writes (the 20270704000003 trigger shape), so a
--    runner cannot attribute their plan to someone else or inflate a
--    creator's start count.
--
-- 4. public.plan_started_from(p_plan_id): the caller's own copy's
--    attribution: the author's display name and handle under the same
--    visibility rule, and the template id while it is still public.
--
-- Locks: training_plans is a per-runner table, not one of the high-volume
-- tables check_migration_online_safety.mjs guards. ADD COLUMN of a nullable
-- column with no default is a catalogue change; the FK's validation reads the
-- table once against a column that is null in every row, and the covering
-- index is partial on the non-null rows, so it is built empty. Function and
-- trigger creation are catalogue-only.

-- ── 1. The gate ─────────────────────────────────────────────────────────────

create or replace function private.public_plan_share_enabled()
returns boolean
language sql
stable
security definer
set search_path = public, private
as $$
  select coalesce(
    (select f.enabled from private.feature_flags f where f.name = 'public_plan_share'),
    false
  );
$$;

revoke execute on function private.public_plan_share_enabled() from public;
grant execute on function private.public_plan_share_enabled() to anon, authenticated, service_role;

create or replace function public.public_plan_share_enabled()
returns boolean
language sql
stable
security definer
set search_path = public, private
as $$
  select private.public_plan_share_enabled();
$$;

revoke execute on function public.public_plan_share_enabled() from public;
grant execute on function public.public_plan_share_enabled() to anon, authenticated, service_role;

comment on function public.public_plan_share_enabled() is
  'Whether a public-library plan is readable anonymously at /share/plan/<id> '
  '(decisions § 2262). Clients hide the share link when false.';

-- ── 2. The attribution column ───────────────────────────────────────────────

alter table training_plans
  add column source_author_id uuid references auth.users (id) on delete set null;

create index training_plans_source_author_id_idx
  on training_plans (source_author_id)
  where source_author_id is not null;

comment on column training_plans.source_author_id is
  'Author of the public-library plan this copy started from. Written by '
  'clone_public_plan only; frozen against client writes. decisions § 2262.';

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
  else
    new.source_author_id := old.source_author_id;
  end if;
  return new;
end;
$$;

create trigger training_plans_freeze_managed_columns
  before insert or update on training_plans
  for each row execute function freeze_training_plan_managed_columns();

-- ── 3. clone_public_plan writes it ──────────────────────────────────────────
-- Full body carried forward from 20270912000001; only the insert's column
-- list and values gain source_author_id.

CREATE OR REPLACE FUNCTION public.clone_public_plan(template_id uuid, new_start_date date, p_overlap text DEFAULT 'replace'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  caller uuid := auth.uid();
  tmpl training_plans%rowtype;
  new_plan_id uuid;
  new_week_id uuid;
  date_offset_days int;
  week_record record;
  workout_record record;
  overlapped record;
begin
  if caller is null then
    raise exception 'clone_public_plan: not authenticated';
  end if;
  if p_overlap is null or p_overlap not in ('refuse', 'replace', 'trim') then
    raise exception using
      errcode = 'invalid_parameter_value',
      message = 'clone_public_plan: overlap must be refuse, replace or trim';
  end if;

  -- Anti-bulk-clone rate limit — same shape as clone_plan_template
  -- (20 clones / hour / caller). A caller with the public library list
  -- cannot loop-clone every public template UUID into their account.
  perform enforce_create_rate_limit('clone_public_plan', caller, 20, 3600);

  -- DEFINER context bypasses RLS, so this reads any public template
  -- regardless of caller. The is_public_template gate is the access check.
  select * into tmpl
  from training_plans
  where id = template_id
    and is_template = true
    and is_public_template = true;

  if not found then
    raise exception 'clone_public_plan: public template not found';
  end if;

  date_offset_days := new_start_date - tmpl.start_date;

  -- Resolve the active plans the new window overlaps per p_overlap, inside
  -- this transaction: a later failure rolls the resolution back with it.
  if exists (
    select 1 from training_plans
    where user_id = caller and status = 'active'
      and daterange(start_date, end_date, '[]') && daterange(new_start_date, tmpl.end_date + date_offset_days, '[]')
  ) then
    if p_overlap = 'refuse' then
      raise exception using
        errcode = 'exclusion_violation',
        message = 'clone_public_plan: these dates overlap an active training plan';
    elsif p_overlap = 'replace' then
      update training_plans
      set status = 'abandoned', updated_at = now()
      where user_id = caller
        and status = 'active'
        and daterange(start_date, end_date, '[]') && daterange(new_start_date, tmpl.end_date + date_offset_days, '[]');
    else
      if exists (
        select 1 from training_plans
        where user_id = caller and status = 'active'
          and daterange(start_date, end_date, '[]') && daterange(new_start_date, tmpl.end_date + date_offset_days, '[]')
          and start_date >= new_start_date
      ) then
        raise exception using
          errcode = 'exclusion_violation',
          message = 'clone_public_plan: an overlapping plan starts on or after the new start date, so it cannot be ended early';
      end if;
      for overlapped in
        select id from training_plans
        where user_id = caller and status = 'active'
          and daterange(start_date, end_date, '[]') && daterange(new_start_date, tmpl.end_date + date_offset_days, '[]')
      loop
        perform trim_training_plan(overlapped.id, new_start_date - 1);
      end loop;
    end if;
  end if;

  insert into training_plans (
    user_id, name, goal_event, goal_distance_m, goal_time_seconds,
    start_date, end_date, days_per_week, vdot, current_5k_seconds,
    status, notes, parent_template_id, is_template, is_public_template,
    source, rules, source_author_id
  )
  values (
    caller, tmpl.name, tmpl.goal_event, tmpl.goal_distance_m, tmpl.goal_time_seconds,
    new_start_date, tmpl.end_date + date_offset_days,
    tmpl.days_per_week,
    -- Publisher-private fitness data — never propagated to the clone.
    -- The clone owner sets their own VDOT via /plans/new.
    null, null,
    'active', tmpl.notes, template_id, false, false,
    tmpl.source, tmpl.rules,
    -- "Started from" attribution, and the start a creator can count. A runner
    -- copying their own plan started from nobody else.
    nullif(tmpl.user_id, caller)
  )
  returning id into new_plan_id;

  for week_record in
    select * from plan_weeks where plan_id = template_id order by week_index
  loop
    insert into plan_weeks (plan_id, week_index, phase, target_volume_m, notes)
    values (new_plan_id, week_record.week_index, week_record.phase,
            week_record.target_volume_m, week_record.notes)
    returning id into new_week_id;

    for workout_record in
      select * from plan_workouts where week_id = week_record.id
    loop
      insert into plan_workouts (
        week_id, scheduled_date, kind, target_distance_m, target_duration_seconds,
        target_pace_sec_per_km, target_pace_end_sec_per_km,
        target_pace_tolerance_sec, pace_zone, structure, notes,
        race_name, race_priority, race_taper_applied_at,
        target_rpe_min, target_rpe_max
      )
      values (
        new_week_id,
        workout_record.scheduled_date + date_offset_days,
        workout_record.kind, workout_record.target_distance_m,
        workout_record.target_duration_seconds,
        workout_record.target_pace_sec_per_km,
        workout_record.target_pace_end_sec_per_km,
        workout_record.target_pace_tolerance_sec,
        workout_record.pace_zone,
        workout_record.structure, workout_record.notes,
        workout_record.race_name, workout_record.race_priority,
        workout_record.race_taper_applied_at,
        workout_record.target_rpe_min, workout_record.target_rpe_max
      );
    end loop;
  end loop;

  return new_plan_id;
end;
$function$;

revoke execute on function public.clone_public_plan(uuid, date, text) from public, anon;
grant execute on function public.clone_public_plan(uuid, date, text) to authenticated;
grant execute on function public.clone_public_plan(uuid, date, text) to service_role;

-- ── 4. The anonymous view ───────────────────────────────────────────────────

create or replace function private.plan_author_visible(p_author uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, private
as $$
  select jsonb_build_object('name', u.display_name, 'handle', u.handle)
  from user_profiles u
  where u.id = p_author
    and u.shadow_hidden = false
    and ((select auth.uid()) is null
         or not is_blocked_either_way((select auth.uid()), u.id))
    and private.profile_visible_to(u.id, (select auth.uid()));
$$;

revoke execute on function private.plan_author_visible(uuid) from public, anon, authenticated;
grant execute on function private.plan_author_visible(uuid) to service_role;

create or replace function public.public_plan_share(p_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, private
as $$
  select jsonb_build_object(
    'id', p.id,
    'name', p.name,
    'goal_event', p.goal_event,
    'goal_distance_m', p.goal_distance_m,
    'days_per_week', p.days_per_week,
    'author', private.plan_author_visible(p.user_id),
    'weeks', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'week_index', w.week_index,
          'phase', w.phase,
          'target_volume_m', w.target_volume_m,
          'workouts', coalesce((
            select jsonb_agg(
              jsonb_build_object(
                'day', wo.scheduled_date - p.start_date,
                'kind', wo.kind,
                'target_distance_m', wo.target_distance_m,
                'target_duration_seconds', wo.target_duration_seconds,
                'pace_zone', wo.pace_zone,
                'target_rpe_min', wo.target_rpe_min,
                'target_rpe_max', wo.target_rpe_max
              )
              order by wo.scheduled_date, wo.id
            )
            from plan_workouts wo
            where wo.week_id = w.id
          ), '[]'::jsonb)
        )
        order by w.week_index
      )
      from plan_weeks w
      where w.plan_id = p.id
    ), '[]'::jsonb)
  )
  from training_plans p
  where p.id = p_id
    and p.is_template = true
    and p.is_public_template = true
    and private.public_plan_share_enabled()
    and not exists (
      select 1 from user_profiles u
      where u.id = p.user_id and u.shadow_hidden = true
    );
$$;

revoke execute on function public.public_plan_share(uuid) from public;
grant execute on function public.public_plan_share(uuid) to anon, authenticated, service_role;

comment on function public.public_plan_share(uuid) is
  'Redacted anonymous view of a public-library plan for /share/plan/<id>: '
  'goal, weeks and workouts by day offset; no physiology, paces, notes, dates '
  'or user id. Null while the public_plan_share gate is closed. decisions § 2262.';

-- ── 5. The copy's attribution ───────────────────────────────────────────────

create or replace function public.plan_started_from(p_plan_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public, private
as $$
  select jsonb_build_object(
    'author', private.plan_author_visible(p.source_author_id),
    'template_id', (
      select t.id from training_plans t
      where t.id = p.parent_template_id and t.is_public_template = true
    )
  )
  from training_plans p
  where p.id = p_plan_id
    and p.user_id = (select auth.uid())
    and p.source_author_id is not null;
$$;

revoke execute on function public.plan_started_from(uuid) from public, anon;
grant execute on function public.plan_started_from(uuid) to authenticated, service_role;

comment on function public.plan_started_from(uuid) is
  'For the caller''s own plan copied from the public library: the author it '
  'started from (null when that profile is hidden from the caller) and the '
  'template id while still public. Null for any other plan. decisions § 2262.';
