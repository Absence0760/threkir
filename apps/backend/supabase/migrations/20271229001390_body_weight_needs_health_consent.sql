-- The settings-bag weight is kept only with health-data consent (the legal
-- pre-review of the #1381/#1382 consent wording, Finding A; decisions § 2542,
-- amending § 1811).
--
-- `user_settings.prefs.body_weight_kg` mirrors the consent-gated
-- `body_metrics` series so every calorie estimate has a weight to read. The
-- setup wizard and web onboarding wrote it whether or not the runner gave
-- health-data consent, and the Health Connect import seeded it the same way,
-- while the consent statement and /health-data-notice both say weight is kept
-- only with that consent. The clients now write it only under consent; this
-- holds every other writer to the same rule:
--
--   * private.check_body_weight_setting refuses a new or changed non-null
--     `body_weight_kg` from a runner without `health_data_consent_at`
--     (42501), the way private.check_hr_medication_setting guards
--     `hr_medication_affected`. Removing the key, or a settings write that
--     leaves it as it was, is never refused.
--   * The weights already held without consent are removed (owner decision,
--     2026-11-15). Without them the calorie estimate uses its documented 70 kg
--     default, as it does for anyone who never gave a weight.
--   * withdraw_health_data_consent() now strips `body_weight_kg` on every
--     withdrawal. It kept the key for a runner who had never consented, only
--     because onboarding could have stored a weight without consent; nothing
--     can now.
--
-- Order: the trigger is created before the clean-up, so the SHARE ROW
-- EXCLUSIVE lock it takes holds off a concurrent unconsented write until the
-- clean-up commits. The clean-up only removes the key, which the trigger
-- allows.
--
-- Lock: `user_settings` is one row per runner and not a high-volume table
-- (docs/backend/migration_locks.md); the clean-up is scoped to rows holding
-- the key. Functions otherwise.

create or replace function private.check_body_weight_setting()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
declare
  v_new jsonb := new.prefs -> 'body_weight_kg';
begin
  if v_new is null or v_new = 'null'::jsonb then
    return new;
  end if;
  if tg_op = 'UPDATE'
     and (old.prefs -> 'body_weight_kg') is not distinct from v_new then
    return new;
  end if;
  if not exists (
    select 1 from user_profiles up
    where up.id = new.user_id and up.health_data_consent_at is not null
  ) then
    raise exception using
      errcode = 'insufficient_privilege',
      message = 'user_settings: body_weight_kg needs health-data consent';
  end if;
  return new;
end;
$$;

revoke execute on function private.check_body_weight_setting() from public, anon, authenticated;

create trigger user_settings_check_body_weight
  before insert or update of prefs on user_settings
  for each row execute function private.check_body_weight_setting();

update user_settings s
   set prefs = s.prefs - 'body_weight_kg'
 where s.prefs ? 'body_weight_kg'
   and not exists (
     select 1 from user_profiles p
      where p.id = s.user_id and p.health_data_consent_at is not null
   );

create or replace function withdraw_health_data_consent()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_had_consent boolean;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  select health_data_consent_at is not null
    into v_had_consent
    from user_profiles
   where id = v_uid;
  perform set_config('app.consent_write', 'on', true);
  -- Insert-or-update so the withdrawal ALWAYS lands a row carrying the
  -- withdrawn state — a 0-row silent no-op here means special-category
  -- data lives on while the user believes it erased.
  --
  -- `date_of_birth` is deliberately absent: it is the child-safety age
  -- record, not an Art 9 column (§ 721).
  insert into user_profiles (id)
  values (v_uid)
  on conflict (id) do update
    set health_data_consent_at = null,
        height_cm = null,
        gender = null;
  -- Heart rate and the food log (§ 2514). With consent on record the
  -- user_profiles transition trigger has just erased them; without it there
  -- was no transition, so a hidden pre-gate backlog is erased here.
  if not coalesce(v_had_consent, false) then
    perform private.erase_health_records(v_uid);
  end if;
  -- Art 7(3): the special-category weight series goes in the same
  -- transaction — no partial-failure window between two client calls.
  delete from body_metrics where user_id = v_uid;
  -- Heart-rate prescription on the runner's own plans, and the
  -- medication-affected flag (§ 2092).
  update plan_workouts pw
     set target_hr_min_bpm = null, target_hr_max_bpm = null
    from plan_weeks pwk
    join training_plans tp on tp.id = pwk.plan_id
   where pw.week_id = pwk.id
     and tp.user_id = v_uid
     and (pw.target_hr_min_bpm is not null or pw.target_hr_max_bpm is not null);
  -- The Art 9 copies in the settings bag.
  update user_settings
     set prefs = prefs
                 - array['hr_medication_affected', 'date_of_birth', 'body_weight_kg',
                         'cycle_tracking_mode', 'cycle_length_days',
                         'cycle_last_period_start', 'pregnancy_due_date']
   where user_id = v_uid
     and prefs ?| array['hr_medication_affected', 'date_of_birth', 'body_weight_kg',
                        'cycle_tracking_mode', 'cycle_length_days',
                        'cycle_last_period_start', 'pregnancy_due_date'];
end;
$$;

revoke all on function withdraw_health_data_consent() from public, anon;
grant execute on function withdraw_health_data_consent() to authenticated, service_role;
