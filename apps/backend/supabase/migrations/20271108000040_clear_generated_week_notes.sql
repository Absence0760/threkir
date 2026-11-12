-- The plan generator used to save an English advice sentence into
-- `plan_weeks.notes` ("Race week — trust the work.", "Step-back week — …",
-- the couch-to-5K and ultra week lines) and into the ultra long-run and
-- race-day `plan_workouts.notes`. 20270908000001 cleared the workout
-- sentences that restated a structure; these were the advice left over
-- (decisions § 2348). Both clients now read the advice from the week's phase
-- and workouts and localize it, so the stored copy showed in English in every
-- locale, in a column the runner or a coach owns. The generator writes null
-- now; this clears what it already wrote.
--
-- Only exact generator output is matched, so a note a person wrote is never
-- touched. Neither table is one of the high-volume tables in
-- docs/backend/migration_locks.md and each predicate scopes the update to the
-- matching rows, so both run inline. The workout audit stamp trigger is held
-- off for the same reason as in 20270908000001: there is no auth.uid() here,
-- and it would erase a coach edit's provenance. plan_weeks has no audit
-- stamp; its template-redaction trigger only ever nulls notes.

update plan_weeks
set notes = null
where notes in (
  'Race week — trust the work.',
  'Taper — volume down, sharpness stays.',
  'Taper — volume comes down week by week; keep a little intensity.',
  'Step-back week — recover before the next build.',
  'Final week — it ends with your first 5K.',
  'Final week — you can run the distance continuously now.',
  'Take the walk breaks even when you feel good — they make the runs sustainable.',
  'Back-to-back weekend — Saturday and Sunday long runs.'
);

alter table plan_workouts disable trigger trg_stamp_plan_workout_audit;

update plan_workouts
set notes = null
where notes in (
  'Time on feet at easy effort: the duration is the target, not the pace. Practise race-day fuelling.',
  'Back-to-back, day one: easy effort, and tomorrow’s long run starts on tired legs.',
  'Back-to-back, day one: easy effort, and tomorrow''s long run starts on tired legs.',
  'Race day. Run by effort and fuel early — the clock looks after itself.'
);

alter table plan_workouts enable trigger trg_stamp_plan_workout_audit;
