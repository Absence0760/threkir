-- A direct NULL of the health-data consent stamp clears every consent-gated
-- value, exactly as withdraw_health_data_consent() does (decisions § 2542,
-- closing the gap it left open).
--
-- lock_consent_columns allows a direct `health_data_consent_at = null` as an
-- Art 7(3) withdrawal. The user_profiles transition trigger (20271227100008)
-- already erased heart rate and the food log on that transition, but height,
-- gender, the body_metrics weight series, the heart-rate targets on the
-- runner's plans and the Art 9 copies in the settings bag were cleared only by
-- the RPC, or by a client after it. A null written any other way left them
-- stored while the runner held no consent.
--
--   * private.health_consent_pref_keys() names the settings-bag keys that are
--     held only with consent, once.
--   * private.erase_consent_gated_values(uid) clears that set: height_cm and
--     gender on the profile, every body_metrics row, the heart-rate targets
--     on the runner's own plans, and those settings keys.
--   * private.health_consent_transition() runs it on every non-null to null
--     transition, beside private.erase_health_records.
--   * withdraw_health_data_consent() now nulls only the stamp and calls the
--     same function, so the RPC and a direct null cannot drift apart. It still
--     erases heart rate and food itself for a runner who never consented,
--     where there is no transition to fire the trigger.
--   * Settings keys a past direct null left behind are stripped from every
--     runner without consent: every writer stores them only under consent
--     (§ 718, § 2092, § 2542, migrations 20271226011374 and 20271229001390),
--     so a copy without consent is a leftover of a withdrawal.
--
-- Lock: functions only, plus a backfill of `user_settings` scoped to rows
-- holding one of the keys (one row per runner, not a high-volume table,
-- docs/backend/migration_locks.md).

create or replace function private.health_consent_pref_keys()
returns text[]
language sql
immutable
set search_path = pg_catalog
as $$
  select array['hr_medication_affected', 'date_of_birth', 'body_weight_kg',
               'cycle_tracking_mode', 'cycle_length_days',
               'cycle_last_period_start', 'pregnancy_due_date']::text[];
$$;

revoke execute on function private.health_consent_pref_keys() from public, anon, authenticated;
grant execute on function private.health_consent_pref_keys() to service_role;

create or replace function private.erase_consent_gated_values(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_keys text[] := private.health_consent_pref_keys();
begin
  if p_user_id is null then
    return;
  end if;
  -- `date_of_birth` stays: the column is the child-safety age record, not an
  -- Art 9 value (§ 721). Its health-use mirror is in v_keys.
  update public.user_profiles
     set height_cm = null, gender = null
   where id = p_user_id
     and (height_cm is not null or gender is not null);

  delete from public.body_metrics where user_id = p_user_id;

  update public.plan_workouts pw
     set target_hr_min_bpm = null, target_hr_max_bpm = null
    from public.plan_weeks pwk
    join public.training_plans tp on tp.id = pwk.plan_id
   where pw.week_id = pwk.id
     and tp.user_id = p_user_id
     and (pw.target_hr_min_bpm is not null or pw.target_hr_max_bpm is not null);

  update public.user_settings
     set prefs = prefs - v_keys
   where user_id = p_user_id
     and prefs ?| v_keys;
end;
$$;

revoke execute on function private.erase_consent_gated_values(uuid) from public, anon, authenticated;
grant execute on function private.erase_consent_gated_values(uuid) to service_role;

create or replace function private.health_consent_transition()
returns trigger
language plpgsql
security definer
set search_path = public, private
as $$
begin
  if new.health_data_consent_at is not null
     and (tg_op = 'INSERT' or old.health_data_consent_at is null) then
    perform private.restore_withheld_health_records(new.id);
  elsif tg_op = 'UPDATE'
     and old.health_data_consent_at is not null
     and new.health_data_consent_at is null then
    perform private.erase_health_records(new.id);
    perform private.erase_consent_gated_values(new.id);
  end if;
  return null;
end;
$$;

revoke execute on function private.health_consent_transition() from public, anon, authenticated;

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
  -- withdrawn state: a 0-row silent no-op here means special-category data
  -- lives on while the user believes it erased.
  insert into user_profiles (id)
  values (v_uid)
  on conflict (id) do update
    set health_data_consent_at = null;
  -- With consent on record the transition trigger has just erased heart rate,
  -- the food log and the consent-gated values. Without it there was no
  -- transition, so a hidden pre-gate backlog is erased here.
  if not coalesce(v_had_consent, false) then
    perform private.erase_health_records(v_uid);
  end if;
  -- The same set the trigger clears; a no-op after a transition.
  perform private.erase_consent_gated_values(v_uid);
end;
$$;

revoke all on function withdraw_health_data_consent() from public, anon;
grant execute on function withdraw_health_data_consent() to authenticated, service_role;

update user_settings s
   set prefs = s.prefs - private.health_consent_pref_keys()
 where s.prefs ?| private.health_consent_pref_keys()
   and not exists (
     select 1 from user_profiles p
      where p.id = s.user_id and p.health_data_consent_at is not null
   );
