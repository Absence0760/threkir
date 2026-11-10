# One-off ops tasks

A task is a SQL file a backend release runs exactly once, for the operator
calls that used to be pasted into the production SQL Editor (issue #1350,
decisions § 2430). It is reviewed in its PR like a migration.

- **Name:** `<YYYYMMDDHHMMSS>_<snake_name>.sql`, with a timestamp no other task
  uses. Tasks run oldest first.
- **Body:** plain SQL. No `begin` / `commit` (the sync runs each task in its own
  transaction and rolls it back on any error) and no psql meta-commands. It
  runs as the release's database role, as a migration does.
- **Result:** to record what it did, end with
  `select private.set_ops_task_result(jsonb_build_object('updated', <count>));`.
  The result lands in `private.ops_task_runs` and the step summary.
- **Never edit a task after it ran.** The ledger stores its sha256 and the next
  release fails on a changed file. Add a new task instead. A task that has not
  run yet (not in any release) can still be edited.
- **Dry run:** a dispatch with `dry_run` runs every pending task and rolls it
  back, so the summary previews its result.
- **A task gated on a sign-off** lands only once the sign-off is recorded:
  merging it is what runs it.

Example, `20271201000001_backfill_display_names.sql` (an illustration only:
that backfill waits on its CISO + counsel sign-off, so no such file is
committed):

```sql
select private.set_ops_task_result(
  jsonb_build_object('updated', private.backfill_display_names_from_provider())
);
```
