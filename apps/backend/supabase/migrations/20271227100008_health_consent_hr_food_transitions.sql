-- Giving or withdrawing health-data consent moves heart rate and the food
-- log with it (decisions § 2514).
--
--   * private.erase_health_records(uid) erases every copy of the runner's
--     heart rate and food log the database holds: the held backlog
--     (private.withheld_run_hr), the heart-rate keys and sidecar path on their
--     runs, bpm on their live and race pings, and every food_log row. The
--     Storage copies (the .hr.json.gz sidecars, per-point bpm inside each
--     track) are queued for the job worker as one `health_hr_erase` job.
--   * private.restore_withheld_health_records(uid) puts held heart rate back
--     on the runs it came from. Food needs no restore: its rows never moved,
--     the select policy simply shows them again.
--   * An AFTER trigger on user_profiles runs the right one on every consent
--     transition, so a direct null of the stamp (allowed by
--     lock_consent_columns as a withdrawal) erases exactly as the RPC does,
--     and a grant restores whatever path stamps it.
--   * withdraw_health_data_consent() keeps everything it did (20271226011374)
--     and also erases heart rate and food for a runner who never consented:
--     that is the one path by which a hidden pre-gate backlog is deleted on
--     the runner's own request. A runner who had consent is erased by the
--     trigger, once.
--
-- Lock: a trigger on user_profiles (not high-volume); functions only
-- otherwise. The erasure touches one runner's rows, through the runs and
-- food_log user indexes.

create or replace function private.erase_health_records(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, private
as $$
declare
  v_keys text[] := private.run_hr_metadata_keys();
begin
  if p_user_id is null then
    return;
  end if;
  -- The runs gate would otherwise hold what this deletes.
  perform set_config('app.health_erase', 'on', true);

  delete from private.withheld_run_hr where user_id = p_user_id;

  update public.runs
     set metadata = metadata - v_keys,
         hr_series_url = null
   where user_id = p_user_id
     and (metadata ?| v_keys or hr_series_url is not null);

  delete from public.food_log where user_id = p_user_id;

  update public.live_run_pings
     set bpm = null
   where user_id = p_user_id and bpm is not null;

  update public.race_pings
     set bpm = null
   where user_id = p_user_id and bpm is not null;

  insert into public.jobs (kind, payload)
  values ('health_hr_erase', jsonb_build_object('user_id', p_user_id));

  perform set_config('app.health_erase', '', true);
end;
$$;

revoke execute on function private.erase_health_records(uuid) from public, anon, authenticated;
grant execute on function private.erase_health_records(uuid) to service_role;

create or replace function private.restore_withheld_health_records(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, private
as $$
begin
  update public.runs r
     set metadata = w.hr || coalesce(r.metadata, '{}'::jsonb),
         hr_series_url = coalesce(r.hr_series_url, w.hr_series_url)
    from private.withheld_run_hr w
   where w.run_id = r.id
     and w.user_id = p_user_id;
  delete from private.withheld_run_hr where user_id = p_user_id;
end;
$$;

revoke execute on function private.restore_withheld_health_records(uuid) from public, anon, authenticated;
grant execute on function private.restore_withheld_health_records(uuid) to service_role;

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
  end if;
  return null;
end;
$$;

revoke execute on function private.health_consent_transition() from public, anon, authenticated;

create trigger user_profiles_health_consent_transition
  after insert or update of health_data_consent_at on public.user_profiles
  for each row execute function private.health_consent_transition();

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
