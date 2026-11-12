-- The plan generator used to write an English sentence restating each
-- structured session into `plan_workouts.notes` ("Tempo: 6 km @ threshold.",
-- "5× 1000 m @ VO2 with 400 m jog.", the walk-run interval script). Both
-- clients render the structure itself from localized keys, so the sentence
-- showed under Notes as an English duplicate in every locale, and it sat in
-- a column the runner or a coach owns. The generator writes null now; this
-- clears the copies it already wrote.
--
-- Only exact generator output is matched, so a note a person wrote is never
-- touched. `plan_workouts` is not one of the high-volume tables in
-- docs/backend/migration_locks.md and the predicate scopes the update to the
-- matching rows, so it runs inline.
--
-- The audit stamp trigger is held off for the update: it would set
-- `updated_by` to null (there is no auth.uid() in a migration) and erase the
-- provenance of a workout a coach had edited. The plan_update notifier needs
-- no such care, since it returns early without a caller.

alter table plan_workouts disable trigger trg_stamp_plan_workout_audit;

update plan_workouts
set notes = null
where notes is not null
  and (
    notes ~ '^Walk 5 min, then run [0-9]+s / walk [0-9]+s × [0-9]+, walk 5 min\.$'
    or notes ~ '^Walk 5 min, run [0-9]+ min continuous, walk 5 min\. Graduation week\.$'
    or notes = 'Race day. Execute the plan.'
    or notes ~ '^Tempo: [0-9]+ km @ threshold\.$'
    or notes ~ '^[0-9]+× [0-9]+ m @ VO2 with [0-9]+ m jog\.$'
    or notes ~ '^[0-9]+ km @ goal marathon pace\.$'
  );

alter table plan_workouts enable trigger trg_stamp_plan_workout_audit;
