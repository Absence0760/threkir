-- Height, gender and the body_metrics weight series are kept only with
-- health-data consent, and the database refuses them without (owner decision
-- 2026-11-15; decisions § 2547, extending § 2542 from the settings-bag weight).
--
-- Withdrawal already clears these values (private.erase_consent_gated_values,
-- 20271230001390), and every client writes them only under consent. But
-- nothing in the database held a writer to that rule: `user_profiles.height_cm`
-- and `gender` were writable by the owner's UPDATE policy with or without a
-- consent stamp, and `body_metrics` checked only the Art 8 age gate
-- (private.enforce_consent). Values stored by runners who never consented,
-- from before the client gates existed, are still held. This migration:
--
--   * private.check_health_profile_values refuses a new or changed non-null
--     `height_cm` or `gender` on user_profiles unless the resulting row has
--     `health_data_consent_at` (42501). An update that sets both the stamp and
--     a value passes, as does a write that leaves either value as it was: the
--     withdrawal nulls only the stamp and the transition trigger then nulls
--     the values. Clearing a value is never refused.
--   * private.check_body_metrics_consent refuses a body_metrics insert or
--     update unless the row's owner has `health_data_consent_at` (42501).
--     Deleting a row is never refused.
--   * Removes what runners without consent still hold: height and gender on
--     the profile, every body_metrics row, and the heart-rate targets on
--     their own plans (the targets already have a write gate,
--     private.check_plan_workout_hr_target, 20270912000001, but it lets an
--     unchanged value stand), through private.erase_values_held_without_consent.
--     It is set-based rather than a per-runner call of
--     private.erase_consent_gated_values: it clears the same values, and a
--     body_metrics row can belong to a runner with no profile row at all.
--     The settings-bag copies were stripped the same way by 20271230001390.
--
-- Order: the triggers are created before the clean-up, so the SHARE ROW
-- EXCLUSIVE locks they take hold off a concurrent unconsented write until the
-- clean-up commits. The clean-up only nulls and deletes, which the triggers
-- allow.
--
-- Lock: user_profiles (one row per runner), body_metrics (a few rows per
-- consenting runner) and plan_workouts are not high-volume tables
-- (docs/backend/migration_locks.md); each clean-up statement is scoped to rows
-- holding a value.

create or replace function private.check_health_profile_values()
returns trigger
language plpgsql
set search_path = pg_catalog
as $$
begin
  if new.health_data_consent_at is not null then
    return new;
  end if;
  if new.height_cm is not null
     and (tg_op = 'INSERT' or new.height_cm is distinct from old.height_cm) then
    raise exception using
      errcode = 'insufficient_privilege',
      message = 'user_profiles: height_cm needs health-data consent';
  end if;
  if new.gender is not null
     and (tg_op = 'INSERT' or new.gender is distinct from old.gender) then
    raise exception using
      errcode = 'insufficient_privilege',
      message = 'user_profiles: gender needs health-data consent';
  end if;
  return new;
end;
$$;

revoke execute on function private.check_health_profile_values() from public, anon, authenticated;

create trigger user_profiles_check_health_values
  before insert or update of height_cm, gender on user_profiles
  for each row execute function private.check_health_profile_values();

create or replace function private.check_body_metrics_consent()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
begin
  if not exists (
    select 1 from user_profiles up
    where up.id = new.user_id and up.health_data_consent_at is not null
  ) then
    raise exception using
      errcode = 'insufficient_privilege',
      message = 'body_metrics: weight needs health-data consent';
  end if;
  return new;
end;
$$;

revoke execute on function private.check_body_metrics_consent() from public, anon, authenticated;

create trigger body_metrics_check_health_consent
  before insert or update on body_metrics
  for each row execute function private.check_body_metrics_consent();

create or replace function private.erase_values_held_without_consent()
returns void
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
begin
  update user_profiles
     set height_cm = null, gender = null
   where health_data_consent_at is null
     and (height_cm is not null or gender is not null);

  delete from body_metrics b
   where not exists (
     select 1 from user_profiles p
      where p.id = b.user_id and p.health_data_consent_at is not null
   );

  update plan_workouts pw
     set target_hr_min_bpm = null, target_hr_max_bpm = null
    from plan_weeks pwk
    join training_plans tp on tp.id = pwk.plan_id
   where pw.week_id = pwk.id
     and (pw.target_hr_min_bpm is not null or pw.target_hr_max_bpm is not null)
     and not exists (
       select 1 from user_profiles p
        where p.id = tp.user_id and p.health_data_consent_at is not null
     );
end;
$$;

revoke execute on function private.erase_values_held_without_consent() from public, anon, authenticated;

select private.erase_values_held_without_consent();
