-- A distance badge earned on an inflated GPS distance is taken back when the
-- owner-requested `distance_recompute` job (20270716000001) lowers the run.
--
-- Awards are durable by design: award_achievements_for_user only inserts, so a
-- deleted run or an ordinary edit never takes a badge away. The recompute is
-- the one write that says the old number was wrong rather than that the run
-- changed — a 5.2 km hop-sum that re-derives to 4.9 km never earned the 5k
-- badge. So, for that write only, the distance_single and distance_lifetime
-- tiers the user's CURRENT runs no longer meet are deleted. Every other family
-- (streak, pr, plan_finisher) is left alone and stays durable.
--
-- One earned set, two readers. The ladders and the eligible-run rules move out
-- of award_achievements_for_user into achievement_tiers_met(), which returns
-- every tier met (not just the top per family). The awarder inserts the top
-- tier per family from it, exactly as before; the revoker deletes distance rows
-- absent from it. A threshold can therefore never differ between awarding and
-- revoking. scripts/check_shared_constants.mjs reads the ladders from the new
-- function.
--
-- The trigger fires only when distance_m AND metadata.distance_recomputed_at
-- both change in one UPDATE, which is the worker's single PATCH
-- (apps/job_worker/internal/handler_distance_recompute.go). It is named to sort
-- before runs_award_achievements_update, and Postgres fires same-event triggers
-- in name order, so the revoke lands first and the award trigger that follows
-- (distance_m changed) inserts any lower tier the corrected figure still meets.
--
-- notifications.achievement_id is ON DELETE CASCADE (20270208_001), so the
-- bell row for a revoked badge goes with it rather than pointing at nothing.
-- No new notification kind: a revoke is the consequence of an action the owner
-- just asked for, and the run page already shows the original figure.
--
-- Locks: function DDL takes none a reader or writer waits on. CREATE TRIGGER on
-- runs takes SHARE ROW EXCLUSIVE for a catalogue-only change — no scan, no
-- rewrite, held for the length of this short transaction. No backfill: no run
-- has been recomputed in production yet.

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
$$;

revoke execute on function achievement_tiers_met(uuid) from public, anon, authenticated;

-- Complete live body (20270514_001) with the earned-set computation replaced by
-- achievement_tiers_met(); the abuse guard and the per-user lock are unchanged.
create or replace function award_achievements_for_user(p_user uuid)
returns setof achievements
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text := coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'),
    ''
  );
begin
  -- The only legitimate callers are the statement-level award triggers, which
  -- run at pg_trigger_depth() > 0, including for a user who is not the caller
  -- (assign_plan_to_athlete), so this cannot gate on auth.uid() = p_user. At
  -- depth 0 only service_role and direct-SQL/empty-role callers pass.
  if pg_trigger_depth() = 0 and v_role <> 'service_role' and v_role <> '' then
    raise exception 'award_achievements_for_user: not authorized' using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(hashtext('achievements:' || p_user::text));

  return query
  with top_per_family as (
    select distinct on (m.badge_key) m.badge_key, m.tier, m.source_kind, m.source_id, m.value_num
    from achievement_tiers_met(p_user) m
    order by m.badge_key, m.rank desc
  ),
  inserted as (
    insert into achievements (user_id, badge_key, tier, source_kind, source_id, value_num)
    select p_user, f.badge_key, f.tier, f.source_kind, f.source_id, f.value_num from top_per_family f
    on conflict (user_id, badge_key, tier) do nothing
    returning *
  )
  select * from inserted;
end;
$$;

revoke execute on function award_achievements_for_user(uuid) from public, anon, authenticated;

create or replace function revoke_unmet_distance_achievements(p_user uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text := coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role'),
    ''
  );
  v_deleted integer;
begin
  if pg_trigger_depth() = 0 and v_role <> 'service_role' and v_role <> '' then
    raise exception 'revoke_unmet_distance_achievements: not authorized' using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(hashtext('achievements:' || p_user::text));

  with met as (
    select m.badge_key, m.tier
    from achievement_tiers_met(p_user) m
    where m.badge_key in ('distance_single', 'distance_lifetime')
  )
  delete from achievements a
  where a.user_id = p_user
    and a.badge_key in ('distance_single', 'distance_lifetime')
    and not exists (
      select 1 from met where met.badge_key = a.badge_key and met.tier = a.tier
    );
  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

revoke execute on function revoke_unmet_distance_achievements(uuid) from public, anon, authenticated;

create or replace function trigger_revoke_recomputed_distance_achievements()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
begin
  for v_user_id in
    select distinct n.user_id
    from new_runs n
    join old_runs o on o.id = n.id
    where n.distance_m is distinct from o.distance_m
      and n.metadata ->> 'distance_recomputed_at' is not null
      and (n.metadata ->> 'distance_recomputed_at')
        is distinct from (o.metadata ->> 'distance_recomputed_at')
  loop
    perform revoke_unmet_distance_achievements(v_user_id);
  end loop;
  return null;
end;
$$;

create trigger runs_achievements_revoke_on_distance_recompute
  after update on runs
  referencing old table as old_runs new table as new_runs
  for each statement execute function trigger_revoke_recomputed_distance_achievements();
