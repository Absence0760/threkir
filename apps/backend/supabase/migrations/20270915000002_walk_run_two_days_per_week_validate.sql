-- Validates the widened training_plans_days_per_week_check added NOT VALID in
-- 20270915000001 (migration_locks.md): SHARE UPDATE EXCLUSIVE, so reads and
-- writes carry on while it scans.
alter table training_plans validate constraint training_plans_days_per_week_check;
