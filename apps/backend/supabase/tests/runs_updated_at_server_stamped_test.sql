-- Pins 20270918000005 (decisions § 2118): `runs.updated_at` is stamped by the
-- server on every INSERT and UPDATE, whatever the writer supplies. The phone's
-- delta pull keys on it, so a client- or archive-supplied value that survived
-- would hide an edit from every other device.
--
-- `now()` is constant for the test's transaction, so "stamped" reads as
-- "equals now()"; the UPDATE cases first plant an old value with the trigger
-- disabled, so a bump is distinguishable from the row keeping its insert time.

begin;
select plan(6);

insert into auth.users (id, aud, role, email, encrypted_password, created_at, updated_at)
values ('0918cccc-0000-0000-0000-0000000000a1', 'authenticated', 'authenticated', 'stamp@rol.local', '', now(), now())
on conflict (id) do nothing;
insert into user_profiles (id, display_name, age_confirmed_at)
values ('0918cccc-0000-0000-0000-0000000000a1', 'Stamp', now())
on conflict (id) do nothing;

select is(
  (select (tgtype & 3)::int from pg_trigger where tgrelid = 'public.runs'::regclass and tgname = 'runs_stamp_updated_at'),
  3,
  'runs_stamp_updated_at is a BEFORE row-level trigger'
);

insert into runs (id, user_id, started_at, duration_s, distance_m, source, is_public,
                  activity_type, is_dnf, updated_at)
values ('0918cccc-0000-0000-0000-0000000000b1', '0918cccc-0000-0000-0000-0000000000a1',
        '2025-01-01T07:00:00Z', 1800, 5000, 'app', false, 'run', false,
        '2001-01-01T00:00:00Z');

select is(
  (select updated_at from runs where id = '0918cccc-0000-0000-0000-0000000000b1'),
  now(),
  'an INSERT carrying an old updated_at (a restored archive row) is stamped with now()'
);

create function pg_temp.plant_old_updated_at()
returns void
language plpgsql as $$
begin
  alter table runs disable trigger runs_stamp_updated_at;
  update runs set updated_at = '2001-01-01T00:00:00Z'
  where id = '0918cccc-0000-0000-0000-0000000000b1';
  alter table runs enable trigger runs_stamp_updated_at;
end;
$$;

select pg_temp.plant_old_updated_at();
select is(
  (select updated_at from runs where id = '0918cccc-0000-0000-0000-0000000000b1'),
  '2001-01-01T00:00:00Z'::timestamptz,
  'the planted value took (the trigger was off for it)'
);

update runs set distance_m = 5100 where id = '0918cccc-0000-0000-0000-0000000000b1';
select is(
  (select updated_at from runs where id = '0918cccc-0000-0000-0000-0000000000b1'),
  now(),
  'an UPDATE of a column bumps updated_at to now()'
);

select pg_temp.plant_old_updated_at();
update runs set metadata = coalesce(metadata, '{}'::jsonb) || '{"title":"renamed on web"}'::jsonb
where id = '0918cccc-0000-0000-0000-0000000000b1';
select is(
  (select updated_at from runs where id = '0918cccc-0000-0000-0000-0000000000b1'),
  now(),
  'a metadata-only edit (the web edit the phone never saw) bumps updated_at'
);

select pg_temp.plant_old_updated_at();
update runs set updated_at = '1999-01-01T00:00:00Z'
where id = '0918cccc-0000-0000-0000-0000000000b1';
select is(
  (select updated_at from runs where id = '0918cccc-0000-0000-0000-0000000000b1'),
  now(),
  'an UPDATE that names updated_at itself is overridden with now()'
);

select * from finish();
rollback;
