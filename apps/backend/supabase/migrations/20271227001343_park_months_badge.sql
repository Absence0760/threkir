-- The `park_months` badge (issue #1343 phase 4, decisions § 2426 / § 2511):
-- distinct calendar months, each read in its park's timezone, with a
-- completed park course: 3 / 6 / 12 / 24. Completions only, never a rank or a
-- monthly win, so an award never moves once earned. Like the other park
-- families it names a count, never a course, a park or a run (source_id null),
-- counts private runs, and is earned by the eligible-run rule the other
-- families use. A month is the same `at time zone` reading the monthly boards
-- use, so 23:30 on 31 October in New York is October here too.
--
-- The awarder is already wired: global_segment_efforts' statement trigger
-- (20271123002404) re-derives on every new effort, and the revoker only
-- touches the distance families. The ladder is a lockstep rail with
-- `badges.ts` and `badges.dart` (scripts/check_shared_constants.mjs).
--
-- ── Locks ──
-- Function DDL only. The back-fill re-derives for users who already hold a
-- park course effort; each call inserts at most four rows with
-- `on conflict do nothing`.

-- Complete live body (20271123002404) plus the park_months branch. The ladder
-- shape (`select '<family>'` then `values (...) as t(...)`) is what
-- scripts/check_shared_constants.mjs reads, so no CTE here selects a quoted
-- literal.
create or replace function achievement_tiers_met(p_user uuid)
returns table (
  badge_key   text,
  tier        text,
  source_kind text,
  source_id   uuid,
  value_num   double precision,
  rank        integer
)
language sql
stable
security invoker
set search_path = public
as $$
  with eligible as (
    select id, distance_m, activity_type, started_at
    from runs
    where user_id = p_user
      and source in ('app', 'watch', 'strava', 'garmin', 'healthkit', 'healthconnect', 'parkrun', 'race')
      and is_dnf = false
  ),
  dist as (
    select
      coalesce(max(distance_m) filter (where activity_type <> 'cycle'), 0)::double precision as longest_m,
      coalesce(sum(distance_m), 0)::double precision as lifetime_m
    from eligible
    where distance_m is not null
  ),
  longest_run as (
    select id
    from eligible
    where activity_type <> 'cycle'
      and distance_m is not null
    order by distance_m desc, started_at asc
    limit 1
  ),
  run_days as (
    select distinct (started_at at time zone 'UTC')::date as d
    from eligible
  ),
  grouped as (
    select d - (row_number() over (order by d))::int as grp
    from run_days
  ),
  streak as (
    select coalesce(max(cnt), 0)::double precision as best
    from (select count(*) as cnt from grouped group by grp) s
  ),
  prs as (
    select count(*)::double precision as n
    from personal_records
    where user_id = p_user
  ),
  plans as (
    select count(*)::double precision as n
    from training_plans
    where user_id = p_user and status = 'completed' and is_template = false
  ),
  done_courses as (
    select distinct pc.id as course_id, pc.park_id, pc.status
    from global_segment_efforts e
    join eligible r on r.id = e.run_id
    join park_courses pc on pc.global_segment_id = e.global_segment_id
    join parks pk on pk.id = pc.park_id and pk.is_active
    where e.user_id = p_user
  ),
  park_totals as (
    select pc.park_id, pk.region_code, count(*) as open_courses
    from park_courses pc
    join parks pk on pk.id = pc.park_id and pk.is_active
    where pc.status <> 'closed'
    group by pc.park_id, pk.region_code
  ),
  park_done as (
    select t.park_id, t.region_code, t.open_courses,
           count(d.course_id) filter (where d.status <> 'closed') as done_open
    from park_totals t
    left join done_courses d on d.park_id = t.park_id
    group by t.park_id, t.region_code, t.open_courses
  ),
  region_done as (
    select region_code
    from park_done
    group by region_code
    having count(*) >= 3 and bool_and(done_open > 0)
  ),
  parks_agg as (
    select
      (select count(*) from done_courses)::double precision as courses,
      (select count(*) from park_done where open_courses >= 2 and done_open = open_courses)::double precision as complete_parks,
      (select count(*) from region_done)::double precision as regions
  ),
  park_months as (
    select count(distinct date_trunc('month', e.started_at at time zone pk.timezone))::double precision as n
    from global_segment_efforts e
    join eligible r on r.id = e.run_id
    join park_courses pc on pc.global_segment_id = e.global_segment_id
    join parks pk on pk.id = pc.park_id and pk.is_active
    where e.user_id = p_user
  )
  select 'distance_single'::text, t.tier, 'distance'::text,
         (select id from longest_run), d.longest_m, t.rank
  from dist d, (values ('bronze',5000,1),('silver',21097,2),('gold',42195,3),('platinum',50000,4)) as t(tier,thr,rank)
  where d.longest_m >= t.thr
  union all
  select 'distance_lifetime', t.tier, 'distance', null::uuid, d.lifetime_m, t.rank
  from dist d, (values ('bronze',100000,1),('silver',500000,2),('gold',1000000,3),('platinum',5000000,4)) as t(tier,thr,rank)
  where d.lifetime_m >= t.thr
  union all
  select 'streak', t.tier, 'streak', null::uuid, s.best, t.rank
  from streak s, (values ('bronze',7,1),('silver',30,2),('gold',100,3),('platinum',365,4)) as t(tier,thr,rank)
  where s.best >= t.thr
  union all
  select 'pr', t.tier, 'pr', null::uuid, p.n, t.rank
  from prs p, (values ('bronze',1,1),('silver',3,2),('gold',5,3)) as t(tier,thr,rank)
  where p.n >= t.thr
  union all
  select 'plan_finisher', t.tier, 'plan', null::uuid, p.n, t.rank
  from plans p, (values ('bronze',1,1),('silver',3,2),('gold',10,3)) as t(tier,thr,rank)
  where p.n >= t.thr
  union all
  select 'park_courses', t.tier, 'segment', null::uuid, a.courses, t.rank
  from parks_agg a, (values ('bronze',1,1),('silver',5,2),('gold',10,3),('platinum',25,4)) as t(tier,thr,rank)
  where a.courses >= t.thr
  union all
  select 'park_complete', t.tier, 'segment', null::uuid, a.complete_parks, t.rank
  from parks_agg a, (values ('bronze',1,1),('silver',3,2),('gold',10,3)) as t(tier,thr,rank)
  where a.complete_parks >= t.thr
  union all
  select 'park_passport', t.tier, 'segment', null::uuid, a.regions, t.rank
  from parks_agg a, (values ('bronze',1,1),('silver',3,2),('gold',10,3)) as t(tier,thr,rank)
  where a.regions >= t.thr
  union all
  select 'park_months', t.tier, 'segment', null::uuid, m.n, t.rank
  from park_months m, (values ('bronze',3,1),('silver',6,2),('gold',12,3),('platinum',24,4)) as t(tier,thr,rank)
  where m.n >= t.thr
$$;

revoke execute on function achievement_tiers_met(uuid) from public, anon, authenticated;

-- ───────────────────────── back-fill ─────────────────────────

do $$
declare
  v_user_id uuid;
begin
  for v_user_id in
    select distinct e.user_id
    from global_segment_efforts e
    join park_courses pc on pc.global_segment_id = e.global_segment_id
  loop
    perform award_achievements_for_user(v_user_id);
  end loop;
end;
$$;
