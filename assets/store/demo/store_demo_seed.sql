-- The store-screenshot demo account, loaded into the LOCAL Supabase stack the
-- store-screenshots workflow starts. Never applied anywhere else.
--
-- What it holds is what the capture photographs: an active half-marathon plan
-- whose window puts today in week 6 with the race six weeks out, every past
-- session done, and one coach conversation on that plan. The runs are not
-- here; the capture writes them into the device's run store, because a run's
-- track is a file in Storage that SQL cannot seed (seed.sql § 3).
--
-- Separate from seed.sql's runner@test.com on purpose: that account carries
-- the owner's name and years of fixture rows other suites assert on, and a
-- store listing must show neither.
--
-- The plan id and the account's email and password are mirrored in
-- apps/mobile_android/integration_test/store/demo_data.dart; change them
-- together. Every date is relative to current_date, so a capture on any day
-- shows the same mid-plan picture. Re-running the file replaces the account's
-- plan and thread rather than adding a second copy.

BEGIN;

INSERT INTO auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change_token_current,
  email_change, phone, phone_change, phone_change_token, reauthentication_token,
  is_sso_user, is_anonymous,
  raw_app_meta_data, raw_user_meta_data
) VALUES (
  '00000000-0000-0000-0000-000000000000',
  '5d000000-0000-4000-8000-000000000001',
  'authenticated', 'authenticated',
  'store-demo@threkir.test',
  extensions.crypt('storedemo', extensions.gen_salt('bf')),
  now(), now(), now(),
  '', '', '', '',
  '', NULL, '', '', '',
  false, false,
  '{"provider":"email","providers":["email"]}',
  '{"email_verified":true}'
) ON CONFLICT (id) DO NOTHING;

INSERT INTO auth.identities (
  id, provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at
) VALUES (
  '5d000000-0000-4000-8000-000000000001',
  '5d000000-0000-4000-8000-000000000001',
  '5d000000-0000-4000-8000-000000000001',
  jsonb_build_object('sub', '5d000000-0000-4000-8000-000000000001',
                     'email', 'store-demo@threkir.test', 'email_verified', true),
  'email', now(), now(), now()
) ON CONFLICT DO NOTHING;

-- Past every gate a real account clears before the screens shown here render:
-- the Art 8 age and terms stamps, onboarding, the coach's AI disclosure at the
-- current version, and Pro so the coach is not capped mid-conversation.
INSERT INTO user_profiles (id, display_name, preferred_unit, subscription_tier,
                           age_confirmed_at, terms_accepted_at, onboarded_at,
                           coach_consent_at, ai_disclosure_version, health_data_consent_at,
                           height_cm, date_of_birth, gender)
VALUES ('5d000000-0000-4000-8000-000000000001', 'Sam Rivera', 'km', 'pro',
        now(), now(), now(),
        now(), ai_disclosure_current_version(), now(),
        170.0, '1991-04-18', 'female')
ON CONFLICT (id) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  subscription_tier = EXCLUDED.subscription_tier,
  coach_consent_at = EXCLUDED.coach_consent_at,
  ai_disclosure_version = EXCLUDED.ai_disclosure_version;

INSERT INTO user_settings (user_id, prefs) VALUES (
  '5d000000-0000-4000-8000-000000000001',
  jsonb_build_object(
    'preferred_unit', 'km',
    'week_start_day', 'monday',
    'resting_hr_bpm', 52,
    'max_hr_bpm', 188,
    'weekly_mileage_goal_m', 40000,
    'coach_personality', 'supportive'
  )
) ON CONFLICT (user_id) DO UPDATE SET prefs = EXCLUDED.prefs;

DO $$
DECLARE
  v_user  constant uuid := '5d000000-0000-4000-8000-000000000001';
  v_plan  constant uuid := '5d000000-0000-4000-8000-0000000000a1';
  v_race  constant text := 'Riverside Half Marathon';
  -- The Monday five weeks before this one, so today falls in week 6 of 12.
  v_start constant date := date_trunc('week', current_date)::date - 35;
  v_week  uuid;
  v_phase plan_phase;
  v_date  date;
  v_kind  workout_kind;
  v_dist  integer;
  v_pace  integer;
  v_zone  text;
  v_struct jsonb;
  v_notes text;
  w int;
  d int;
BEGIN
  DELETE FROM training_plans WHERE id = v_plan;

  INSERT INTO training_plans (
    id, user_id, name, goal_event, goal_distance_m, goal_time_seconds,
    start_date, end_date, days_per_week, vdot, current_5k_seconds,
    status, source, rules, notes
  ) VALUES (
    v_plan, v_user, v_race, 'distance_half', 21097.5, 6300,
    v_start, v_start + 83, 5, 45.0, 1500,
    'active', 'generated',
    '["Most of the week stays easy","Long run on Sundays","Add no more than 10% a week"]'::jsonb,
    'Goal: 1:45:00 at the Riverside Half Marathon.'
  );

  FOR w IN 0..11 LOOP
    v_phase := CASE
      WHEN w < 4 THEN 'base'
      WHEN w < 8 THEN 'build'
      WHEN w < 10 THEN 'peak'
      WHEN w < 11 THEN 'taper'
      ELSE 'race'
    END;
    INSERT INTO plan_weeks (plan_id, week_index, phase)
    VALUES (v_plan, w, v_phase)
    RETURNING id INTO v_week;

    FOR d IN 0..6 LOOP
      v_date := v_start + w * 7 + d;
      v_struct := NULL;
      v_notes := NULL;
      -- Monday rest, Tuesday quality, Wednesday easy, Thursday tempo,
      -- Friday rest, Saturday recovery, Sunday long; race week tapers into
      -- the race on its last Sunday.
      CASE d
        WHEN 0, 4 THEN
          v_kind := 'rest'; v_dist := NULL; v_pace := NULL; v_zone := NULL;
        WHEN 1 THEN
          IF w < 4 OR w >= 10 THEN
            v_kind := 'easy'; v_dist := 6000; v_pace := 350; v_zone := 'E';
          ELSE
            v_kind := 'interval'; v_dist := 9000; v_pace := 262; v_zone := 'I';
            v_struct := '{"warmup":{"distance_m":2000,"pace":"easy"},"repeats":{"count":5,"distance_m":800,"pace_sec_per_km":262,"recovery_distance_m":400,"recovery_pace":"jog"},"cooldown":{"distance_m":1500,"pace":"easy"}}'::jsonb;
            v_notes := '5 x 800 m at interval pace, 400 m jog between.';
          END IF;
        WHEN 2 THEN
          v_kind := 'easy'; v_dist := CASE WHEN w = 11 THEN 5000 ELSE 7000 END;
          v_pace := 350; v_zone := 'E';
        WHEN 3 THEN
          IF w = 11 THEN
            v_kind := 'easy'; v_dist := 4000; v_pace := 340; v_zone := 'E';
            v_notes := 'Easy with four 20-second strides.';
          ELSE
            v_kind := 'tempo'; v_dist := 8000 + least(w, 8) * 250; v_pace := 285; v_zone := 'T';
            v_struct := '{"warmup":{"distance_m":2000,"pace":"easy"},"steady":{"distance_m":4000,"pace_sec_per_km":285},"cooldown":{"distance_m":2000,"pace":"easy"}}'::jsonb;
            v_notes := '4 km at threshold between an easy warm-up and cool-down.';
          END IF;
        WHEN 5 THEN
          v_kind := 'recovery'; v_dist := 5000; v_pace := 365; v_zone := 'E';
        ELSE
          IF w = 11 THEN
            v_kind := 'race'; v_dist := 21098; v_pace := 298; v_zone := 'MP';
          ELSIF w = 10 THEN
            v_kind := 'long'; v_dist := 12000; v_pace := 345; v_zone := 'E';
          ELSE
            v_kind := 'long'; v_dist := 10000 + least(w, 9) * 1000; v_pace := 345; v_zone := 'E';
          END IF;
      END CASE;

      INSERT INTO plan_workouts (
        week_id, scheduled_date, kind, target_distance_m, target_pace_sec_per_km,
        target_pace_tolerance_sec, pace_zone, structure, notes,
        race_name, race_priority,
        manually_completed, completed_at
      ) VALUES (
        v_week, v_date, v_kind, v_dist, v_pace,
        CASE WHEN v_pace IS NULL THEN NULL ELSE 15 END, v_zone, v_struct, v_notes,
        CASE WHEN v_kind = 'race' THEN v_race END,
        CASE WHEN v_kind = 'race' THEN 'A' END,
        v_kind <> 'rest' AND v_date < current_date,
        CASE WHEN v_kind <> 'rest' AND v_date < current_date
             THEN v_date + time '07:30' END
      );
    END LOOP;

    UPDATE plan_weeks SET target_volume_m = (
      SELECT coalesce(sum(target_distance_m), 0) FROM plan_workouts WHERE week_id = v_week
    ) WHERE id = v_week;
  END LOOP;

  -- Assistant turns are written by the coach handler with the service role;
  -- this file runs as postgres, which is the same trust level.
  DELETE FROM coach_messages WHERE user_id = v_user;
  INSERT INTO coach_messages (user_id, plan_id, role, content, created_at) VALUES
    (v_user, v_plan, 'user',
     'My legs felt heavy on Sunday''s long run. Should I still do Thursday''s tempo?',
     now() - interval '14 minutes'),
    (v_user, v_plan, 'assistant',
     E'You''ve completed every session for five weeks, and Sunday''s long run was right on your easy target, so some heaviness two days later is normal.\n\n'
     'Keep Thursday''s tempo, with two changes:\n\n'
     '- **Warm up for 15 minutes** instead of 10, and only start the 4 km at threshold once your legs feel loose.\n'
     '- **Hold 4:50/km**, not 4:45. You still get the threshold work without digging a hole before Sunday.\n\n'
     'If your legs are still heavy after the first kilometre at pace, make it an easy run. One tempo won''t change race day; arriving tired might.',
     now() - interval '13 minutes'),
    (v_user, v_plan, 'user',
     'Am I still on track for 1:45?',
     now() - interval '3 minutes'),
    (v_user, v_plan, 'assistant',
     E'Yes. Your last two tempo runs point to about **1:44 to 1:46** for the half, which puts 1:45 well within reach.\n\n'
     'The next four weeks are the peak of the plan. Keep the long runs easy and you''ll arrive at the start line fresh.',
     now() - interval '2 minutes');
END $$;

COMMIT;
