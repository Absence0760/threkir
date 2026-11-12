-- The two numbers that decide whether the Coach row stays where the
-- 2026-11-08 Home redesign put it (decisions § 2387): Coach engagement among
-- active runners, and plan-day completion, weekly over the last 16 ISO weeks.
-- Issue #1362. Until now they were two raw queries in multi_modal.md § Home
-- that someone with prod access was meant to run by hand; the owner's rule is
-- that nobody hand-runs SQL against prod, so they are admin reads behind
-- /admin/home-metrics instead.
--
-- ── Who can read it ──────────────────────────────────────────────────────────
-- The `app_admins` allow-list (20270105_001), the same privilege
-- /admin/earnings uses (20270723000002). Both functions are SECURITY DEFINER
-- because they count rows across every user, which RLS would otherwise limit to
-- the caller's own, and both HARD-DENY (42501) a caller for whom
-- `private.is_admin(auth.uid())` is false before reading anything. EXECUTE is
-- granted to `authenticated` only, so anon cannot call them at all.
--
-- ── What they return ─────────────────────────────────────────────────────────
-- One row per week, aggregate counts only: never a user id, never a per-user
-- row. Every one of the 16 weeks is returned, a week with nothing in it
-- included, so a gap reads as a zero rather than as a missing row. A
-- percentage over a zero denominator is null, not an error.
--
-- ── Weeks ────────────────────────────────────────────────────────────────────
-- ISO weeks (Monday start) in UTC. The window is the current ISO week and the
-- 15 before it, so the current week is partial. A run's week is the UTC date
-- of `started_at`; a Coach day is `user_coach_usage.usage_date`, which the
-- increment RPC stamps with the server's `current_date`, UTC on Supabase; a
-- plan day is `plan_workouts.scheduled_date`, a calendar date with no zone,
-- taken as-is. The week start is `d - (isodow(d) - 1)`, plain date
-- arithmetic, so the session's TimeZone cannot move a row between weeks.
--
-- ── Coach engagement ─────────────────────────────────────────────────────────
-- Of the users with at least one run started in the week, the share who also
-- sent the Coach at least one message that week (`message_count > 0`). A user
-- who used the Coach without running is not in the denominator.
-- `user_coach_usage` records no entry point, so this is Coach use as a whole,
-- not the Home row against the sidebar or Messages.
--
-- ── Plan-day completion ──────────────────────────────────────────────────────
-- Of the non-rest `plan_workouts` scheduled in the week up to yesterday (UTC),
-- the share completed by a run (`completed_run_id`) or marked done
-- (`manually_completed`). Today is excluded because it is not over. A skipped
-- day stays in the denominator: it was scheduled and not done. Left out:
--   * templates (`is_template`, club and public library): nobody's schedule;
--   * abandoned plans: nothing records when a plan was abandoned, so its
--     unwalked remainder would count as misses forever;
--   * a paused plan's days from the day it was paused (`paused_at`, UTC):
--     a pause is not a miss, and resuming moves those days forward anyway.
-- Because abandonment is not timestamped, abandoning a plan removes its past
-- weeks from these counts too: an earlier week's figure can move.
--
-- ── Lock impact (docs/backend/migration_locks.md) ────────────────────────────
-- Only CREATE FUNCTION, REVOKE and GRANT: catalogue rows in pg_proc, no lock on
-- any table, no scan, no rewrite. The reads are an operator's, a range scan on
-- `runs.started_at`, `user_coach_usage` and `plan_workouts.scheduled_date`
-- over 16 weeks; no index is added for them.

create or replace function public.admin_home_coach_engagement_weeks()
returns table (
  week_start       date,
  active_runners   bigint,
  coached_runners  bigint,
  coached_pct      numeric
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_today date := (now() at time zone 'UTC')::date;
  v_first date;
begin
  if not private.is_admin(auth.uid()) then
    raise exception 'admin_home_coach_engagement_weeks: not authorized'
      using errcode = '42501';
  end if;

  v_first := v_today - (extract(isodow from v_today)::int - 1) - 105;

  return query
    with weeks as (
      select (v_first + 7 * g)::date as wk
      from pg_catalog.generate_series(0, 15) as g
    ),
    active as (
      select distinct
        r.user_id as uid,
        (r.started_at at time zone 'UTC')::date
          - (extract(isodow from (r.started_at at time zone 'UTC'))::int - 1) as wk
      from public.runs r
      where r.started_at >= (v_first::timestamp at time zone 'UTC')
    ),
    coached as (
      select distinct
        u.user_id as uid,
        u.usage_date - (extract(isodow from u.usage_date)::int - 1) as wk
      from public.user_coach_usage u
      where u.usage_date >= v_first
        and u.message_count > 0
    )
    select
      w.wk,
      count(a.uid)::bigint,
      count(c.uid)::bigint,
      case when count(a.uid) = 0 then null
           else round(100.0 * count(c.uid) / count(a.uid), 1)
      end
    from weeks w
    left join active a on a.wk = w.wk
    left join coached c on c.uid = a.uid and c.wk = a.wk
    group by w.wk
    order by w.wk;
end;
$$;

comment on function public.admin_home_coach_engagement_weeks() is
  'Operator-only (app_admins): for each of the last 16 ISO weeks (UTC, Monday '
  'start, current week partial), the users with a run that week, how many of '
  'them messaged the Coach that week, and the percentage (null over zero). '
  'Aggregates only. Raises 42501 for anyone else. decisions § 2387, issue #1362.';

revoke execute on function public.admin_home_coach_engagement_weeks() from public, anon;
grant execute on function public.admin_home_coach_engagement_weeks() to authenticated;

create or replace function public.admin_home_plan_completion_weeks()
returns table (
  week_start      date,
  scheduled_days  bigint,
  completed_days  bigint,
  completed_pct   numeric
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_today date := (now() at time zone 'UTC')::date;
  v_first date;
begin
  if not private.is_admin(auth.uid()) then
    raise exception 'admin_home_plan_completion_weeks: not authorized'
      using errcode = '42501';
  end if;

  v_first := v_today - (extract(isodow from v_today)::int - 1) - 105;

  return query
    with weeks as (
      select (v_first + 7 * g)::date as wk
      from pg_catalog.generate_series(0, 15) as g
    ),
    days as (
      select
        pw.scheduled_date - (extract(isodow from pw.scheduled_date)::int - 1) as wk,
        (pw.completed_run_id is not null or pw.manually_completed) as done
      from public.plan_workouts pw
      join public.plan_weeks pk on pk.id = pw.week_id
      join public.training_plans tp on tp.id = pk.plan_id
      where pw.kind <> 'rest'
        and pw.scheduled_date >= v_first
        and pw.scheduled_date < v_today
        and not tp.is_template
        and tp.status <> 'abandoned'
        and (tp.status <> 'paused'
             or tp.paused_at is null
             or pw.scheduled_date < (tp.paused_at at time zone 'UTC')::date)
    )
    select
      w.wk,
      count(d.wk)::bigint,
      (count(*) filter (where d.done))::bigint,
      case when count(d.wk) = 0 then null
           else round(100.0 * count(*) filter (where d.done) / count(d.wk), 1)
      end
    from weeks w
    left join days d on d.wk = w.wk
    group by w.wk
    order by w.wk;
end;
$$;

comment on function public.admin_home_plan_completion_weeks() is
  'Operator-only (app_admins): for each of the last 16 ISO weeks (UTC, Monday '
  'start), the non-rest plan days scheduled up to yesterday on non-template, '
  'non-abandoned plans (a paused plan up to its pause), how many were done by a '
  'run or marked done, and the percentage (null over zero). Aggregates only. '
  'Raises 42501 for anyone else. decisions § 2387, issue #1362.';

revoke execute on function public.admin_home_plan_completion_weeks() from public, anon;
grant execute on function public.admin_home_plan_completion_weeks() to authenticated;
