-- Withdrawing health-data consent erases the Art 9 copies in the settings bag
-- too (issue #1374 round 4, the legal pre-review of the consent wording).
--
-- `withdraw_health_data_consent()` already nulls the consent stamp, height and
-- gender, erases the weight series, the heart-rate targets on the runner's own
-- plans and `hr_medication_affected`. The other Art 9 values in
-- `user_settings.prefs` were left to whichever client called it:
--
--   * `date_of_birth` (the health-use mirror, decisions § 718) and
--     `body_weight_kg` (the weight series' mirror, § 1811) were cleared by the
--     web Account and Body metrics pages and the app's Body metrics screen,
--     each in a separate write after the RPC;
--   * `cycle_tracking_mode`, `cycle_length_days`, `cycle_last_period_start`
--     and `pregnancy_due_date` were cleared only by the web Account page, and
--     only while `PUBLIC_CYCLE_PLANS_ENABLED` was on. A withdrawal from web
--     Body metrics or from the app left them stored.
--
-- So the privacy policy could not say what a withdrawal erases without
-- naming a page. The RPC now strips all six keys in the same transaction.
-- `body_weight_kg` goes only when consent had been given: onboarding can store
-- a weight from a runner who never consented, and a withdrawal call from a
-- runner with nothing to withdraw must not erase it (the clients apply the
-- same rule).
--
-- The backfill strips the date-of-birth mirror and the cycle and pregnancy
-- keys from every runner who holds no consent today. Every writer stores those
-- only while consent is granted, so a copy without consent is one a past
-- withdrawal left behind. `body_weight_kg` is not backfilled, for the reason
-- above.
--
-- `user_settings` is one row per runner and not a high-volume table
-- (docs/backend/migration_locks.md); the backfill is scoped to rows holding
-- one of the keys.

set search_path = public;

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
                 - array['hr_medication_affected', 'date_of_birth',
                         'cycle_tracking_mode', 'cycle_length_days',
                         'cycle_last_period_start', 'pregnancy_due_date']
                 - case when coalesce(v_had_consent, false)
                        then array['body_weight_kg'] else array[]::text[] end
   where user_id = v_uid
     and (prefs ?| array['hr_medication_affected', 'date_of_birth',
                         'cycle_tracking_mode', 'cycle_length_days',
                         'cycle_last_period_start', 'pregnancy_due_date']
          or (coalesce(v_had_consent, false) and prefs ? 'body_weight_kg'));
end;
$$;

revoke all on function withdraw_health_data_consent() from public, anon;
grant execute on function withdraw_health_data_consent() to authenticated, service_role;

update user_settings s
   set prefs = s.prefs - array['date_of_birth', 'cycle_tracking_mode',
                               'cycle_length_days', 'cycle_last_period_start',
                               'pregnancy_due_date']
 where s.prefs ?| array['date_of_birth', 'cycle_tracking_mode',
                        'cycle_length_days', 'cycle_last_period_start',
                        'pregnancy_due_date']
   and not exists (
     select 1 from user_profiles p
      where p.id = s.user_id and p.health_data_consent_at is not null
   );
