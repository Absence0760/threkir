-- Pins 20270918000002 (decisions § 2111): a run write takes its runner's
-- 'achievements:' lock before it touches a row. Two parallel deletes of one
-- runner's runs deadlocked when that lock came only from the statement
-- triggers, because each delete had already locked rows the other needed. The
-- deadlock itself needs two sessions; this pins the ordering that prevents it.
-- `tests-e2e/runs/list.spec.ts` (Select 10 + bulk-delete) is the end-to-end
-- half.

begin;
select plan(5);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('0918bbbb-0000-0000-0000-0000000000a1', 'authenticated', 'authenticated', 'lock@rol.local', '', now(), now())
on conflict (id) do nothing;
insert into user_profiles (id, display_name, age_confirmed_at)
values ('0918bbbb-0000-0000-0000-0000000000a1', 'Lock', now())
on conflict (id) do nothing;

create function pg_temp.holds_achievements_lock(p_user uuid)
returns boolean
language sql as $$
  select exists (
    select 1 from pg_locks l
    where l.locktype = 'advisory'
      and l.pid = pg_backend_pid()
      and l.granted
      and l.mode = 'ExclusiveLock'
      and ((l.classid::bigint << 32) | l.objid::bigint)
          = hashtext('achievements:' || p_user::text)::bigint
  );
$$;

select is(
  (select (tgtype & 1)::int from pg_trigger where tgrelid = 'public.runs'::regclass and tgname = 'runs_lock_caller'),
  0,
  'runs_lock_caller is a statement-level trigger'
);
select is(
  (select (tgtype & 3)::int from pg_trigger where tgrelid = 'public.runs'::regclass and tgname = 'runs_lock_owner'),
  3,
  'runs_lock_owner is a BEFORE row-level trigger'
);

select ok(not pg_temp.holds_achievements_lock('0918bbbb-0000-0000-0000-0000000000a1'),
  'the lock is not held before the write');

set local role authenticated;
set local "request.jwt.claims" = '{"sub":"0918bbbb-0000-0000-0000-0000000000a1","role":"authenticated"}';
-- A delete that matches no row reaches no row trigger and no statement
-- trigger that reads a transition table, so only the BEFORE STATEMENT trigger
-- can have taken the lock.
delete from runs where id = '0918bbbb-0000-0000-0000-00000000ffff';
reset role;

select ok(pg_temp.holds_achievements_lock('0918bbbb-0000-0000-0000-0000000000a1'),
  'a client delete takes the runner''s lock before touching any row');

select lives_ok(
  $$ insert into runs (user_id, started_at, duration_s, distance_m, source, is_public,
                       activity_type, is_dnf)
     values ('0918bbbb-0000-0000-0000-0000000000a1', now(), 1800, 5000, 'app', false,
             'run', false) $$,
  'a service-role insert still writes through the row-level owner lock'
);

select * from finish();
rollback;
