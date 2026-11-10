# Migration locks — the online-DDL playbook

Migrations run twice with wildly different stakes. Locally (`supabase db reset`)
and on CI they hit a fresh, near-empty database where every lock is released in
microseconds and a full-table rewrite is invisible. In production `supabase db
push` (or the release workflow's `apply-pending-migrations.sh`) applies the same
SQL to a **live, populated** instance that the web app, Edge Functions, and the
Go job worker are reading and writing continuously. A statement that takes an
`ACCESS EXCLUSIVE` lock or scans a big table there **blocks every reader and
writer for the duration** — that is downtime.

This file is the playbook for writing DDL that stays online against prod. It is
the durable companion to the read-only `/audit/migration-locks` command (which
classifies the *existing* migrations by lock impact) and to `/safe-migration`
(which lands a new one). When you write a migration that adds a constraint or
touches many rows, follow the patterns here **before** it ships — a blocking
migration cannot be edited after it applies (the schema only moves forward), so
the cost of getting it wrong is a maintenance-window remediation, not a revert.

This is about **lock impact and online-safety only**. Whether the constraint or
index *should* exist (normalization, FK integrity, index choice) belongs to
`/audit/db-design`; type-drift belongs to `/audit/schema-drift`; RLS belongs to
`/audit/rls`.

## The high-volume tables

The blast radius of a blocking statement is proportional to the row count of the
table it locks. These are the tables that are big now or grow unboundedly, and
where an online-unsafe statement is real downtime:

`runs`, `notifications`, `jobs`, `live_run_pings`, `race_pings`,
`segment_efforts`, `run_kudos`, `run_comments`, `run_photos`, `webhook_events`,
`rate_limits`.

`jobs` earns its place for a different reason than sheer row count: the Go
`job_worker` polls it continuously, so a blocking validation scan on the
`jobs_kind_chk` allow-list (the common `DROP CONSTRAINT … , ADD CONSTRAINT …
CHECK (…)` widening when a new job kind lands) stalls job processing until the
scan finishes. Widen it with `ADD … NOT VALID` + `VALIDATE`, same as
`notifications` (#394 follow-up — the guard now enforces this on `jobs`).

`runs` is the highest-volume table and the one to be most careful with. A
constraint or backfill on a small, bounded config table (`event_pricing`,
`fundraisers`, `session_plan_items`, `race_listings`, `clubs`, `user_profiles`,
…) is cheap — the online form there is ceremony, not safety, and the forward
guard deliberately does not demand it.

## CHECK constraints — `NOT VALID` then `VALIDATE`

A single-step `ADD CONSTRAINT … CHECK (…)` holds `ACCESS EXCLUSIVE` while it
scans **every existing row** to prove the constraint holds. Split it:

```sql
-- Migration 1: instant. Takes ACCESS EXCLUSIVE only for a metadata flip; new
-- and updated rows are enforced immediately, existing rows are not yet checked.
alter table runs
  add constraint runs_activity_type_check
  check (activity_type in ('run', 'walk', 'hike', 'cycle', 'stroller'))
  not valid;

-- Migration 2 — a SEPARATE file, ideally a low-traffic window: scans existing
-- rows under SHARE UPDATE EXCLUSIVE, so reads and writes proceed during the
-- scan. In the same file as migration 1 it would scan under migration 1's lock.
alter table runs
  validate constraint runs_activity_type_check;
```

After `VALIDATE` the constraint is indistinguishable from one added in a single
step.

**The split has to be across migrations, or it buys nothing.** Each migration
file is applied inside one transaction (`apply-pending-migrations.sh` wraps it
in `begin;` … `commit;` so the ledger row commits atomically with the SQL, and
the CLI wraps a file the same way — that is why `CREATE INDEX CONCURRENTLY`
errors as apply-time DDL, below). A lock taken by DDL is held until the
transaction ends, so in one file the `ADD … NOT VALID`'s own `ACCESS EXCLUSIVE`
— or a preceding `DROP CONSTRAINT` or `ADD COLUMN` — is *still held* while the
`VALIDATE` scans. `SHARE UPDATE EXCLUSIVE` is subsumed by it, never a downgrade.
Same-file, the two-step and the single step block writers for the identical
duration; only the `VALIDATE` in a **later** migration, in its own transaction,
lets writes through during the scan.
`check_migration_online_safety.mjs` fails both shapes on a guarded table.

**Widening an existing IN-list is the common case** (e.g. re-emitting
`notifications_kind_check` to allow a new notification kind). Every existing row
already satisfies the wider set, so the re-validation scan is pure waste — but
the single-step `DROP CONSTRAINT … , ADD CONSTRAINT … CHECK (…)` still takes the
scan. Use `ADD … NOT VALID` + `VALIDATE` there too.

## FK constraints — `NOT VALID` then `VALIDATE`, per table, split across migrations

Adding (or drop-and-recreating) a foreign key in one step scans the whole child
table to prove every row's reference resolves, under a lock that also grabs a
lock on the *referenced* table. The online form is identical in shape to the
CHECK case, and `ADD … FOREIGN KEY … NOT VALID` is effectively instant:

```sql
-- Migration 1: instant metadata change per table.
alter table runs
  drop constraint runs_user_id_fkey,
  add constraint runs_user_id_fkey
    foreign key (user_id) references auth.users (id) on delete cascade
    not valid;

-- Migration 2, quiet window: validate under SHARE UPDATE EXCLUSIVE.
alter table runs
  validate constraint runs_user_id_fkey;
```

Two extra rules for FKs:

- **One table per migration when several are involved.** A migration that walks
  eight tables serializing eight `ACCESS EXCLUSIVE` operations widens both the
  blocking window and the deadlock surface against live app traffic. Split the
  add-`NOT VALID` steps across per-table migrations (or at least keep each
  table's scan in its own `VALIDATE`).
- **Every new FK ships with a covering index** on the referencing column, in
  the same release as the FK. When the file that adds the FK also adds the
  column (`ACCESS EXCLUSIVE`), build the index in its own later file (§ Index
  builds — alone in their file) — an unindexed FK forces a sequential scan of
  the child table on every delete/update of the parent, and `fk_covering_index_test.sql`
  fails the pgtap job without it. See `apps/backend/CLAUDE.md` § "New policies
  wrap auth.* …".

`SET NOT NULL` on an existing big table has the same scan hazard: prefer adding a
`NOT VALID CHECK (col IS NOT NULL)`, `VALIDATE` it, then `SET NOT NULL` (PG12+
skips its own scan by trusting the validated constraint).

## One table per migration

Each migration file is applied as ONE transaction (`apply-pending-migrations.sh`
wraps it in `begin; … commit;` with its ledger row, and the Supabase CLI wraps it
the same way), and every lock a statement takes is held until that commit. So a
file that takes `ACCESS EXCLUSIVE` on `events`, then `race_sessions`, then
`race_pings`, then `notifications` holds all four until its last statement, and
`race_pings` inserts stall for the whole file, not for the instant its own
`ALTER` needed. Several strong locks in sequence also widen the deadlock surface:
a run save that holds a `runs` row lock and then inserts into `jobs` deadlocks
against a migration that holds `jobs` and wants `runs`.

Write one table's strong-lock DDL per file, ordered so each file's dependencies
come first (columns before the `language sql` functions and views that read
them, an index before the job that relies on it). `20271121002400` and
`20271117002392` were split this way before `backend@1.0.38` shipped
([decisions § 2428](../architecture/decisions.md)).

## Index builds — alone in their file

A non-concurrent `CREATE INDEX` reads the whole heap under `SHARE`: writers wait
for the scan, readers do not. That holds only when nothing stronger is held. If
the same file already took `ACCESS EXCLUSIVE` on the table (an `ADD COLUMN`, a
`DROP`/`ADD CONSTRAINT`, a `DROP TRIGGER`, a policy change), that lock is still
held during the build, and **readers wait for the scan too**. A partial index
whose predicate matches no row is still a full heap scan.

Put the index in its own later migration with `create index if not exists`:

```sql
-- 20271124002408: catalogue-only, a brief ACCESS EXCLUSIVE.
alter table notifications add column course_alert_id uuid;

-- 20271124100001: the build, alone, under SHARE.
create index if not exists notifications_course_alert_id
  on notifications (course_alert_id) where course_alert_id is not null;
```

The forward guard enforces this on the high-volume tables
(`index_under_exclusive`, below).

## Lock timeout on apply

`apps/backend/scripts/apply-pending-migrations.sh` opens every file's
transaction with `set local lock_timeout = '5s'`. Without it, an `ACCESS
EXCLUSIVE` request queued behind a long reader (a report, a stuck idle-in-
transaction session) waits indefinitely, and every later query on that table
queues behind the request, so a migration that needs the lock for a millisecond
stops the table for as long as the reader runs. With it, the waiting statement
fails with SQLSTATE `55P03` after 5 s, the whole file rolls back (its ledger row
is in the same transaction, so the ledger stays honest), and the script retries
the file from the top: up to 5 attempts, sleeping 5, 10, 20 and 40 s between
them. Any other error is not retried. When the last attempt also times out, the
deploy fails with an `::error::` naming the version; find the holder in
`pg_stat_activity` / `pg_locks`, let it finish or end it, and re-run the
release.

`MIGRATION_LOCK_TIMEOUT`, `MIGRATION_LOCK_ATTEMPTS` and `MIGRATION_RETRY_BASE_S`
override the three numbers. A file that takes several locks either gets them all
within the timeout or gets none of them, which is another reason to keep each
file to one table. `apply_pending_migrations.test.mjs` pins the contract against
a stub `psql`.

## Large backfills — one pass, batched, off the hot table

A single unbounded `UPDATE`/`DELETE` over a big table takes a row lock on every
touched row, bloats the table, and holds those locks for the whole statement.

- **Collapse multiple passes into one.** Rewriting every row of `runs` twice in
  one transaction (once per column) is two full-table rewrites; do the columns
  in a single `UPDATE … SET a = …, b = …`.
- **Batch in id-range chunks, out of band.** For a genuinely large backfill,
  loop over id ranges (`… WHERE id BETWEEN $lo AND $hi`) in separate
  transactions so each holds locks briefly and autovacuum can keep up, rather
  than one statement that rewrites the whole table under sustained locks. On the
  highest-volume tables prefer running the batched backfill as a maintenance
  step (or a job) rather than inline in the migration.
- **Scope the backfill.** `UPDATE … WHERE <predicate>` that touches only the
  rows that actually need it beats an unconditional whole-table `UPDATE`.
- Backfills against small, bounded tables are fine inline — the concern is the
  high-volume set above.

## Lock reference

| DDL | Lock | Online against a big table? |
|---|---|---|
| `ADD CONSTRAINT … CHECK/FK` (single step) | `ACCESS EXCLUSIVE` + full-row scan | **No** — blocks all reads+writes for the scan |
| `ADD CONSTRAINT … NOT VALID` | brief `ACCESS EXCLUSIVE`, no scan | Yes |
| `VALIDATE CONSTRAINT` | `SHARE UPDATE EXCLUSIVE` | Yes — reads+writes proceed, **but only in its own migration**: a stronger lock taken earlier in the same file is still held during the scan |
| `ADD COLUMN … DEFAULT <constant>` | brief `ACCESS EXCLUSIVE`, no rewrite (PG11+) | Yes |
| `ADD COLUMN … DEFAULT <volatile>` (`now()`, `gen_random_uuid()`, a function) | `ACCESS EXCLUSIVE` + full rewrite | **No** |
| `SET NOT NULL` | `ACCESS EXCLUSIVE` + full scan | **No** — use the `NOT VALID CHECK` route |
| `ALTER COLUMN … TYPE` | `ACCESS EXCLUSIVE` + full rewrite + index rebuild | **No** — add-new-column + batched backfill + swap |
| `CREATE INDEX` | `SHARE` for the build's full heap scan (blocks writes, not reads) | Only alone in its file — after an `ACCESS EXCLUSIVE` on the same table in that file, reads block too (§ Index builds). `CONCURRENTLY` can't run in the wrapped txn (see below) |
| `DROP TRIGGER [IF EXISTS]` / `CREATE`/`DROP`/`ALTER POLICY` | `ACCESS EXCLUSIVE`, catalogue-only | Yes if the file commits promptly — the lock is held to commit |
| `CREATE TRIGGER` | `SHARE ROW EXCLUSIVE`, catalogue-only | Yes for readers, no for writers — blocks concurrent INSERT/UPDATE/DELETE on that table only, for an O(1) change |
| `CREATE OR REPLACE FUNCTION` (incl. a trigger's function) | none on any table | Yes — swapping a trigger's *body* never touches the table the trigger is on |
| `GRANT` / `REVOKE` (table- or column-level) | none on the target relation — an `AccessShareLock` on the catalogue object only | Yes — no scan, no rewrite, no reader or writer blocked |
| unbounded `UPDATE`/`DELETE` | row locks on every touched row | **No** — batch in id-range chunks |

The `GRANT`/`REVOKE` row is measured on PG 17.6, not inferred: a table-level
`REVOKE` plus a column-level `GRANT` in one transaction holds no `pg_locks` row
against the relation at all. A privilege change is therefore never the reason a
migration needs the online-DDL machinery — but it still needs the **shape** to be
right, because a column-level revoke under a table-level grant revokes nothing
(see `apps/backend/CLAUDE.md` § A column-level `revoke` is a no-op under a
table-level grant, and `check_migration_column_revoke_noop.mjs`).

`SHARE ROW EXCLUSIVE` does **not** conflict with `ACCESS SHARE` or `ROW SHARE`,
and a *queued* request only blocks later requests that conflict with it — so a
`CREATE TRIGGER` waiting behind a long write still lets every reader through.
That is what makes it acceptable on a populated table where an `ACCESS
EXCLUSIVE` statement of the same duration would not be (`20270608_001`, the
`direct_messages` send throttle, measured on PG 17.6).

`CREATE INDEX CONCURRENTLY` / `DROP INDEX CONCURRENTLY` / `REINDEX CONCURRENTLY`
**cannot run inside a transaction block**, and the Supabase apply path is prone
to wrapping a migration file in one — so a `CONCURRENTLY` statement as apply-time
DDL errors. The safe baseline in this repo is concurrent work deferred inside a
`pg_cron` job body (`20260602_001`, `20260706_001` do `refresh materialized view
concurrently …`), which executes later as a scheduled job, not as apply-time DDL.
A failed `CONCURRENTLY` build also leaves an `INVALID` index that `IF NOT EXISTS`
won't rebuild — it needs a manual `DROP INDEX` + retry.

## Worked examples — what NOT to do, and the fix

Three shipped migrations predate this playbook and took blocking locks. They are
already applied, so they are **not** edited (the schema only moves forward); they
stand as the reference for the corrected pattern, and the forward guard
grandfathers them by name.

- **#411 — `20261210_001_status_policy_check_constraints.sql`** adds four
  first-time CHECK constraints (`event_attendees.status`, `clubs.join_policy`,
  `club_members.status`, `events.recurrence_freq`) in single steps. Each scans
  its table under `ACCESS EXCLUSIVE`. The corrected pattern: `ADD … NOT VALID`
  then a later `VALIDATE`. (These four are on bounded social tables, so the real
  blast radius was small — but the pattern is the thing.)
- **#410 — `20260728_001_cascade_auth_users_fks.sql`** drop-and-recreates the
  `auth.users` FK on eight tables (including `runs`) in one migration, each a
  single-step validating add, serializing eight `ACCESS EXCLUSIVE` operations.
  The corrected pattern: `drop + add … NOT VALID` per table, each `VALIDATE`
  split out, and the `runs` one scheduled for a quiet window.
- **#409 — `20261207_001_promote_activity_type_is_dnf.sql`** makes four
  full-table passes over `runs` in one transaction — two backfill `UPDATE`s
  (`activity_type`, `is_dnf`), a single-step `ADD CONSTRAINT … CHECK`, and a
  third `UPDATE` stripping the two keys from the `metadata` bag. The two column
  `ADD`s themselves are the safe constant-default fast path; the hazard is the
  three whole-`runs` `UPDATE`s (collapse the two backfills into one pass, run
  the metadata-strip batched/out-of-band) plus the single-step CHECK
  (`NOT VALID` + `VALIDATE`).

## Forward guard

`apps/backend/scripts/check_migration_online_safety.mjs` fails CI on three
shapes that scan a high-volume table under a lock that blocks more than the scan
needs: a CHECK or FK added without `NOT VALID` (`blocking_add`), a `VALIDATE
CONSTRAINT` in the same file as the DDL whose lock is still held
(`same_txn_validate`), and a non-concurrent `CREATE INDEX` on a table the same
file already took `ACCESS EXCLUSIVE` on (`index_under_exclusive`; the error names
the table and the earlier statement). It
scans **every** committed migration on every run, and it is deliberately narrow
only in the table set it guards (constraints on small config tables don't trip
it). It runs in the `parity-types` CI job right after the version-uniqueness
guard, and `check_migration_online_safety.test.mjs` pins the parse + detection
logic. Run it locally before pushing a new migration:

```bash
node apps/backend/scripts/check_migration_online_safety.mjs
```

**Adding a migration requires no edit to the guard.** The already-applied
violations are grandfathered one at a time in `GRANDFATHERED_VIOLATIONS`, each
naming a `{filename, kind, table, constraint}` tuple (for
`index_under_exclusive`, `constraint` is the index's name), rather than by a version
cutoff. The `kind` is part of the key so an entry vouching for a blocking add
cannot silently also vouch for a same-transaction validate in the same file. The
cutoff it replaces
had to be bumped past the newest migration by its own test, and the bump was
what removed that migration from the scan, so the scanned set was empty at rest
([decisions § 775](../architecture/decisions.md)). A name cannot do that: it
exempts exactly the constraint it spells, and an entry that matches nothing in
the tree fails the guard rather than sitting there as unused cover.

If it flags a constraint you are certain is safe to validate inline (a genuinely
small or empty table the guard's table set happens to include), add that one
constraint to `GRANDFATHERED_VIOLATIONS` and say why in the PR — a named entry
is the conscious, reviewed escape hatch, not a silent bypass. For a
`same_txn_validate` the normal answer is not an entry at all: move the
`VALIDATE CONSTRAINT` into its own migration file.

## Pre-merge checklist

Before merging a migration, for each statement:

- [ ] `ADD CONSTRAINT … CHECK/FK` on a high-volume table → `NOT VALID` + a
      `VALIDATE CONSTRAINT` in a **later migration file** — same-file, the
      VALIDATE scans under the lock the ADD is still holding.
- [ ] New FK → covering index in the same release; multi-table work split one
      table per migration.
- [ ] `CREATE INDEX` on a high-volume table → in a file that took no `ACCESS
      EXCLUSIVE` on that table (no `ADD COLUMN`, constraint swap, `DROP
      TRIGGER` or policy change before it).
- [ ] `SET NOT NULL` on a big table → `NOT VALID CHECK (col IS NOT NULL)` +
      `VALIDATE` + `SET NOT NULL`, not a raw `SET NOT NULL`.
- [ ] `ADD COLUMN` default is a **constant** (fast path), never a volatile
      expression on a populated table.
- [ ] No `ALTER COLUMN … TYPE` on a populated big table (add-column + batched
      backfill + swap instead).
- [ ] Backfills collapsed into one pass, scoped by predicate, and batched /
      out-of-band on the high-volume tables.
- [ ] No `CREATE INDEX CONCURRENTLY` as apply-time DDL (it errors in the wrapped
      transaction); defer concurrent work to a `pg_cron` body.
- [ ] `node apps/backend/scripts/check_migration_online_safety.mjs` passes.
- [ ] Both row-type generators re-run and the docs-hygiene sweep done (see
      `apps/backend/CLAUDE.md` § Migrations).
