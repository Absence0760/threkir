-- The food log is kept only with health-data consent (decisions § 2513).
--
-- The privacy policy and the health-data notice name nutrition and food logs
-- as special-category data processed only with explicit consent. Until now
-- food_log took any write and showed every row to its owner.
--
--   * Writes: a BEFORE INSERT OR UPDATE trigger refuses a row whose owner has
--     no health-data consent (42501), for every writer including the service
--     role. Nothing is stored until consent is given.
--   * Reads: a RESTRICTIVE select policy hides the caller's rows while they
--     have no consent. Rows logged before this gate by a runner who never
--     consented are therefore hidden, not deleted: they come back when consent
--     is given, and are erased by withdraw_health_data_consent() or by the
--     flag-gated backlog purge (20271227100009).
--   * public_food_log (a definer view, so RLS does not reach it) gains the
--     same consent term, so a shared meal stops showing when its owner has no
--     consent on record. The term is written out rather than calling
--     private.health_data_consented: a function in a view runs with the
--     reader's EXECUTE rights, and anon must not be able to ask whether a
--     named runner has given health-data consent.
--
-- Lock: the policy and trigger are catalogue changes on food_log, which is
-- not a high-volume table (migration_locks.md). The view is replaced in place
-- with the same columns.

create or replace function private.food_log_health_gate()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
begin
  if not private.health_data_consented(new.user_id) then
    raise exception using
      errcode = 'insufficient_privilege',
      message = 'food_log: logging food needs health-data consent',
      hint = 'call grant_health_data_consent() first (decisions § 2513)';
  end if;
  return new;
end;
$$;

revoke execute on function private.food_log_health_gate() from public, anon, authenticated;

create trigger food_log_health_gate
  before insert or update on public.food_log
  for each row execute function private.food_log_health_gate();

create policy "food_log needs health consent"
  on public.food_log
  as restrictive
  for select
  to authenticated
  using (private.health_data_consented((select auth.uid())));

create or replace view public.public_food_log as
select
  f.id,
  f.user_id,
  f.started_at,
  f.item_name,
  f.meal_slot,
  f.calories,
  f.protein_g,
  f.carbs_g,
  f.fat_g,
  f.is_public,
  f.created_at
from public.food_log f
where f.is_public = true
  and exists (
    select 1 from public.user_profiles c
     where c.id = f.user_id and c.health_data_consent_at is not null
  )
  and (
    not exists (
      select 1 from public.user_profiles p
       where p.id = f.user_id and p.profile_private
    )
    or f.user_id = (select auth.uid())
    or exists (
      select 1 from public.user_follows uf
       where uf.followee_id = f.user_id and uf.follower_id = (select auth.uid())
    )
  );

revoke all on public.public_food_log from public, anon, authenticated;
grant select on public.public_food_log to anon, authenticated;
