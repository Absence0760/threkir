-- An ended nutrition_plan_assignments row still governs the days inside its
-- start_date..end_date (decisions § 1922), so the client must keep reading the
-- plan it names: the day view resolves a past day's targets through
-- fetchNutritionPlansByIds, and a plan RLS hid there left that day judged
-- against nothing. 20270815000001's helper honoured only status = 'active',
-- which for a third-party author (the P3 nutritionist) withdrew the client's
-- own history the moment the assignment ended (decisions § 1957).
--
-- The read now follows the assignment row itself: any status that row can
-- hold. The status list is spelled out rather than dropped so a status added
-- later (revoked, withdrawn) is denied until a migration decides otherwise.
-- Deleting the assignment, or the plan (which cascades it), still closes the
-- read. Writes are untouched: plans stay author-only and self-assignment
-- still requires authoring the plan.

create or replace function private.can_read_nutrition_plan(p_plan_id uuid, p_uid uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
           select 1 from nutrition_plans p
            where p.id = p_plan_id and p.author_id = p_uid)
      or exists (
           select 1 from nutrition_plan_assignments a
            where a.plan_id = p_plan_id and a.client_id = p_uid
              and a.status in ('active', 'ended'));
$$;

revoke execute on function private.can_read_nutrition_plan(uuid, uuid) from public, anon;
grant execute on function private.can_read_nutrition_plan(uuid, uuid) to authenticated, service_role;
