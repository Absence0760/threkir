-- Nutrition programming, slice P1 (docs/features/nutrition_programming.md,
-- decisions § 1922): self-serve meal plans + the self-assignment that makes
-- one govern a run of diary days. Adherence is computed on read from
-- food_log + the governing plan and never stored, so no third table and no
-- trigger. nutrition_plan_meals (+ meal_count) and the progression ENGINE are
-- P2; the progression columns land here at their defaults, as gym P1 did.
--
-- A client may read a plan because an assignment links them to it (the P3
-- nutritionist branch), so the plans read policy consults the assignments
-- table. Doing that inline would re-apply the assignments RLS inside the plans
-- policy, so it goes through a SECURITY DEFINER helper, as
-- private.is_active_coach_of does for runs.
--
-- Self-assignment is a direct INSERT. Its policy also requires the caller to
-- author the plan: without that, a known plan id is enough to mint a row that
-- the client branch of the helper then honours, and any plan becomes readable.
--
-- Every FK cascades from auth.users except assigned_by, which is set null so a
-- deleted nutritionist (P3) leaves the client's history intact. Deleting a
-- plan never touches food_log: the link is date + assignment, not an FK.

create table public.nutrition_plans (
  id                 uuid primary key default gen_random_uuid(),
  author_id          uuid not null references auth.users (id) on delete cascade,
  title              text not null check (length(title) between 1 and 120),
  notes              text check (notes is null or length(notes) <= 1000),

  goal_phase         text not null default 'maintain'
                       check (goal_phase in ('cut','maintain','build','recomp')),

  target_calories    numeric(7,1) not null
                       check (target_calories >= 1000 and target_calories <= 12000),
  target_protein_g   numeric(6,1) check (target_protein_g is null
                       or (target_protein_g >= 0 and target_protein_g <= 2000)),
  target_carbs_g     numeric(6,1) check (target_carbs_g is null
                       or (target_carbs_g >= 0 and target_carbs_g <= 2000)),
  target_fat_g       numeric(6,1) check (target_fat_g is null
                       or (target_fat_g >= 0 and target_fat_g <= 2000)),

  training_calories  numeric(7,1) check (training_calories is null
                       or (training_calories >= 1000 and training_calories <= 12000)),
  training_carbs_g   numeric(6,1) check (training_carbs_g is null
                       or (training_carbs_g >= 0 and training_carbs_g <= 2000)),

  progression        text not null default 'none'
                       check (progression in ('none','weight_trend','linear_deficit','reverse_diet')),
  progression_params jsonb not null default '{}'::jsonb,

  external_id        text,
  last_modified_at   timestamptz not null default now(),
  created_at         timestamptz not null default now()
);

create unique index nutrition_plans_author_external_id_key
  on public.nutrition_plans (author_id, external_id) where external_id is not null;
create index nutrition_plans_author_modified_idx
  on public.nutrition_plans (author_id, last_modified_at desc);

create table public.nutrition_plan_assignments (
  id               uuid primary key default gen_random_uuid(),
  plan_id          uuid not null references public.nutrition_plans (id) on delete cascade,
  client_id        uuid not null references auth.users (id) on delete cascade,
  assigned_by      uuid references auth.users (id) on delete set null,

  start_date       date not null,
  end_date         date,
  status           text not null default 'active'
                     check (status in ('active','ended')),

  last_modified_at timestamptz not null default now(),
  created_at       timestamptz not null default now(),

  constraint nutrition_plan_assignments_dates_chk
    check (end_date is null or end_date >= start_date)
);

create index nutrition_plan_assignments_client_idx
  on public.nutrition_plan_assignments (client_id, start_date desc);
create index nutrition_plan_assignments_plan_idx
  on public.nutrition_plan_assignments (plan_id);
create index nutrition_plan_assignments_assigned_by_idx
  on public.nutrition_plan_assignments (assigned_by);

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
            where a.plan_id = p_plan_id and a.client_id = p_uid and a.status = 'active');
$$;

revoke execute on function private.can_read_nutrition_plan(uuid, uuid) from public, anon;
grant execute on function private.can_read_nutrition_plan(uuid, uuid) to authenticated, service_role;

alter table public.nutrition_plans            enable row level security;
alter table public.nutrition_plan_assignments enable row level security;

create policy "nutrition_plans author or client select"
  on public.nutrition_plans for select
  to authenticated
  using (author_id = (select auth.uid())
         or private.can_read_nutrition_plan(id, (select auth.uid())));
create policy "nutrition_plans author insert"
  on public.nutrition_plans for insert
  to authenticated
  with check (author_id = (select auth.uid()));
create policy "nutrition_plans author update"
  on public.nutrition_plans for update
  to authenticated
  using (author_id = (select auth.uid()))
  with check (author_id = (select auth.uid()));
create policy "nutrition_plans author delete"
  on public.nutrition_plans for delete
  to authenticated
  using (author_id = (select auth.uid()));

create policy "nutrition_plan_assignments either party select"
  on public.nutrition_plan_assignments for select
  to authenticated
  using (client_id = (select auth.uid()) or assigned_by = (select auth.uid()));
create policy "nutrition_plan_assignments self assign insert"
  on public.nutrition_plan_assignments for insert
  to authenticated
  with check (
    client_id = (select auth.uid())
    and assigned_by = (select auth.uid())
    and exists (
      select 1 from public.nutrition_plans p
       where p.id = nutrition_plan_assignments.plan_id
         and p.author_id = (select auth.uid()))
  );
create policy "nutrition_plan_assignments self update"
  on public.nutrition_plan_assignments for update
  to authenticated
  using (client_id = (select auth.uid()) and assigned_by = (select auth.uid()))
  with check (
    client_id = (select auth.uid())
    and assigned_by = (select auth.uid())
    and exists (
      select 1 from public.nutrition_plans p
       where p.id = nutrition_plan_assignments.plan_id
         and p.author_id = (select auth.uid()))
  );
create policy "nutrition_plan_assignments self delete"
  on public.nutrition_plan_assignments for delete
  to authenticated
  using (client_id = (select auth.uid()) and assigned_by = (select auth.uid()));

revoke all on table public.nutrition_plans from public, anon, authenticated;
revoke all on table public.nutrition_plan_assignments from public, anon, authenticated;
grant select, insert, update, delete on table public.nutrition_plans to authenticated;
grant select, insert, update, delete on table public.nutrition_plan_assignments to authenticated;
grant select, insert, update, delete on table public.nutrition_plans to service_role;
grant select, insert, update, delete on table public.nutrition_plan_assignments to service_role;
