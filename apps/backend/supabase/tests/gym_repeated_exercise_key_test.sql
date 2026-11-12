-- Pins the negative recorded in decisions § 1286 (re-verified § 1489): two rows
-- of ONE parent may share an exercise key, so no uniqueness may cover that pair.
--
-- A lifter who programs a heavy top set and then a back-off block has two
-- `gym_routine_exercises` rows in one routine under one `exercise_key`, and
-- every set of one exercise in one session is a `gym_sets` row under the same
-- pair. Both shapes are named, supported, and already paid for --
-- `expandRoutineSteps` orders the two blocks by `position` and
-- `computeRoutineAdherence` matches on `(exerciseKey, stepIndex)` precisely so
-- they do not collapse onto one logged set. A unique index over either pair
-- makes those routines unrepresentable, and it fails at `db push` against the
-- populated table with a 23505 rather than at review.
--
-- The guard is BEHAVIOURAL, not nominal. It does not name an index; it derives
-- from `pg_index` whether any uniqueness on the table covers a column set that
-- is a SUBSET of the pair, because a subset forbids strictly more than the pair
-- does -- a bare `unique (exercise_key)` refuses the same routine and would sail
-- past a guard keyed on the literal name or the literal column list. Three
-- shapes the derivation deliberately treats as offending:
--
--   * a PARTIAL unique index. Its predicate narrows which rows must be unique,
--     it does not narrow what uniqueness MEANS, so the top-set-then-back-off
--     routine is still refused for every lifter the predicate admits. The
--     predicate's own columns are therefore not read.
--   * an EXPRESSION key column, which `indkey` records as 0 and which this
--     cannot decompose. Treated as capable of ranging over the key column
--     (`unique (routine_id, lower(exercise_key))` forbids exactly the shape),
--     so an index whose every other key column is in the pair fails closed.
--   * an EXCLUSION constraint. `exclude (routine_id with =, exercise_key with =)`
--     is uniqueness under another name and its backing index is NOT flagged
--     `indisunique`, so reading unique indexes alone would miss it.
--
-- INCLUDE columns are read past (`indnkeyatts`): a payload column does not
-- participate in the uniqueness, so `unique (exercise_key) include (routine_id)`
-- is the bare subset it looks like. Unique CONSTRAINTS need no separate pass --
-- every one is implemented by a unique index, which is what `pg_index` holds.

begin;

select plan(9);

create or replace function pg_temp.uniqueness_over_subset(tbl regclass, cols text[])
returns text language sql stable as $fn$
  select coalesce(string_agg(i.relname || ': ' || pg_get_indexdef(ix.indexrelid),
                             '; ' order by i.relname), '')
  from pg_index ix
  join pg_class i on i.oid = ix.indexrelid
  where ix.indrelid = tbl
    and (ix.indisunique
         or exists (select 1 from pg_constraint x
                    where x.conrelid = tbl and x.contype = 'x'
                      and x.conindid = ix.indexrelid))
    and (select bool_and(k.attnum = 0 or a.attname = any (cols))
         from unnest((ix.indkey::int2[])[0:ix.indnkeyatts - 1]) k(attnum)
         left join pg_attribute a
           on a.attrelid = ix.indrelid and a.attnum = k.attnum);
$fn$;

-- ── The shape, saved ────────────────────────────────────────────────────────
-- Asserting the catalogue alone would pass against a table nobody can write
-- the pattern to. These two write it.

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('00000000-0000-0000-0000-0000000d0001'::uuid, 'authenticated', 'authenticated',
        'lifter@backoff.local', '', now(), now());

insert into user_profiles (id, display_name)
values ('00000000-0000-0000-0000-0000000d0001', 'Lifter');

select tests.confirm_consent();

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"00000000-0000-0000-0000-0000000d0001"}';

insert into gym_routines (id, author_id, title)
values ('00000000-0000-0000-0000-0000000d1001',
        '00000000-0000-0000-0000-0000000d0001', 'Top set then back-off');

-- 1. The routine that motivated the negative: one lift programmed twice, a
--    heavy single and then a lighter block, ordered by `position`.
select lives_ok(
  $$insert into gym_routine_exercises (routine_id, exercise_name, position)
    values ('00000000-0000-0000-0000-0000000d1001', 'Back Squat', 0),
           ('00000000-0000-0000-0000-0000000d1001', 'Back Squat', 1)$$,
  'one routine holds two blocks of one lift — the heavy-top-set-then-back-off pattern'
);

insert into gym_workouts (id, user_id, title, started_at)
values ('00000000-0000-0000-0000-0000000d2001',
        '00000000-0000-0000-0000-0000000d0001', 'Squat day', now());

-- 2. The same pair on the log side, where repetition is not a pattern but the
--    table's whole purpose: `set_index` exists to order sets of one exercise.
select lives_ok(
  $$insert into gym_sets (workout_id, set_index, exercise_name, reps, weight_kg)
    values ('00000000-0000-0000-0000-0000000d2001', 0, 'Back Squat', 3, 140),
           ('00000000-0000-0000-0000-0000000d2001', 1, 'Back Squat', 8, 100)$$,
  'one workout holds two sets of one lift'
);

reset role;

-- ── The catalogue ───────────────────────────────────────────────────────────

-- 3.
select is(
  pg_temp.uniqueness_over_subset('public.gym_routine_exercises'::regclass,
                                 array['routine_id', 'exercise_key']),
  '',
  'no uniqueness on gym_routine_exercises covers a subset of '
  '(routine_id, exercise_key) — one would refuse a legitimate routine at save '
  'time on a populated table (decisions § 1286)'
);

-- 4.
select is(
  pg_temp.uniqueness_over_subset('public.gym_sets'::regclass,
                                 array['workout_id', 'exercise_key']),
  '',
  'no uniqueness on gym_sets covers a subset of (workout_id, exercise_key) — '
  'one would refuse the second set of any exercise'
);

-- ── The detector is not vacuous ─────────────────────────────────────────────
-- Assertions 3 and 4 read '' from a table that has no uniqueness over either
-- pair today, and would go on reading '' from a derivation that had stopped
-- looking. Each shape the comment above claims to catch is built here on a
-- scratch table of the same column names and read back.

create temp table subset_control (routine_id uuid, exercise_key text, position int);

-- 5. The negative control first: a unique index over a SUPERSET of the pair
--    leaves the pattern representable (the two rows differ in `position`), so
--    the derivation must stay quiet on it. Without this, a derivation that
--    named every unique index would pass 6-9 and be useless.
create unique index subset_control_super
  on subset_control (routine_id, exercise_key, position);

select is(
  pg_temp.uniqueness_over_subset('pg_temp.subset_control'::regclass,
                                 array['routine_id', 'exercise_key']),
  '',
  'a unique index over a superset of the pair is not an offender'
);

-- 6. The shape a nominal guard misses: neither the forbidden index name nor the
--    literal column pair, and it forbids strictly more.
create unique index subset_control_bare on subset_control (exercise_key);

select alike(
  pg_temp.uniqueness_over_subset('pg_temp.subset_control'::regclass,
                                 array['routine_id', 'exercise_key']),
  '%subset_control_bare%',
  'a bare unique (exercise_key) is caught — it forbids the same shape the pair does'
);

drop index subset_control_bare;

-- 7.
create unique index subset_control_expr
  on subset_control (routine_id, lower(exercise_key));

select alike(
  pg_temp.uniqueness_over_subset('pg_temp.subset_control'::regclass,
                                 array['routine_id', 'exercise_key']),
  '%subset_control_expr%',
  'an expression key column fails closed — it may range over exercise_key'
);

drop index subset_control_expr;

-- 8.
create unique index subset_control_partial
  on subset_control (routine_id, exercise_key) where position is null;

select alike(
  pg_temp.uniqueness_over_subset('pg_temp.subset_control'::regclass,
                                 array['routine_id', 'exercise_key']),
  '%subset_control_partial%',
  'a partial unique index is caught — its predicate picks which rows it refuses, '
  'not whether it refuses them'
);

drop index subset_control_partial;

-- 9.
alter table subset_control add constraint subset_control_excl
  exclude using btree (routine_id with =, exercise_key with =);

select alike(
  pg_temp.uniqueness_over_subset('pg_temp.subset_control'::regclass,
                                 array['routine_id', 'exercise_key']),
  '%subset_control_excl%',
  'an all-equality exclusion constraint is caught — its index is not indisunique'
);

select * from finish();
rollback;
