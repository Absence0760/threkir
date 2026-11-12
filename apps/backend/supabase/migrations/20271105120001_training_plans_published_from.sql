-- A public-library copy remembers the plan it was published from.
--
-- Plan detail decided whether a plan was already in the library by finding
-- one of the owner's public templates with the same NAME. Renaming the plan
-- lost its Unpublish button (the copy kept the old name), and two plans that
-- shared a name each showed Unpublish for the same copy, so unpublishing from
-- one deleted the other's library entry. The copy is now linked by id:
-- training_plans.published_from_plan_id, nullable, set-null when the source
-- plan is deleted, so the library copy outlives the plan it came from.
--
-- Who writes it
--   * publishPlanToLibrary (web data.ts, mobile training_service.dart) sets it
--     on the template it inserts. The owner may set or clear it through the
--     existing owner INSERT / UPDATE policies; no new policy.
--   * clone_public_plan, clone_plan_template and assign_plan_to_athlete copy
--     a named column list that does not include it, so a cloner's plan never
--     points at the publisher's source plan.
--
-- What it discloses
--   The column is readable on a public template by every library reader,
--   like every other column of that row (RLS has no column dimension, see
--   20270508_001). It holds the uuid of the publisher's own plan, which the
--   owner-only SELECT policy keeps unreadable to anyone else, so it names a
--   row the reader cannot open and carries none of that row's content.
--
-- Backfill
--   Existing copies are linked by name only where the match is unambiguous:
--   the owner has exactly one public template with that name AND exactly one
--   non-template plan with that name. Anything else stays null, which shows
--   Publish rather than wiring Unpublish to the wrong copy.
--
-- Locks: training_plans is a per-runner table, not one of the high-volume
-- tables check_migration_online_safety.mjs guards. ADD COLUMN of a nullable
-- column with no default is a catalogue change; the FK's validation reads the
-- table once against a column that is null in every row. The covering index
-- is partial on the non-null rows, so it is built empty. The backfill touches
-- only public templates (one row per publish action) under per-row locks.

alter table training_plans
  add column published_from_plan_id uuid references training_plans (id) on delete set null;

create index training_plans_published_from_idx
  on training_plans (published_from_plan_id)
  where published_from_plan_id is not null;

-- A function so the pgtap suite runs this exact statement against fixtures
-- (training_plan_published_from_test.sql). Nothing calls it after this
-- migration; a second run links nothing already linked.
create or replace function private.backfill_training_plan_published_from()
returns integer
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_linked integer;
begin
  with tmpl as (
    select user_id, name, min(id::text)::uuid as id
      from training_plans
     where is_public_template = true
     group by user_id, name
    having count(*) = 1
  ),
  src as (
    select user_id, name, min(id::text)::uuid as id
      from training_plans
     where is_template = false
     group by user_id, name
    having count(*) = 1
  )
  update training_plans t
     set published_from_plan_id = src.id
    from tmpl
    join src on src.user_id = tmpl.user_id and src.name = tmpl.name
   where t.id = tmpl.id
     and t.published_from_plan_id is null;
  get diagnostics v_linked = row_count;
  return v_linked;
end;
$$;

revoke execute on function private.backfill_training_plan_published_from() from public, anon, authenticated, service_role;

select private.backfill_training_plan_published_from();
